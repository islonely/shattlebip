import term.ui as tui

const (
	cell_size = 25
	grid_padding = 30
)

enum CellState {
	@none
	occupied
	enemy_hit
	player_hit
	shot_missed
}

enum GridType {
	player
	enemy
}

struct Grid {
mut:
	@type GridType = .player
	grid [10][10]CellState
}

[inline]

fn (g Grid) size() int {
	return cell_size * 10
}

fn (g Grid) draw(mut app App) {
	app.tui.set_color(r: 0xff, g: 0xff, b: 0xff)
	if g.@type == .player {
		for i in 0..10 {
			{ // horizontal lines
				x1, y1 := app.width/2 - g.size() - grid_padding, grid_padding + (cell_size * i)
				x2, y2 := app.width/2 - grid_padding, grid_padding + (cell_size * i)
				app.tui.draw_line(x1, y1, x2, y2)
			}
			{ // vertical lines
				
			}
		}
	} else {
		x1, y1 := app.width/2 + grid_padding, grid_padding
		x2, y2 := app.width/2 + g.size() + grid_padding, grid_padding
		app.tui.draw_rect(x1, y1, x2, y2)
	}
}