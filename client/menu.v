module main

import strings
import term

enum CheckboxState {
	disabled
	unselected
	selected
	active
}

struct MenuItem {
mut:
	label string
	state CheckboxState = .unselected
	do    fn () = fn () {}
}

fn (mi MenuItem) str() string {
	str := match mi.state {
		.disabled {
			term.dim('[ ] ${mi.label}')
		}
		.unselected {
			d('[ ] ${mi.label}')
		}
		.selected {
			d('[✓] ${mi.label}')
		}
		.active {
			d('[*] ${mi.label}')
		}
	}
	return str
}

struct Menu {
mut:
	label    string
	items    []MenuItem
	selected int
}

fn (m Menu) draw_center(mut app App) {
	mut sb := strings.new_builder(0)
	mut longest := m.label.len
	sb.writeln(d(m.label))
	for i, item in m.items {
		if item.str().len > longest {
			longest = item.str().len
		}
		if i == m.selected {
			sb.writeln(d('[*] ${item.label}'))
			continue
		}
		sb.writeln(item.str())
	}
	str := sb.str().split_into_lines()
	x := (app.width / 2) - (longest / 4)
	y := (app.height / 2) - (str.len / 2)

	for i, line in str {
		app.tui.draw_text(x, y + i, line)
	}
}

fn (m Menu) draw(mut app App, x int, y int) {
	app.tui.draw_text(x, y, m.label)
	for i, item in m.items {
		app.tui.draw_text(x, y + i + 1, item.str())
	}
}

[inline]
fn d(str string) string {
	return term.bright_white(str)
}

[inline]
fn (m Menu) selected() MenuItem {
	return m.items[m.selected]
}

fn (mut m Menu) move_down() {
	m.selected++
	if m.selected >= m.items.len {
		m.selected = 0
	}
	for m.items[m.selected].state == .disabled {
		m.move_down()
	}
}

fn (mut m Menu) move_up() {
	m.selected--
	if m.selected < 0 {
		m.selected += m.items.len
	}
	for m.items[m.selected].state == .disabled {
		m.move_up()
	}
}
