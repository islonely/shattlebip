import term.ui as tui
import term
import strings

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
		init_fn: init
		hide_cursor: true
	)
	app.tui.run() or {
		panic('Failed to run app.')
	}
}

struct App {
mut:
    tui &tui.Context = unsafe { nil }
	width int
	height int
	colors []Color
	grid struct {
	mut:
		player Grid
		enemy Grid
	}
}

fn init(mut app App) {
	app.tui.set_bg_color(r: 0x0f, g: 0x80, b: 0xef)
}

fn event(e &tui.Event, mut app App) {
    println(e)
    if e.typ == .key_down && e.code == .escape {
        exit(0)
    }
}

fn frame(mut app App) {
    app.tui.clear()

	app.width, app.height = term.get_terminal_size()
	app.grid.player.draw(mut app)
	app.grid.enemy.draw(mut app)
	
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

    app.tui.reset()
    app.tui.flush()
}

fn draw_text_center(mut app App, text string) {
	str_offset := text.len / 2
	app.tui.draw_text(app.width/2-str_offset, app.height/2, text)
}

[if debug]
fn debug[T](x T) {
	println(x)
}