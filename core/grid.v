module core

import strings
import util

// cell_pictograph is the icon that represents a `CellState`.
pub const cell_pictograph = {
	'carrier':    term_pastel('Ħ')
	'battleship': term_pastel('Җ')
	'cruiser':    term_pastel('₪')
	'submarine':  term_pastel('§')
	'destroyer':  term_pastel('₪')
	'empty':      bright_blue('_')
	'hit':        bright_red('✗')
	'miss':       white('◯')
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
	return rgb(p.r, p.g, p.b, str)
}

// good_color is the color used for cells with `Neutraility.good`.
fn good_color(str string) string {
	return bg_rgb(0, 100, 30, str)
}

// Cell is a Cell in the 10x10 Grid.
pub struct Cell {
pub mut:
	neutrality Neutrality = .neutral
	state      CellState  = .empty
	content    string
	// flash highlights the cell for one frame; used for attack feedback
	flash bool
}

// Grid is the gameboard through which the players view the game world.
pub struct Grid {
pub:
	max_banner_len int                = 14
	len            int                = 28
	name_colorizer fn (string) string = fn (str string) string {
		return bright_white(str)
	}
__global:
	// name should be 17 characters or less
	name   string
	grid   [10][10]Cell = [10][10]Cell{init: [10]Cell{}}
	cursor Cursor
}

// set_at_cursor changes the state of the cell at the cursor position.
@[inline]
pub fn (mut g Grid) set_at_cursor(state CellState) {
	g.grid[g.cursor.y][g.cursor.x].state = state
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

// all_ships_sunk returns true when no ship cell is left standing, which
// means the fleet on this grid has been destroyed.
pub fn (g Grid) all_ships_sunk() bool {
	ships := [CellState.carrier, .battleship, .cruiser, .submarine, .destroyer]
	for row in g.grid {
		for cell in row {
			if cell.state in ships {
				return false
			}
		}
	}
	return true
}

// ship_fully_hit returns true when no cell of the given ship type is left
// un-hit, meaning that ship has been sunk.
pub fn (g Grid) ship_fully_hit(typ CellState) bool {
	for row in g.grid {
		for cell in row {
			if cell.state == typ {
				return false
			}
		}
	}
	return true
}

// string converts the `Grid` to a string for terminal output with
// the cursor denoted by a yellow color.
pub fn (g Grid) str() string {
	mut grid_bldr := strings.new_builder(500)
	prefix := ' __'
	name := prefix + g.name_colorizer(g.name)
	name_len := g.name.len + prefix.len
	padding := if g.max_banner_len >= name_len { 0 } else { (g.max_banner_len - g.name.len) / 2 }
	safe_padding := if padding > 0 { padding } else { 0 }
	under_len := g.len - name_len - 1
	under := if under_len > 0 { '_'.repeat(under_len) } else { '' }
	// grid_bldr.write_string(merge_strings('', '', padding, name))
	grid_bldr.writeln(util.merge_strings('', '', safe_padding, name) + under + ' ')
	grid_bldr.write_string('|    ')
	for i in 0 .. 10 {
		grid_bldr.write_string(' ${i}')
	}
	grid_bldr.write_string('  |\n|    ')
	for x in 0 .. 10 {
		if x == g.cursor.x {
			grid_bldr.write_string(g.cursor.color(' _'))
			continue
		}
		grid_bldr.write_string(bright_blue(' _'))
	}
	grid_bldr.write_string('  |\n')
	for y, row in g.grid {
		// draws the grid container and letter: "| A "
		grid_bldr.write_string('| ${u8(y + 65).ascii_str()} ' + if y == g.cursor.y {
			g.cursor.color('>')
		} else {
			' '
		})

		// draws "|_" back to back to form row in grid
		for x, cell in row {
			last_cell := if x == 0 { cell } else { g.grid[y][x - 1] }
			// a flashing cell is always drawn highlighted, even under the cursor
			if cell.flash {
				grid_bldr.write_string(bg_red('|${cell_pictograph[cell.state.str()]}'))
				continue
			}
			// line before cursor
			if y == g.cursor.y - 1 && x == g.cursor.x {
				grid_bldr.write_string(bright_blue('|') + if cell.state == .empty {
					g.cursor.color('_')
				} else {
					cell_pictograph[cell.state.str()]
				})
			}
			// location of cursor
			else if y == g.cursor.y && x == g.cursor.x && cell.state == .empty {
				grid_bldr.write_string(g.cursor.color('|') + g.cursor.color('_'))
			} else if y == g.cursor.y && x in [g.cursor.x, g.cursor.x + 1] {
				grid_bldr.write_string(g.cursor.color('|') + cell_pictograph[cell.state.str()])
			}
			// last line and cursor column
			else if x == g.cursor.x && y == 9 {
				grid_bldr.write_string(bright_blue('|') + if cell.state == .empty {
					g.cursor.color('_')
				} else {
					cell_pictograph[cell.state.str()]
				})
			}
			// Cell.neutrality is .good
			else if cell.neutrality == .good {
				grid_bldr.write_string(good_color('|${cell_pictograph[cell.state.str()]}'))
			} else if last_cell.neutrality == .good {
				grid_bldr.write_string(good_color('|') + cell_pictograph[cell.state.str()])
			}
			// Cell.neutrality is .bad
			else if cell.neutrality == .bad {
				grid_bldr.write_string(bg_red('|${cell_pictograph[cell.state.str()]}'))
			} else if last_cell.neutrality == .bad {
				grid_bldr.write_string(bg_red('|') + cell_pictograph[cell.state.str()])
			}
			// normal
			else {
				grid_bldr.write_string(bright_blue('|') + cell_pictograph[cell.state.str()])
			}
		}

		// draws the last cell bar and grid container: "| |\n"
		if y == g.cursor.y {
			if g.cursor.x == 9 {
				grid_bldr.write_string(g.cursor.color('|<') + '|\n')
			} else {
				grid_bldr.write_string(bright_blue('|') + g.cursor.color('<') + '|\n')
			}
		} else {
			grid_bldr.write_string(bright_blue('|') + ' |\n')
		}
	}
	// draws the grid container bottom minus 2 for the pipes "|" on each side.
	grid_bldr.write_string('|${'_'.repeat(g.len - 2)}|')
	return grid_bldr.str()
}

// can_place_ship reports whether a ship of `size` fits with its bow at
// `pos` and extends right (horizontal) or down (vertical).
pub fn (g Grid) can_place_ship(size int, pos Pos, o Orientation) bool {
	if pos.x < 0 || pos.y < 0 || pos.x > 9 || pos.y > 9 {
		return false
	}
	match o {
		.horizontal {
			if pos.x + size > 10 {
				return false
			}
			for x in pos.x .. pos.x + size {
				if g.grid[pos.y][x].state != .empty {
					return false
				}
			}
		}
		.vertical {
			if pos.y + size > 10 {
				return false
			}
			for y in pos.y .. pos.y + size {
				if g.grid[y][pos.x].state != .empty {
					return false
				}
			}
		}
	}
	return true
}

// place_ship puts a ship onto the grid with its bow at `pos`. Error is
// returned when the placement is out of bounds or overlaps another ship.
pub fn (mut g Grid) place_ship(typ CellState, size int, pos Pos, o Orientation) ! {
	ships := [CellState.carrier, .battleship, .cruiser, .submarine, .destroyer]
	if typ !in ships {
		return error('Invalid cell state for ship placement: ${typ}')
	}
	if !g.can_place_ship(size, pos, o) {
		return error('Grid space occupied or out of bounds.')
	}
	match o {
		.horizontal {
			for x in pos.x .. pos.x + size {
				g.grid[pos.y][x] = Cell{
					state: typ
				}
			}
		}
		.vertical {
			for y in pos.y .. pos.y + size {
				g.grid[y][pos.x] = Cell{
					state: typ
				}
			}
		}
	}
}

// remove_ship clears every cell occupied by the given ship type.
pub fn (mut g Grid) remove_ship(typ CellState) {
	for y in 0 .. g.grid.len {
		for x in 0 .. g.grid[y].len {
			if g.grid[y][x].state == typ {
				g.grid[y][x].state = .empty
			}
		}
	}
}

// set_neutrality sets the neutrality of the cell at `pos`, ignoring
// out-of-bounds positions.
pub fn (mut g Grid) set_neutrality(pos Pos, n Neutrality) {
	if pos.x < 0 || pos.x > 9 || pos.y < 0 || pos.y > 9 {
		return
	}
	mut cell := g.grid[pos.y][pos.x]
	cell.neutrality = n
	g.grid[pos.y][pos.x] = cell
}

// set_flash toggles the flash highlight on the cell at `pos`, ignoring
// out-of-bounds positions.
pub fn (mut g Grid) set_flash(pos Pos, on bool) {
	if pos.x < 0 || pos.x > 9 || pos.y < 0 || pos.y > 9 {
		return
	}
	mut cell := g.grid[pos.y][pos.x]
	cell.flash = on
	g.grid[pos.y][pos.x] = cell
}
