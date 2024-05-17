module core

import term
import strings
import util

// cell_pictograph is the icon that represents a `CellState`.
pub const cell_pictograph = {
	'carrier':    term_pastel('₪')
	'battleship': term_pastel('₪')
	'cruiser':    term_pastel('₪')
	'submarine':  term_pastel('₪')
	'destroyer':  term_pastel('₪')
	'empty':      term.bright_blue('_')
	'hit':        term.bright_red('✛')
	'miss':       term.white('✗')
}
// ship_sizes is the length of each ship.
pub const ship_sizes = {
	CellState.carrier: 5
	.battleship:       4
	.cruiser:          3
	.submarine:        3
	.destroyer:        2
}

// Orientation is the direction a ship is facing.
pub enum Orientation {
	vertical
	horizontal
}

// Neutrality is used to color the background of a cell.
pub enum Neutrality {
	neutral
	good
	bad
}

// CellState is used to set the contents and color of contents
// of a cell.
pub enum CellState {
	empty
	carrier
	battleship
	cruiser
	submarine
	destroyer
	friendly_boat
	enemy_boat
	hit
	miss
}

// term_pastel returns a string with a randomly generated pastel color.
@[inline]
fn term_pastel(str string) string {
	p := Color.pastel()
	return term.rgb(p.r, p.g, p.g, str)
}

// good_color is the color used for cells with `Neutraility.good`.
fn good_color(str string) string {
	return term.bg_rgb(0, 100, 30, str)
}

// Cell is a Cell in the 10x10 Grid.
pub struct Cell {
mut:
	neutrality Neutrality = .neutral
	state      CellState  = .empty
	content    string
}

// Grid is the gameboard through which the players view the game world.
pub struct Grid {
pub:
	max_banner_len int = 14
	len            int = 28
	name_colorizer fn (string) string = fn (str string) string {
		return term.bright_white(str)
	}
__global:
	// name should be 17 characters or less
	name string
	grid [10][10]Cell = [10][10]Cell{init: [10]Cell{}}
}

// neutralize sets all the `Cell`s in the `Grid` to `Neutrality.neutral`.
pub fn (mut g Grid) neutralize() {
	for y in 0 .. g.grid.len {
		for x in 0 .. g.grid[y].len {
			mut new := g.grid[y][x]
			new.neutrality = .neutral
			g.grid[y][x] = new
		}
	}
}

// badify sets all the `Cell`s in the `Grid` to `Neutrality.bad`.
pub fn (mut g Grid) badify() {
	for y in 0 .. g.grid.len {
		for x in 0 .. g.grid[y].len {
			mut new := g.grid[y][x]
			new.neutrality = .bad
			g.grid[y][x] = new
		}
	}
}

// string converts the `Grid` to a string for terminal output with
// the cursor denoted by a yellow color.
pub fn (g Grid) string(cursor Cursor) string {
	mut grid_bldr := strings.new_builder(500)
	prefix := ' __'
	name := prefix + g.name_colorizer(g.name)
	name_len := g.name.len + prefix.len
	padding := if g.max_banner_len >= name_len { 0 } else { (g.max_banner_len - g.name.len) / 2 }
	// grid_bldr.write_string(merge_strings('', '', padding, name))
	grid_bldr.writeln(util.merge_strings('', '', padding, name) + '_'.repeat(g.len - name_len - 1) +
		' ')
	grid_bldr.write_string('|    ')
	for i in 0 .. 10 {
		grid_bldr.write_string(' ${i}')
	}
	grid_bldr.write_string('  |\n|    ' + term.bright_blue(' _'.repeat(10)) + '  |\n')
	for y, row in g.grid {
		grid_bldr.write_string('| ${u8(y + 65).ascii_str()}  ')
		for x, cell in row {
			last_cell := if x == 0 { cell } else { g.grid[y][x - 1] }
			// location of cursor
			if y == cursor.y && x == cursor.x && cell.state == .empty {
				grid_bldr.write_string(cursor_color('|') + cursor_color('_'))
			} else if y == cursor.y && x in [cursor.x, cursor.x + 1] {
				grid_bldr.write_string(cursor_color('|') + core.cell_pictograph[cell.state.str()])
			}
			// Cell.neutrality is .good
			else if cell.neutrality == .good {
				grid_bldr.write_string(good_color('|${core.cell_pictograph[cell.state.str()]}'))
			} else if last_cell.neutrality == .good {
				grid_bldr.write_string(good_color('|') + core.cell_pictograph[cell.state.str()])
			}
			// Cell.neutrality is .bad
			else if cell.neutrality == .bad {
				grid_bldr.write_string(good_color('|${core.cell_pictograph[cell.state.str()]}'))
			} else if last_cell.neutrality == .bad {
				grid_bldr.write_string(term.bg_red('|') + core.cell_pictograph[cell.state.str()])
			}
			// normal
			else {
				grid_bldr.write_string(term.bright_blue('|') +
					core.cell_pictograph[cell.state.str()])
			}
		}
		if y == cursor.y && cursor.x == 9 {
			grid_bldr.write_string(cursor_color('|') + ' |\n')
		} else {
			grid_bldr.write_string(term.bright_blue('|') + ' |\n')
		}
	}
	grid_bldr.write_string('|${'_'.repeat(g.len - 2)}|')
	return grid_bldr.str()
}

// place_ship puts a ship onto the grid in the specified location.
pub fn (mut g Grid) place_ship(typ CellState, size int, pos Pos, o Orientation) ! {
	ships := [CellState.carrier, .battleship, .cruiser, .submarine, .destroyer]
	if typ !in ships {
		return error('Invalid cell state for ship placement: ${typ}')
	}
	match o {
		.vertical {
			if pos.y <= size {
				for y in pos.y .. (pos.y + size) {
					if g.grid[y][pos.x].state in ships {
						return error('Grid space occupied.')
					}
				}
				for y in pos.y .. (pos.y + size) {
					g.grid[y][pos.x] = Cell{
						state: typ
					}
				}
			} else {
				for y in (pos.y - size) .. pos.y {
					if g.grid[y][pos.x].state in ships {
						return error('Grid space occupied.')
					}
				}
				for y in (pos.y - size) .. pos.y {
					g.grid[y][pos.x] = Cell{
						state: typ
					}
				}
			}
		}
		.horizontal {
			if pos.x <= size {
				for x in pos.x .. (pos.x + size) {
					if g.grid[pos.y][x].state in ships {
						return error('Grid space occupied.')
					}
				}
				for x in pos.x .. (pos.x + size) {
					g.grid[pos.y][x] = Cell{
						state: typ
					}
				}
			} else {
				for x in (pos.x - size) .. pos.x {
					if g.grid[pos.y][x].state in ships {
						return error('Grid space occupied.')
					}
				}
				for x in (pos.x - size) .. pos.x {
					g.grid[pos.y][x] = Cell{
						state: typ
					}
				}
			}
		}
	}
}
