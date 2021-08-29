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
		hide_cursor: true
	)
	app.tui.run() or {
		panic('Failed to run app.')
	}
}

struct App {
mut:
    tui &tui.Context = 0
	width int
	height int
	colors []Color
}

fn event(e &tui.Event, x voidptr) {
    mut app := &App(x)
    println(e)
    if e.typ == .key_down && e.code == .escape {
        exit(0)
    }
}

fn frame(x voidptr) {
    mut app := &App(x)

    app.tui.clear()

	app.width, app.height = term.get_terminal_size()

	m := Menu{
		label: 'Select Difficulty:'
		items: [
			MenuItem{label: 'Easy', state: .disabled},
			MenuItem{label: 'Medium'},
			MenuItem{label: 'Hard', state: .selected}
			MenuItem{label: 'Excruciating', state: .active}
		]
	}
	m.draw_center(mut app)

    app.tui.set_cursor_position(0, 0)

    app.tui.reset()
    app.tui.flush()
}

fn draw_text_center(mut app App, text string) {
	str_offset := text.len / 2
	app.tui.draw_text(app.width/2-str_offset, app.height/2, text)
}

[if debug]
fn debug<T>(x T) {
	println(x)
}