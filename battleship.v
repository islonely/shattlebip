import term.ui as tui
import term
import strings
import math

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
	app.tui.run() or { panic('Failed to run app.') }
}

enum GameState {
	placing_ships
}

struct Pos {
mut:
	x int
	y int
}

// null returns a `Pos` that points to outside the gridspace.
[inline]
fn Pos.null() Pos {
	return Pos{-1, -1}
}

// is_null returns true if the position exists outside the gridspace.
[inline]
fn (pos Pos) is_null() bool {
	return pos.x < 0 || pos.y < 0 || pos.x > 9 || pos.y > 9
}

struct App {
mut:
	tui               &tui.Context = unsafe { nil }
	width             int
	height            int
	colors            []Color
	cursor            Cursor
	state             GameState = .placing_ships
	ship_needs_placed []Ship    = [.carrier, .battleship, .cruiser, .submarine, .destroyer]
	ship_rotated      bool

	player Grid = Grid{
		name: 'Player'
		name_colorizer: fn (str string) string {
			return term.bright_blue(str)
		}
	}
	enemy Grid = Grid{
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
				if _likely_(app.cursor.y < 9) {
					app.cursor.y++
				}
			}
			.up {
				if _likely_(app.cursor.y > 0) {
					app.cursor.y--
				}
			}
			.left {
				if _likely_(app.cursor.x > 0) {
					app.cursor.x--
				}
			}
			.right {
				if _likely_(app.cursor.x < 9) {
					app.cursor.x++
				}
			}
			.space {
				app.handle_space_press()
			}
			else {}
		}
	}
}

fn (mut app App) handle_space_press() {
	app.cursor.select_pos()
	match app.state {
		.placing_ships {}
	}
}

fn frame(mut app App) {
	app.width, app.height = term.get_terminal_size()
	app.tui.set_cursor_position(0, 0)

	// app.grid.enemy.draw(mut app)
	player := app.player.string(app.cursor)
	enemy := app.enemy.string(app.cursor)
	app.tui.draw_text(0, 0, merge_strings(player, enemy, 4, '::'))
	app.tui.draw_text(0, 15, Banner.text('Select locations for your ships.'))
	app.tui.draw_text(0, 19, 'POS: ${app.cursor.val()}')

	match app.state {
		.placing_ships {
			size := ship_sizes[app.ship_needs_placed.last()]
			ysize := if app.ship_rotated { app.cursor.y + size } else { app.cursor.y + 1 }
			xsize := if !app.ship_rotated { app.cursor.x + size } else { app.cursor.x + 1 }
			for y, row in app.player.grid {
				for x, cell in row {
					if x >= app.cursor.x && x < xsize && y >= app.cursor.y && y < ysize {
						app.player.grid[y][x] = Cell{.good, .friendly_boat}
					} else {
						app.player.grid[y][x] = grid_copy[y][x]
					}
				}
			}
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
