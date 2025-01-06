module main

import core

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
