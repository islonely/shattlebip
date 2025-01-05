module main

import term.ui as tui
import term
import rand
import net
import core
import log
import util
import time

// 1902 = letters 19 and 02
//		= SB
// 		= ShattleBip
const server_host = 'localhost:1902'
const log_file_path = './shattlebip.log'

fn main() {
	w, h := term.get_terminal_size()
	mut game := &Game{
		width:  w
		height: h
		// logger: *log.new_thread_safe_log()
	}
	// lock game.logger {
	// 	game.logger.set_output_path(log_file_path)
	// }
	game.tui = tui.init(
		user_data:   game
		event_fn:    event
		frame_fn:    frame
		hide_cursor: true
	)
	game.menu = Menu{
		label: ''
		items: [
			MenuItem{
				label: 'Online Play'
				state: .unselected
				do:    fn [mut game] () {
					spawn game.initiate_server_connection()
				}
			},
			MenuItem{
				label: 'Offline Play'
				state: .disabled
			},
			MenuItem{
				label: 'Settings'
				state: .disabled
			},
			MenuItem{
				label: 'Quit'
				state: .unselected
				do:    fn () {
					exit(1)
				}
			},
		]
	}
	game.tui.run() or { panic('Failed to run game.') }
}

// GameState is the state the game is currently in.
enum GameState {
	placing_ships
	wait_for_enemy_ship_placement
	main_menu
	my_turn
	their_turn
}

// Game is the primary game object.
struct Game {
mut:
	tui                 &tui.Context = unsafe { nil }
	width               int
	height              int
	colors              []core.Color
	state               GameState        = .main_menu
	ship_needs_placed   []core.CellState = [.carrier, .battleship, .cruiser, .submarine, .destroyer]
	ship_rotated        bool
	menu                Menu
	banner_text         string      = '                          SHATTLEBIP                          '
	banner_text_channel chan string = chan string{cap: 100}
	server              ?&net.TcpConn
	network_thread      thread
	// logger              shared log.ThreadSafeLog

	player_grid core.Grid = core.Grid{
		name:           'Player'
		name_colorizer: fn (str string) string {
			return term.bright_blue(str)
		}
	}
	enemy_grid  core.Grid = core.Grid{
		name:           'Enemy'
		name_colorizer: fn (str string) string {
			return term.bright_red(str)
		}
	}
}

// initiate_server_connection tries to connect to the server.
fn (mut game Game) initiate_server_connection() {
	game.banner_text_channel <- 'Initiating server connection.'
	game.server = net.dial_tcp(server_host) or {
		game.state = GameState.main_menu
		game.banner_text_channel <- 'Failed to connect to server.'
		return
	}
	game.state = .main_menu
	game.banner_text_channel <- 'Connected to server.'

	mut server := game.server or {
		game.banner_text = 'Connection to server lost.'
		game.state = .main_menu
		return
	}

	for {
		msg := core.Message.read(mut server) or {
			game.banner_text_channel <- 'Failed to read bytes from server: ${err.msg()}'
			continue
		}

		match msg {
			.null {
				break
			}
			.paired_with_player {
				game.state = .placing_ships
				game.banner_text_channel <- 'Press space to place ships.'
				break
			}
			else {
				game.banner_text_channel <- 'Unexpected message from server: ${msg}'
				continue
			}
		}
	}
}

// draw_banner converts the Game.banner_text variable to the correct text
// and draws it to the screen.
fn (mut game Game) draw_banner() {
	banner := Banner.text(game.banner_text)
	for i, line in banner.split_into_lines() {
		x := (game.width / 2) - (line.len / 2)
		game.tui.draw_text(x, i + 2, line)
	}
}

// switch_state sets the game to the specified state. And sets the banner text
// to the specified text. As well as flushed and clears the terminal UI.
fn (mut game Game) switch_state(state GameState, banner_text string) {
	game.tui.flush()
	game.tui.clear()
	game.state = state
	game.banner_text = banner_text
}

// tcp_write_cursor sends the Game.cursor field encoded in hexadecimal to the server.
fn (mut game Game) tcp_write_cursor() {
	mut server := game.server or {
		game.switch_state(.main_menu, 'Server connection interrupted')
		return
	}

	mut cursor_pos_bytes := []u8{cap: 4}
	cursor_pos_bytes << core.messages['client']['cursor_position']
	cursor_pos_bytes << [u8(game.player_grid.cursor.x), u8(game.player_grid.cursor.y)]
	server.write(cursor_pos_bytes) or {
		game.switch_state(.main_menu, 'Failed to write to server: ${err.msg()}')
		return
	}
}

// event passes an event to the respective function to be handled
// based on the current game state.
fn event(e &tui.Event, mut game Game) {
	if e.typ == .key_down && e.code == .escape {
		exit(0)
	}

	match game.state {
		.main_menu {
			game.main_menu_event(e)
		}
		.my_turn {
			game.my_turn_event(e)
		}
		.placing_ships {
			game.placing_ships_event(e)
		}
		else {
			game.banner_text = 'No keybinds setup for state: ${game.state}'
		}
	}
}

// main_menu_event handles mouse, keyboard, and window events that
// hgameen during the .main_menu state.
fn (mut game Game) main_menu_event(event &tui.Event) {
	match event.typ {
		.key_down {
			match event.code {
				.up { game.menu.move_up() }
				.down { game.menu.move_down() }
				.space { game.menu.selected().do() }
				else {}
			}
		}
		else {}
	}
}

// my_turn_event handles mouse, keyboard, and window events that
// hgameen during the .my_turn state.
fn (mut game Game) my_turn_event(event &tui.Event) {
	match event.typ {
		.key_down {}
		else {}
	}
}

// placing_ships_event handles mouse, keyboard, and window events
// that hgameen during the .placing_ships state.
fn (mut game Game) placing_ships_event(event &tui.Event) {
	match event.typ {
		.key_down {
			match event.code {
				.space {
					// space press randomly places ships for now
					// TODO: implement choosing where to place your
					// own ships on the grid.
					for game.ship_needs_placed.len > 0 {
						ship := game.ship_needs_placed.last()
						size := core.ship_sizes[ship]
						orientation := unsafe {
							core.Orientation(rand.int_in_range(0, 2) or {
								println('This should never hgameen: ${err.msg()}')
								exit(1)
							})
						}
						pos := core.Pos.rand()
						game.player_grid.place_ship(ship, size, pos, orientation) or { continue }
						game.ship_needs_placed.pop()
					}
				}
				else {}
			}
		}
		else {}
	}
}

// frame is what is drawn to the terminal UI each frame.
fn frame(mut game Game) {
	game.width, game.height = term.get_terminal_size()
	game.tui.set_cursor_position(0, 0)

	// _ := game.state_channel.try_pop(mut game.state)
	_ := game.banner_text_channel.try_pop(mut game.banner_text)

	match game.state {
		.wait_for_enemy_ship_placement {}
		.main_menu { game.main_menu_frame() }
		.placing_ships { game.placing_ships_frame() }
		.my_turn { game.my_turn_frame() }
		.their_turn { game.their_turn_frame() }
	}

	game.tui.set_cursor_position(0, 0)
	game.tui.reset()
	game.tui.flush()
	game.tui.clear()
	time.sleep(time.millisecond * 333)
}

// connection_established_frame draws the screen in the
// .conection_established state.
// fn (mut game Game) connection_established_frame() {
// 	mut server := game.server or {
// 		game.banner_text = 'Connection to server lost.'
// 		game.state = .main_menu
// 		return
// 	}

// 	game.banner_text = 'Connection to server established.'
// 	for {
// 		mut buf := []u8{len: 2}
// 		server.read(mut buf) or {
// 			game.banner_text = 'Failed to read bytes from server: ${err.msg()}'
// 			continue
// 		}

// 		buffer_is_empty := buf[0] == 0 && buf[1] == 0
// 		if buffer_is_empty {
// 			break
// 		}

// 		game.banner_text = '$: ${buf.bytestr()}'

// 		if buf == core.messages['server']['paired_with_player'] {
// 			game.state = .placing_ships
// 			game.banner_text = 'Press space to place ships.'
// 			break
// 		}
// 	}
// 	game.main_menu_frame()
// }

// main_menu_frame draws the screen in the .main_menu state.
fn (mut game Game) main_menu_frame() {
	game.draw_banner()
	game.menu.draw_center(mut game)
}

// my_turn_frame draws the screen in the .my_turn state.
fn (mut game Game) my_turn_frame() {
	player := game.player_grid.string(game.player_grid.cursor)
	enemy := game.enemy_grid.string(game.player_grid.cursor)
	game.tui.draw_text(0, 0, util.merge_strings(player, enemy, 4, '::'))
	game.tui.draw_text(0, 15, Banner.text(game.banner_text))
	game.tui.draw_text(0, 19, 'My Cursor: ${game.player_grid.cursor.val()}')
	game.tui.draw_text(0, 19, 'Their Cursor: ${game.enemy_grid.cursor.val()}')
}

// placing_ships_frame draws the screen in the .placing_ships state.
fn (mut game Game) placing_ships_frame() {
	player := game.player_grid.string(game.player_grid.cursor)
	enemy := game.enemy_grid.string(game.enemy_grid.cursor)
	game.tui.draw_text(0, 0, util.merge_strings(player, enemy, 4, '::'))
	game.tui.draw_text(0, 15, Banner.text(game.banner_text))
	game.tui.draw_text(0, 19, 'My Cursor: ${game.player_grid.cursor.val()}')
	game.tui.draw_text(0, 19, 'Their Cursor: ${game.enemy_grid.cursor.val()}')
}

// their_turn_frame draws the screen in the .their_turn state.
fn (mut game Game) their_turn_frame() {
	player := game.player_grid.string(game.player_grid.cursor)
	enemy := game.enemy_grid.string(game.enemy_grid.cursor)
	game.tui.draw_text(0, 0, util.merge_strings(player, enemy, 4, '::'))
	game.tui.draw_text(0, 15, Banner.text(game.banner_text))
	game.tui.draw_text(0, 19, 'My Cursor: ${game.player_grid.cursor.val()}')
	game.tui.draw_text(0, 19, 'Their Cursor: ${game.enemy_grid.cursor.val()}')
}

// draw_text_center draws text to the screen centered on both the horizontal
// and vertical axes.
fn draw_text_center(mut game Game, text string) {
	str_offset := text.len / 2
	game.tui.draw_text(game.width / 2 - str_offset, game.height / 2, text)
}
