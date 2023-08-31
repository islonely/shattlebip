module main

import term.ui as tui
import term
import rand
import net
import islonely.hex
import core

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

enum GameState {
	placing_ships
	wait_for_enemy_ship_placement
	main_menu
	initiate_server_connection
	connection_established
}

struct App {
mut:
	tui               &tui.Context = unsafe { nil }
	width             int
	height            int
	colors            []core.Color
	cursor            core.Cursor
	state             GameState        = .main_menu
	ship_needs_placed []core.CellState = [.carrier, .battleship, .cruiser, .submarine, .destroyer]
	ship_rotated      bool
	menu              Menu
	banner_text       string
	server            ?&net.TcpConn

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
			app.banner_text = 'Waiting for openent to place ships.'

			// app.state = .wait_for_enemy_ship_placement

			// something should probably be done to allow the user
			// to place their own ships, but I can't come up with
			// a good system right now to do that

			// if !app.cursor.last().is_null() {
			// 	size := ship_sizes[app.ship_needs_placed.last()]
			// 	cur := app.cursor.selected
			// 	last := app.cursor.last()
			// 	ymin := math.min(cur.y, last.y)
			// 	ymax := math.max(cur.y, last.y) + 1
			// 	xmin := math.min(cur.x, last.x)
			// 	xmax := math.max(cur.x, last.x) + 1
			// 	for y in ymin .. ymax {
			// 		for x in xmin .. xmax {
			// 			app.player.grid[y][x] = Cell{.neutral, .friendly_boat}
			// 		}
			// 	}
			// 	app.cursor.nullify()
			// } else {
			// 	app.player.grid[app.cursor.y][app.cursor.x] = Cell{.neutral, .friendly_boat}
			// }
		}
		.main_menu {
			app.menu.selected().do()
		}
		else {}
	}
}

fn frame(mut app App) {
	app.width, app.height = term.get_terminal_size()
	app.tui.set_cursor_position(0, 0)

	match app.state {
		.wait_for_enemy_ship_placement {}
		.main_menu {
			app.menu.draw_center(mut app)
		}
		.placing_ships {
			player := app.player.string(app.cursor)
			enemy := app.enemy.string(core.Cursor{ x: -1, y: -1 })
			app.tui.draw_text(0, 0, merge_strings(player, enemy, 4, '::'))
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
	}

	// m := Menu{
	// 	label: 'Select Difficulty:'
	// 	items: [
	// 		MenuItem{label: 'Easy', state: .disabled},
	// 		MenuItem{label: 'Medium'},
	// 		MenuItem{label: 'Hard', state: .selected}
	// 		MenuItem{label: 'Excruciating', state: .active}
	// 	]
	// }
	// m.draw_center(mut app)

	// app.tui.set_cursor_position(0, 0)
	// app.tui.reset()
	app.tui.flush()
	// app.tui.clear()
}

fn draw_text_center(mut app App, text string) {
	str_offset := text.len / 2
	app.tui.draw_text(app.width / 2 - str_offset, app.height / 2, text)
}

fn merge_strings(s1 string, s2 string, padding int, divider string) string {
	mut lines1 := s1.split_into_lines()
	mut lines2 := s2.split_into_lines()
	if lines1.len == 0 {
		lines1 = ['']
	}
	if lines2.len == 0 {
		lines2 = ['']
	}
	for i := 0; i < lines1.len && i < lines2.len; i++ {
		lines1[i] = lines1[i] + ' '.repeat(padding) + divider + ' '.repeat(padding) + lines2[i]
	}
	return lines1.join('\n')
}

[if debug]
fn debug[T](x T) {
	println(x)
}
