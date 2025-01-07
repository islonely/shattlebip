module main

import core
import net

const server_host = '[::1]:1902'

// initiate_server_connection tries to connect to the server.
fn (mut game Game) initiate_server_connection() {
	if disconnect_idx := game.menu.find('Disconnect') {
		game.menu.items[disconnect_idx].state = .unselected
	}
	game.banner_text_channel <- 'Initiating server connection.'
	game.server = net.dial_tcp(server_host) or {
		game.banner_text_channel <- 'Failed to connect to server.'
		if index := game.menu.find('Disconnect') {
			game.menu.items[index].state = .disabled
		}
		return
	}

	if mut server := game.server {
		server.set_read_timeout(default_read_timeout)
		server.set_write_timeout(default_write_timeout)
		server.set_blocking(true) or {
			game.end(err.msg())
			return
		}
	}

	game.banner_text_channel <- 'Connected to server.'
	game.connected() or {
		game.end(err.msg())
		return
	}
}

// connected handles the game logic after connecting to the server
fn (mut game Game) connected() ! {
	mut server := game.server or { return error('Connection to server lost.') }

	for {
		mut raw_msg := []u8{len: 4}
		server.read(mut raw_msg) or {
			game.banner_text_channel <- 'Failed to read bytes from server: ${err.msg()}'
			continue
		}
		if !core.Message.is_valid_bytes(raw_msg) {
			game.banner_text_channel <- 'Invalid bytes received from server: ${raw_msg.str()}'
			continue
		}

		msg := core.Message.from_bytes(raw_msg) or {
			game.banner_text_channel <- 'Failed to convert bytes to enum Message: ${err.msg()}'
			continue
		}

		if msg == .connection_terminated {
			return
		}

		match game.state {
			.main_menu {
				game.connected_main_menu(msg, raw_msg)!
			}
			.my_turn {
				game.connected_my_turn(msg, raw_msg)!
			}
			.placing_ships {
				game.connected_placing_ships(msg, raw_msg)!
			}
			.their_turn {
				game.connected_their_turn(msg, raw_msg)!
			}
			.wait_for_enemy_ship_placement {
				game.connected_wait_for_enemy_ship_placement(msg, raw_msg)!
			}
		}
	}
}

// connected_main_menu handles the Messages received from the server during
// the .main_menu state.
fn (mut game Game) connected_main_menu(msg core.Message, raw_msg []u8) ! {
	mut server := game.server or { return error('server not set') }

	match msg {
		.added_player_to_queue {
			game.banner_text_channel <- 'No players. Added to queue'
		}
		.paired_with_player {
			game.state = .placing_ships
			game.banner_text_channel <- 'Press R to place your ships randomly'
			core.Message.paired_with_player.write(mut server)!
		}
		else {
			return error('unexpected message: ${msg}')
		}
	}
}

// connected_my_turn handles the Messages received from the server during
// the .my_turn state.
fn (mut game Game) connected_my_turn(msg core.Message, raw_msg []u8) ! {
	match msg {
		.set_cursor_pos {
			game.read_cursor()
		}
		else {
			return error('unexpected message: ${msg}')
		}
	}
}

// connected_placing_ships handles the Messages received from the server during
// the .placing_ships state.
fn (mut game Game) connected_placing_ships(msg core.Message, raw_msg []u8) ! {
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
			return error('unexpected message: ${msg}')
		}
	}
}

// connected_their_turn handles the Messages received from the server during
// the .their_turn state.
fn (mut game Game) connected_their_turn(msg core.Message, raw_msg []u8) ! {
	match msg {
		.set_cursor_pos {
			game.read_cursor()
		}
		.attack_cell {
			mut server := game.server or {
				game.end('server connection interrupted: ${err.msg()}')
				return
			}

			// get cursor pos
			mut pos_bytes := []u8{len: int(sizeof(core.Pos))}
			server.read(mut pos_bytes) or {
				return error('failed to read bytes from server: ${err.msg()}')
			}
			pos := unsafe { core.Pos.from_bytes(pos_bytes) }
			game.enemy_grid.cursor.Pos = pos

			// check if it's their turn
			if game.state == .my_turn {
				nyt_msg := core.Message.not_your_turn
				nyt_msg.write(mut server) or {
					return error('failed to write message (${nyt_msg}): ${err.msg()}')
				}
			}

			// check cell status
			is_cell_occupied := game.player_grid.grid[pos.y][pos.x].state in [
				core.CellState.carrier,
				.battleship,
				.cruiser,
				.submarine,
				.destroyer,
			]
			send_msg := if is_cell_occupied {
				game.player_grid.grid[pos.y][pos.x].state = .hit
				game.banner_text_channel <- 'Hit ${game.player_grid.cursor.val()}! Your turn.'
				core.Message.hit
			} else {
				game.player_grid.grid[pos.y][pos.x].state = .miss
				game.banner_text_channel <- 'Miss. Your turn.'
				core.Message.miss
			}
			send_msg.write(mut server) or {
				game.end('failed to write message (${send_msg}): ${err.msg()}')
				return
			}

			game.state = .my_turn
		}
		else {
			return error('unexpected message: ${msg}')
		}
	}
}

// connected_wait_for_enemy_ship_placement handles the Messages received
// from the server during the .wait_for_enemy_ship_placement state.
fn (mut game Game) connected_wait_for_enemy_ship_placement(msg core.Message, raw_msg []u8) ! {
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
			return error('unexpected message: ${msg}')
		}
	}
}
