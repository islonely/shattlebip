module main

import core
import net
import time

// initiate_server_connection tries to connect to the server. When the player
// chose "find new opponent" it reconnects and rejoins the queue.
fn (mut game Game) initiate_server_connection() {
	for {
		game.want_requeue = false
		if disconnect_idx := game.menu.find('Disconnect') {
			game.menu.items[disconnect_idx].state = .unselected
		}
		game.banner_text_channel <- 'Initiating server connection.'
		mut conn := net.dial_tcp(game.server_addr) or {
			game.banner_text_channel <- 'Failed to connect to server.'
			if index := game.menu.find('Disconnect') {
				game.menu.items[index].state = .disabled
			}
			return
		}
		game.server = core.BufferedTcpConn.new(mut conn)
		game.server.sock.set_option_bool(.keep_alive, true) or {
			game.end('Could not set socket to keep alive: ${err}')
			return
		}
		game.server.set_read_timeout(default_read_timeout)
		game.server.set_write_timeout(default_write_timeout)

		// fresh boards and a clean menu for this connection
		game.reset_grids()
		game.state = .main_menu
		game.banner_text_channel <- 'Connected to server.'

		mut err_msg := ''
		game.connected() or {
			err_msg = err.msg()
		}
		if game.want_requeue {
			continue
		}
		game.end(err_msg)
		return
	}
}

// connected handles the game logic after connecting to the server
fn (mut game Game) connected() ! {
	for {
		msg_sz := int(sizeof(core.Message))
		raw_msg := game.server.read_chunk(msg_sz) or {
			if err.code() == net.error_ewouldblock {
				time.sleep(10 * time.millisecond)
				continue
			}
			return err
		}
		if !core.Message.is_valid_bytes(raw_msg) {
			game.banner_text_channel <- 'invalid bytes received from server: ${raw_msg.str()}'
			continue
		}

		msg := core.Message.from_bytes(raw_msg)!

		if msg == .connection_terminated {
			return
		}

		match game.state {
			.main_menu {
				game.connected_main_menu(msg)!
			}
			.my_turn {
				game.connected_my_turn(msg)!
			}
			.placing_ships {
				game.connected_placing_ships(msg)!
			}
			.their_turn {
				game.connected_their_turn(msg)!
			}
			.wait_for_enemy_ship_placement {
				game.connected_wait_for_enemy_ship_placement(msg)!
			}
			.game_over {
				game.connected_game_over(msg)!
			}
		}
	}
}

// connected_main_menu handles the Messages received from the server during
// the .main_menu state.
fn (mut game Game) connected_main_menu(msg core.Message) ! {
	match msg {
		.added_player_to_queue {
			game.banner_text_channel <- 'No players. Added to queue'
		}
		.paired_with_player {
			game.switch_state(.placing_ships, 'Place your ships to begin.')
			game.write_message(core.Message.paired_with_player)!
			game.server.flush()!
		}
		else {
			return error('${game.state} unexpected message: ${msg}')
		}
	}
}

// connected_my_turn handles the Messages received from the server during
// the .my_turn state.
fn (mut game Game) connected_my_turn(msg core.Message) ! {
	match msg {
		.set_cursor_pos {
			game.read_cursor()
		}
		.hit, .miss, .not_your_turn, .opponent_defeated, .opponent_resigned {
			game.handle_attack_reply(msg)
		}
		else {
			return error('${game.state} unexpected message: ${msg}')
		}
	}
}

// handle_attack_reply applies the server's response to the player's own
// last attack. It is handled by the network thread, the only socket reader.
fn (mut game Game) handle_attack_reply(msg core.Message) {
	pos := game.last_attack_pos
	match msg {
		.hit {
			game.enemy_grid.grid[pos.y][pos.x].state = .hit
			game.banner_text_channel <- 'Hit ${game.enemy_grid.cursor.val()}! Their turn.'
		}
		.miss {
			game.enemy_grid.grid[pos.y][pos.x].state = .miss
			game.banner_text_channel <- 'Miss. Their turn.'
		}
		.not_your_turn {
			game.banner_text_channel <- "It's not your turn."
		}
		.opponent_defeated {
			game.enemy_grid.grid[pos.y][pos.x].state = .hit
			game.enter_game_over(true, 'You win! Enemy fleet destroyed.')
			return
		}
		.opponent_resigned {
			game.enter_game_over(true, 'You win! Opponent resigned.')
			return
		}
		else {}
	}
	game.switch_state(.their_turn, none)
}

// connected_placing_ships handles the Messages received from the server during
// the .placing_ships state.
fn (mut game Game) connected_placing_ships(msg core.Message) ! {
	match msg {
		.start_player {
			game.us_starts_game = true
		}
		.not_start_player {
			game.us_starts_game = false
		}
		.set_cursor_pos {
			game.read_cursor()
		}
		.placed_ships {
			game.has_enemy_placed_ships = true
		}
		else {
			return error('${game.state} unexpected message: ${msg}')
		}
	}
}

// connected_their_turn handles the Messages received from the server during
// the .their_turn state.
fn (mut game Game) connected_their_turn(msg core.Message) ! {
	match msg {
		.set_cursor_pos {
			game.read_cursor()
		}
		.hit, .miss, .not_your_turn, .opponent_defeated, .opponent_resigned {
			game.handle_attack_reply(msg)
		}
		.attack_cell {
			// get cursor pos
			pos_sz := int(sizeof(core.Pos))
			pos_bytes := game.server.read_chunk(pos_sz)!
			pos := unsafe { core.Pos.from_bytes(pos_bytes) }
			game.player_grid.cursor.Pos = pos
			game.start_flash(pos, false)

			// check cell status
			is_cell_occupied := game.player_grid.grid[pos.y][pos.x].state in [
				core.CellState.carrier,
				.battleship,
				.cruiser,
				.submarine,
				.destroyer,
			]
			existing := game.player_grid.grid[pos.y][pos.x].state
			if existing in [core.CellState.hit, core.CellState.miss] {
				// this cell was already resolved; echo the old result so an
				// accidental repeat attack cannot turn a hit into a miss
				game.write_message(if existing == .hit {
					core.Message.hit
				} else {
					core.Message.miss
				})!
				game.server.flush()!
				return
			}
			if is_cell_occupied {
				game.player_grid.grid[pos.y][pos.x].state = .hit
				// the fleet is gone, so this player has lost the round
				if game.player_grid.all_ships_sunk() {
					game.write_message(core.Message.defeated)!
					game.server.flush()!
					game.enter_game_over(false, 'You lose! Your fleet was destroyed.')
					return
				}
				game.banner_text_channel <- 'Hit ${game.player_grid.cursor.val()}! Your turn.'
				game.write_message(core.Message.hit)!
			} else {
				game.player_grid.grid[pos.y][pos.x].state = .miss
				game.banner_text_channel <- 'Miss. Your turn.'
				game.write_message(core.Message.miss)!
			}
			game.server.flush()!

			game.switch_state(.my_turn, none)
		}
		else {
			return error('${game.state} unexpected message: ${msg}')
		}
	}
}

// connected_wait_for_enemy_ship_placement handles the Messages received
// from the server during the .wait_for_enemy_ship_placement state.
fn (mut game Game) connected_wait_for_enemy_ship_placement(msg core.Message) ! {
	match msg {
		.placed_ships {
			game.has_enemy_placed_ships = true
			if game.us_starts_game {
				game.switch_state(.my_turn, 'Game start! Your turn first.')
			} else {
				game.switch_state(.their_turn, 'Game start! Their turn first.')
			}
		}
		else {
			return error('${game.state} unexpected message: ${msg}')
		}
	}
}

// connected_game_over handles the Messages received from the server during
// the .game_over state.
fn (mut game Game) connected_game_over(msg core.Message) ! {
	match msg {
		.rematch_start {
			game.reset_grids()
			game.switch_state(.placing_ships, 'Rematch! Place your ships.')
		}
		.opponent_requested_rematch {
			game.opponent_requested_rematch = true
			game.banner_text_channel <- 'Opponent wants a rematch!'
		}
		.opponent_left {
			game.end('Opponent left the game.')
		}
		.set_cursor_pos {
			game.read_cursor()
		}
		else {
			return error('${game.state} unexpected message: ${msg}')
		}
	}
}

// write_message attempts to write a message to the server.
@[inline]
fn (mut game Game) write_message(msg core.Message) ! {
	game.server.write_buffered(msg.to_bytes())
}

// write_cursor sends the position of the enemy cursor to the server.
fn (mut game Game) write_cursor() {
	pos_bytes := game.enemy_grid.cursor.Pos.to_bytes()
	game.server.write_buffered(pos_bytes)
	game.server.flush() or {
		game.end(err.msg())
		return
	}
}

// read_cursor reads the position of the player cursor from the server.
fn (mut game Game) read_cursor() {
	pos_sz := int(sizeof(core.Pos))
	pos_bytes := game.server.read_chunk(pos_sz) or {
		if err.code() == net.error_ewouldblock {
			time.sleep(10 * time.millisecond)
			game.read_cursor()
		}
		game.banner_text_channel <- 'failed to read bytes from server: ${err.msg()}'
		return
	}
	pos := unsafe { core.Pos.from_bytes(pos_bytes) }
	game.player_grid.cursor.Pos = pos
}
