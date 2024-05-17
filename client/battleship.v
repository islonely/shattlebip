module main

import term.ui as tui
import term
import rand
import net
import islonely.hex
import core
import util

// 1902 = letters 19 and 02
//		= SB
// 		= ShattleBip
const server_host = 'localhost:1902'

fn main() {
	w, h := term.get_terminal_size()
	mut app := &App{
		width: w
		height: h
	}
	app.tui = tui.init(
		user_data: app
		event_fn: event
		frame_fn: frame
		hide_cursor: true
	)
	app.menu = Menu{
		label: ''
		items: [
			MenuItem{
				label: 'Online Play'
				state: .unselected
				do: fn [mut app] () {
					app.tui.clear()
					app.tui.reset()
					app.state = .initiate_server_connection
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
				do: fn () {
					exit(1)
				}
			},
		]
	}
	app.tui.run() or { panic('Failed to run app.') }
}

// GameState is the state the game is currently in.
enum GameState {
	placing_ships
	wait_for_enemy_ship_placement
	main_menu
	initiate_server_connection
	connection_established
	my_turn
	their_turn
}

// App is the primary game object.
struct App {
mut:
	tui                  &tui.Context = unsafe { nil }
	width                int
	height               int
	colors               []core.Color
	cursor               core.Cursor
	state                GameState        = .main_menu
	ship_needs_placed    []core.CellState = [.carrier, .battleship, .cruiser, .submarine, .destroyer]
	ship_rotated         bool
	menu                 Menu
	banner_text          string = '                          SHATTLEBIP                          '
	server               ?&net.TcpConn
	waiting_for_response thread

	player core.Grid = core.Grid{
		name: 'Player'
		name_colorizer: fn (str string) string {
			return term.bright_blue(str)
		}
	}
	enemy core.Grid = core.Grid{
		name: 'Enemy'
		name_colorizer: fn (str string) string {
			return term.bright_red(str)
		}
	}
}

// switch_state sets the game to the specified state. And sets the banner text
// to the specified text. As well as flushed and clears the terminal UI.
fn (mut app App) switch_state(state GameState, banner_text string) {
	app.tui.flush()
	app.tui.clear()
	app.state = state
	app.banner_text = banner_text
}

// tcp_write_cursor sends the App.cursor field encoded in hexadecimal to the server.
fn (mut app App) tcp_write_cursor() {
	mut server := app.server or {
		app.switch_state(.main_menu, 'Server connection interrupted')
		return
	}

	server.write(core.messages['client']['cursor_position']) or {
		app.switch_state(.main_menu, 'Failed to write to server: ${err.msg()}')
		return
	}
	bytes := hex.encode_struct(app.cursor) or {
		app.switch_state(.main_menu, 'Failed to encode Cursor: ${err.msg()}')
		return
	}
	server.write_string(bytes.bytestr()) or {
		app.switch_state(.main_menu, 'Failed to write to server: ${err.msg()}')
		return
	}
}

// event handles keypresses among other events that may occur.
fn event(e &tui.Event, mut app App) {
	if e.typ == .key_down && e.code == .escape {
		exit(0)
	}

	if e.typ == .key_down {
		match e.code {
			.down {
				match app.state {
					.placing_ships {
						if _likely_(app.cursor.y < 9) {
							app.cursor.y++
						}
					}
					.main_menu {
						app.menu.move_down()
					}
					.my_turn {
						if _likely_(app.cursor.y < 9) {
							app.cursor.y++
						}
						app.tcp_write_cursor()
					}
					else {}
				}
			}
			.up {
				match app.state {
					.placing_ships {
						if _likely_(app.cursor.y > 0) {
							app.cursor.y--
						}
					}
					.main_menu {
						app.menu.move_up()
					}
					.my_turn {
						if _likely_(app.cursor.y < 9) {
							app.cursor.y--
						}
						app.tcp_write_cursor()
					}
					else {}
				}
			}
			.left {
				match app.state {
					.placing_ships {
						if _likely_(app.cursor.x > 0) {
							app.cursor.x--
						}
					}
					.main_menu {}
					.my_turn {
						if _likely_(app.cursor.y < 9) {
							app.cursor.x--
						}
						app.tcp_write_cursor()
					}
					else {}
				}
			}
			.right {
				match app.state {
					.placing_ships {
						if _likely_(app.cursor.x < 9) {
							app.cursor.x++
						}
					}
					.main_menu {}
					.my_turn {
						if _likely_(app.cursor.y < 9) {
							app.cursor.x++
						}
						app.tcp_write_cursor()
					}
					else {}
				}
			}
			.space {
				app.handle_space_press()
			}
			.enter {
				app.handle_space_press()
			}
			else {}
		}
	}
}

// handle_space_press handles the press of the space key.
fn (mut app App) handle_space_press() {
	app.cursor.select_pos()
	match app.state {
		.placing_ships {
			for app.ship_needs_placed.len > 0 {
				ship := app.ship_needs_placed.pop()
				size := core.ship_sizes[ship]
				// orientation of the ship
				o := unsafe {
					core.Orientation(rand.int_in_range(0, 2) or {
						panic('This should never happen.')
					})
				}
				pos := core.Pos.rand()
				app.player.place_ship(ship, size, pos, o) or {
					app.ship_needs_placed << ship
					continue
				}
			}

			mut server := app.server or {
				app.switch_state(.main_menu, 'Server connection interrupted.')
				return
			}

			// let server know we have placed ships
			app.banner_text = 'Waiting for openent to place ships.'
			server.write(core.messages['client']['ships_placed']) or {
				app.switch_state(.main_menu, 'Failed to write to server: ${err.msg()}')
				return
			}

			// wait for other player to place ships
			spawn fn [mut app, mut server] () {
				mut response := []u8{len: 2}
				server.read(mut response) or {
					app.switch_state(.main_menu, 'Failed to read from server: ${err.msg()}')
					return
				}
				if response != core.messages['client']['ships_placed'] {
					app.switch_state(.main_menu, 'Received invalid bytes from oponent; connection terminated.')
					server.close() or {}
					return
				}

				app.banner_text = 'Oponent has placed their ships.'

				// receive bytes to determine if I am start or end player
				response = []u8{len: 2}
				server.read(mut response) or {
					app.state = .main_menu
					app.banner_text = 'Failed to read from server: ${err.msg()}'
					app.tui.clear()
					return
				}
				match response {
					core.messages['server']['start_player'] {
						app.state = .my_turn
						app.banner_text = "It's your turn! Select a location to obliterate."
						app.tui.clear()
						app.tcp_write_cursor()
						return
					}
					core.messages['server']['end_player'] {
						app.state = .their_turn
						app.banner_text = "It's their turn. Please wait for your demise."
						app.tui.clear()
						app.waiting_for_response = spawn fn [mut app, mut server] () {
							for {
								mut buf := []u8{len: 2}
								server.read(mut buf) or {
									app.switch_state(.main_menu, 'Failed to read from server: ${err.msg()}')
									return
								}
								match buf {
									core.messages['client']['cursor_position'] {
										hex_cursor := server.read_line().bytes()
										if hex_cursor.len == 0 {
											app.switch_state(.main_menu, 'Invalid bytes after cursor prefix: ${hex_cursor}')
											return
										}
										app.cursor = hex.decode_struct[core.Cursor](hex_cursor) or {
											app.switch_state(.main_menu, 'Invalid bytes in cursor hex: ${hex_cursor}')
											return
										}
									}
									else {
										app.switch_state(.main_menu, 'Invalid bytes received from server: ${buf}')
										return
									}
								}
							}
						}()
					}
					else {
						app.state = .main_menu
						app.banner_text = 'Received invalid bytes from server; connection terminated.'
						app.tui.clear()
						return
					}
				}
			}()
		}
		.main_menu {
			app.menu.selected().do()
		}
		else {}
	}
}

// frame is what is drawn to the terminal UI each frame.
fn frame(mut app App) {
	app.width, app.height = term.get_terminal_size()
	app.tui.set_cursor_position(0, 0)

	match app.state {
		.wait_for_enemy_ship_placement {}
		.main_menu {
			banner := Banner.text(app.banner_text)
			for i, line in banner.split_into_lines() {
				x := (app.width / 2) - (line.len / 2)
				app.tui.draw_text(x, i + 2, line)
			}

			app.menu.draw_center(mut app)
		}
		.placing_ships {
			player := app.player.string(app.cursor)
			enemy := app.enemy.string(core.Cursor{ x: -1, y: -1 })
			app.tui.draw_text(0, 0, util.merge_strings(player, enemy, 4, '::'))
			app.tui.draw_text(0, 15, Banner.text(app.banner_text))
			app.tui.draw_text(0, 19, 'POS: ${app.cursor.val()}')
		}
		.initiate_server_connection {
			app.tui.draw_text(1, 1, 'Initiating connection to server...')
			app.tui.flush()
			app.server = net.dial_tcp(server_host) or {
				println('Could not connect to server: ${err.msg()}')
				app.tui.clear()
				app.tui.flush()
				app.state = .main_menu
				app.banner_text = 'Failed to connect to server.'
				return
			}
			app.state = .connection_established
			app.tui.clear()
			app.tui.reset()
		}
		.connection_established {
			mut server := app.server or {
				app.tui.draw_text(1, 1, 'Connection to server failed.')
				app.tui.flush()
				return
			}

			app.tui.draw_text(1, 1, 'Connection to server established.')
			mut i := 1
			for {
				i++
				line := server.read_line()
				if line == '' {
					break
				}

				app.tui.draw_text(1, i, '[Server] ${line}')
				app.tui.flush()

				if line == 'Paired with player. Game will start soon.\n' {
					app.state = .placing_ships
					app.banner_text = 'Press space to place ships.'
					app.tui.clear()
					return
				}
			}
			app.tui.flush()
		}
		.my_turn {
			player := app.player.string(core.Cursor{ x: -1, y: -1 })
			enemy := app.enemy.string(app.cursor)
			app.tui.draw_text(0, 0, util.merge_strings(player, enemy, 4, '::'))
			app.tui.draw_text(0, 15, Banner.text(app.banner_text))
			app.tui.draw_text(0, 19, 'POS: ${app.cursor.val()}')
			app.tui.flush()
		}
		.their_turn {
			player := app.player.string(app.cursor)
			enemy := app.enemy.string(core.Cursor{ x: -1, y: -1 })
			app.tui.draw_text(0, 0, util.merge_strings(player, enemy, 4, '::'))
			app.tui.draw_text(0, 15, Banner.text(app.banner_text))
			app.tui.draw_text(0, 19, 'POS: ${app.cursor.val()}')
			app.tui.flush()
		}
	}

	// app.tui.set_cursor_position(0, 0)
	// app.tui.reset()
	app.tui.flush()
	// app.tui.clear()
}

// draw_text_center draws text to the screen centered on both the horizontal
// and vertical axes.
fn draw_text_center(mut app App, text string) {
	str_offset := text.len / 2
	app.tui.draw_text(app.width / 2 - str_offset, app.height / 2, text)
}
