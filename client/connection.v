module main

import core
import net
import time

const server_host = '[::1]:1902'

// initiate_server_connection tries to connect to the server.
fn (mut game Game) initiate_server_connection() {
	if disconnect_idx := game.menu.find('Disconnect') {
		game.menu.items[disconnect_idx].state = .unselected
	}
	game.banner_text_channel <- 'Initiating server connection.'
	mut conn := net.dial_tcp(server_host) or {
		game.banner_text_channel <- 'Failed to connect to server.'
		if index := game.menu.find('Disconnect') {
			game.menu.items[index].state = .disabled
		}
		return
	}
	game.server = core.BufferedTcpConn.new(mut conn)
	game.server.set_read_timeout(default_read_timeout)
	game.server.set_write_timeout(default_write_timeout)

	game.banner_text_channel <- 'Connected to server.'
	game.connected() or {
		game.end(err.msg())
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
			game.state = .placing_ships
			game.banner_text_channel <- 'Press R to place your ships randomly'
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
		else {
			return error('${game.state} unexpected message: ${msg}')
		}
	}
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
		.attack_cell {
			// get cursor pos
			pos_sz := int(sizeof(core.Pos))
			pos_bytes := game.server.read_chunk(pos_sz)!
			pos := unsafe { core.Pos.from_bytes(pos_bytes) }
			game.player_grid.cursor.Pos = pos

			// check if it's their turn
			if game.state == .my_turn {
				nyt_msg := core.Message.not_your_turn
				game.write_message(nyt_msg)!
				game.server.flush()!
				return
			}

			// check cell status
			is_cell_occupied := game.player_grid.grid[pos.y][pos.x].state in [
				core.CellState.carrier,
				.battleship,
				.cruiser,
				.submarine,
				.destroyer,
			]
			// update cell state and send state to server
			send_msg := if is_cell_occupied {
				game.player_grid.grid[pos.y][pos.x].state = .hit
				game.banner_text_channel <- 'Hit ${game.player_grid.cursor.val()}! Your turn.'
				core.Message.hit
			} else {
				game.player_grid.grid[pos.y][pos.x].state = .miss
				game.banner_text_channel <- 'Miss. Your turn.'
				core.Message.miss
			}
			game.write_message(send_msg)!
			game.server.flush()!

			game.state = .my_turn
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
				game.state = .my_turn
				game.banner_text_channel <- 'Game start! Your turn first.'
			} else {
				game.state = .their_turn
				game.banner_text_channel <- 'Game start! Their turn first.'
			}
		}
		else {
			return error('${game.state} unexpected message: ${msg}')
		}
	}
}

// read_message attempts to get a message from the server.
fn (mut game Game) read_message() !core.Message {
	msg_sz := int(sizeof(core.Message))
	msg_bytes := game.server.read_chunk(msg_sz)!
	if !core.Message.is_valid_bytes(msg_bytes) {
		return .invalid_bytes
	}

	return core.Message.from_bytes(msg_bytes) or {
		game.end(err.msg())
		return .invalid_bytes
	}
}

// write_message attempts to write a message to the server.
@[inline]
fn (mut game Game) write_message(msg core.Message) ! {
	game.server.write(msg.to_bytes())
}

// write_cursor sends the position of the enemy cursor to the server.
fn (mut game Game) write_cursor() {
	pos_bytes := game.enemy_grid.cursor.Pos.to_bytes()
	game.server.write(pos_bytes)
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
