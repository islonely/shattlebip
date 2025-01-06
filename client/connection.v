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
		return
	}

	if mut server := game.server {
		server.set_read_timeout(default_read_timeout)
		server.set_write_timeout(default_write_timeout)
	}

	game.banner_text_channel <- 'Connected to server.'
	game.connected()
}

// connected handles the game logic after connecting to the server
fn (mut game Game) connected() {
	mut server := game.server or {
		game.end('Connection to server lost.')
		return
	}

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
				game.connected_main_menu(msg, raw_msg)
			}
			.my_turn {
				game.connected_my_turn(msg, raw_msg)
			}
			.placing_ships {
				game.connected_placing_ships(msg, raw_msg)
			}
			.their_turn {
				game.connected_their_turn(msg, raw_msg)
			}
			.wait_for_enemy_ship_placement {
				game.connected_wait_for_enemy_ship_placement(msg, raw_msg)
			}
		}
	}
}

// connected_main_menu handles the Messages received from the server during
// the .main_menu state.
fn (mut game Game) connected_main_menu(msg core.Message, raw_msg []u8) {
	match msg {
		.added_player_to_queue {
			game.banner_text_channel <- 'No players. Added to queue'
		}
		.paired_with_player {
			game.state = .placing_ships
			game.banner_text_channel <- 'Press R to place your ships randomly'
		}
		else {
			game.end('Closing connection. Unexpected message received: ${msg}')
		}
	}
}

// connected_my_turn handles the Messages received from the server during
// the .my_turn state.
fn (mut game Game) connected_my_turn(msg core.Message, raw_msg []u8) {
	match msg {
		.set_cursor_pos {
			game.read_cursor()
		}
		else {
			game.end('Closing connection. Unuxepected message received: ${msg}')
		}
	}
}

// connected_placing_ships handles the Messages received from the server during
// the .placing_ships state.
fn (mut game Game) connected_placing_ships(msg core.Message, raw_msg []u8) {
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
			game.end('Closing connection. Unexpected Message from server: ${msg}')
		}
	}
}

// connected_their_turn handles the Messages received from the server during
// the .their_turn state.
fn (mut game Game) connected_their_turn(msg core.Message, raw_msg []u8) {
	match msg {
		.set_cursor_pos {
			game.read_cursor()
		}
		else {
			game.end('Closing connection. Unexpected message received: ${msg}')
		}
	}
}

// connected_wait_for_enemy_ship_placement handles the Messages received
// from the server during the .wait_for_enemy_ship_placement state.
fn (mut game Game) connected_wait_for_enemy_ship_placement(msg core.Message, raw_msg []u8) {
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
			game.end('Closing connection. Unexpected message received: ${msg}')
		}
	}
}
