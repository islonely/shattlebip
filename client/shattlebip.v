module main

import term.ui as tui
import term
import rand
import net
import core
import util
import time

// 1902 = letters 19 and 02
//		= SB
// 		= ShattleBip
const log_file_path = './shattlebip.log'
const default_read_timeout = time.minute * 5
const default_write_timeout = time.minute * 5

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
					game.network_thread = spawn game.initiate_server_connection()
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
				label: 'Disconnect'
				state: .disabled
				do:    fn [mut game] () {
					game.end('Connection terminated.')
				}
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

// Game is the primary game object.
struct Game {
mut:
	tui                    &tui.Context = unsafe { nil }
	width                  int
	height                 int
	colors                 []core.Color
	state                  core.GameState = .main_menu
	has_enemy_placed_ships bool
	us_starts_game         bool
	ship_needs_placed      []core.CellState = [.carrier, .battleship, .cruiser, .submarine, .destroyer]
	ship_rotated           bool
	menu                   Menu
	banner_text            string      = '                          SHATTLEBIP                          '
	banner_text_channel    chan string = chan string{cap: 100}
	server                 ?&net.TcpConn
	network_thread         thread
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
fn (mut game Game) switch_state(state core.GameState, banner_text string) {
	game.state = state
	game.banner_text_channel <- banner_text
}

// write_cursor sends the position of the enemy cursor to the server.
fn (mut game Game) write_cursor() {
	mut server := game.server or {
		game.end('server connection interrupted: ${err.msg()}')
		return
	}

	core.Message.set_cursor_pos.write(mut server) or {
		game.end('failed to write Message to server: ${err.msg()}')
		return
	}
	pos_bytes := game.enemy_grid.cursor.Pos.to_bytes()
	server.write(pos_bytes) or {
		game.end('Failed to write bytes to server: ${err.msg()}')
		return
	}
}

// read_cursor reads the position of the player cursor from the server.
fn (mut game Game) read_cursor() {
	mut server := game.server or {
		game.end('server connection interrupted: ${err.msg()}')
		return
	}

	mut pos_bytes := []u8{len: int(sizeof(core.Pos))}
	server.read(mut pos_bytes) or {
		game.end('failed to read bytes from server: ${err.msg()}')
		return
	}
	pos := unsafe { core.Pos.from_bytes(pos_bytes) }
	game.player_grid.cursor.Pos = pos
}

// event passes an event to the respective function to be handled
// based on the current game state.
fn event(event &tui.Event, mut game Game) {
	if event.typ == .key_down && event.code == .escape {
		exit(0)
	}

	match game.state {
		.main_menu {
			game.main_menu_event(event)
		}
		.my_turn {
			game.my_turn_event(event)
		}
		.placing_ships {
			game.placing_ships_event(event)
		}
		.their_turn {
			game.their_turn_event(event)
		}
		.wait_for_enemy_ship_placement {
			game.wait_for_enemy_ship_placement_event(event)
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
				.space, .enter { game.menu.selected().do() }
				else {}
			}
		}
		else {}
	}
}

// my_turn_event handles mouse, keyboard, and window events that
// happen during the .my_turn state.
fn (mut game Game) my_turn_event(event &tui.Event) {
	match event.typ {
		.key_down {
			match event.code {
				.left, .right, .up, .down {
					game.move_cursor(event.code, mut game.enemy_grid, true)
				}
				else {}
			}
		}
		else {}
	}
}

// their_turn_event handles mouse, keyboard, and window events that
// happen during the .their turn state.
fn (mut game Game) their_turn_event(event &tui.Event) {
	match event.typ {
		.key_down {
			match event.code {
				.left, .right, .up, .down {
					game.move_cursor(event.code, mut game.enemy_grid, true)
				}
				else {}
			}
		}
		else {}
	}
}

// placing_ships_event handles mouse, keyboard, and window events
// that happen during the .placing_ships state.
fn (mut game Game) placing_ships_event(event &tui.Event) {
	match event.typ {
		.key_down {
			match event.code {
				.r {
					// R press randomly places ships for now
					// TODO: implement choosing where to place your
					// own ships on the grid.
					for game.ship_needs_placed.len > 0 {
						ship := game.ship_needs_placed.last()
						size := core.ship_sizes[ship]
						orientation := unsafe {
							core.Orientation(rand.int_in_range(0, 2) or {
								println('This should never happen: ${err.msg()}')
								exit(1)
							})
						}
						pos := core.Pos.rand()
						game.player_grid.place_ship(ship, size, pos, orientation) or { continue }
						game.ship_needs_placed.pop()
					}

					mut server := game.server or {
						game.end('connection to server interrupted')
						return
					}

					core.Message.placed_ships.write(mut server) or {
						game.end('failed to write message to server: ${err.msg()}')
						return
					}
					if game.has_enemy_placed_ships {
						if game.us_starts_game {
							game.state = .my_turn
							game.banner_text_channel <- 'Game Start! Your turn first.'
						} else {
							game.state = .their_turn
							game.banner_text_channel <- 'Game Start! Their turn first.'
						}
						return
					}

					game.state = .wait_for_enemy_ship_placement
					game.banner_text_channel <- 'waiting for enemy to place their ships'
				}
				.left, .right, .up, .down {
					game.move_cursor(event.code, mut game.player_grid, false)
				}
				else {}
			}
		}
		else {}
	}
}

// wait_for_enemy_ship_placement_event handles events that occur during the
// .wait_for_enemy_ship_placement_event state.
fn (mut game Game) wait_for_enemy_ship_placement_event(event &tui.Event) {
	match event.typ {
		.key_down {
			if event.code in [tui.KeyCode.left, .right, .up, .down] {
				game.move_cursor(event.code, mut game.enemy_grid, false)
			}
		}
		else {}
	}
}

// move_cursor moves the cursor on the grid.
fn (mut game Game) move_cursor(direction tui.KeyCode, mut grid core.Grid, send_to_server bool) {
	match direction {
		.left {
			if grid.cursor.x > 0 {
				grid.cursor.x--
			}
		}
		.right {
			if grid.cursor.x < 9 {
				grid.cursor.x++
			}
		}
		.up {
			if grid.cursor.y > 0 {
				grid.cursor.y--
			}
		}
		.down {
			if grid.cursor.y < 9 {
				grid.cursor.y++
			}
		}
		else {}
	}

	if !send_to_server {
		return
	}
	game.write_cursor()
}

// frame is what is drawn to the terminal UI each frame.
fn frame(mut game Game) {
	game.width, game.height = term.get_terminal_size()
	game.tui.set_cursor_position(0, 0)

	_ := game.banner_text_channel.try_pop(mut game.banner_text)

	match game.state {
		.wait_for_enemy_ship_placement { game.wait_for_enemy_ship_placement_frame() }
		.main_menu { game.main_menu_frame() }
		.placing_ships { game.placing_ships_frame() }
		.my_turn { game.my_turn_frame() }
		.their_turn { game.their_turn_frame() }
	}

	game.tui.set_cursor_position(0, 0)
	game.tui.reset()
	game.tui.flush()
	game.tui.clear()
}

// wait_for_enemy_ship_placement_frame draws the screen in the
// .wait_for_enemy_ship_placement state.
fn (mut game Game) wait_for_enemy_ship_placement_frame() {
	game.draw_game()
}

// main_menu_frame draws the screen in the .main_menu state.
fn (mut game Game) main_menu_frame() {
	game.draw_banner()
	game.menu.draw_center(mut game)
}

// my_turn_frame draws the screen in the .my_turn state.
fn (mut game Game) my_turn_frame() {
	game.draw_game()
}

// placing_ships_frame draws the screen in the .placing_ships state.
fn (mut game Game) placing_ships_frame() {
	game.draw_game()
}

// their_turn_frame draws the screen in the .their_turn state.
fn (mut game Game) their_turn_frame() {
	game.draw_game()
}

// draw_game draws the player grid, enemy player grid, cursor position, and
// banner text to the screen.
fn (mut game Game) draw_game() {
	player := game.player_grid.str()
	enemy := game.enemy_grid.str()
	game.tui.draw_text(0, 0, util.merge_strings(player, enemy, 4, '::'))
	game.tui.draw_text(0, 15, Banner.text(game.banner_text))
	game.tui.draw_text(0, 19, 'Player Cursor: ${game.player_grid.cursor.val()}')
	game.tui.draw_text(0, 20, 'Enemy Cursor: ${game.enemy_grid.cursor.val()}')
}

// draw_text_center draws text to the screen centered on both the horizontal
// and vertical axes.
fn draw_text_center(mut game Game, text string) {
	str_offset := text.len / 2
	game.tui.draw_text(game.width / 2 - str_offset, game.height / 2, text)
}

// end ends a game and closes the connection to the server.
fn (mut game Game) end(msg string) {
	game.state = .main_menu
	game.banner_text_channel <- msg
	if mut server := game.server {
		core.Message.terminate_connection.write(mut server) or {}
		game.network_thread.wait()
		println('foo')
		server.close() or {}
		game.server = none
	}
	if index := game.menu.find('Disconnect') {
		game.menu.items[index].state = .disabled
		game.menu.move_down()
	}
}
