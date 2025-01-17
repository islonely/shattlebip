module main

import strings
import term

// CheckboxState is the state of the `MenuItem`.
enum CheckboxState {
	disabled
	unselected
	selected
	active
}

// MenuItem is an item in the `Menu`.
struct MenuItem {
mut:
	label string
	state CheckboxState = .unselected
	do    fn ()         = fn () {}
}

// str converts a `MenuItem` into a string.
fn (mi MenuItem) str() string {
	str := match mi.state {
		.disabled {
			term.dim('[ ] ${mi.label}')
		}
		.unselected {
			term.bright_white('[ ] ${mi.label}')
		}
		.selected {
			term.bright_white('[✓] ${mi.label}')
		}
		.active {
			term.bright_white('[*] ${mi.label}')
		}
	}
	return str
}

// Menu is a list of items that the user can select.
struct Menu {
mut:
	label    string
	items    []MenuItem
	selected int
}

// draw_center horizontally and vertically draws the `Menu` onto the terminal UI.
fn (m Menu) draw_center(mut game Game) {
	mut sb := strings.new_builder(0)
	mut longest := m.label.len
	sb.writeln(term.bright_white(m.label))
	for i, item in m.items {
		if item.str().len > longest {
			longest = item.str().len
		}
		if i == m.selected {
			sb.writeln(term.bright_white('[*] ${item.label}'))
			continue
		}
		sb.writeln(item.str())
	}
	str := sb.str().split_into_lines()
	x := (game.width / 2) - (longest / 4)
	y := (game.height / 2) - (str.len / 2)

	for i, line in str {
		game.tui.draw_text(x, y + i, line)
	}
}

// draw draws the `Menu` at the specified location onto the terminal UI.
fn (m Menu) draw(mut game Game, x int, y int) {
	game.tui.draw_text(x, y, m.label)
	for i, item in m.items {
		game.tui.draw_text(x, y + i + 1, item.str())
	}
}

// find searches for a `MenuItem` with the same label as the one provided.
pub fn (menu Menu) find(label string) ?int {
	for i, item in menu.items {
		if item.label == label {
			return i
		}
	}
	return none
}

// selected gets the currently selected `MenuItem`.
@[inline]
fn (m Menu) selected() MenuItem {
	return m.items[m.selected]
}

// move_down cycles down the `Menu`. It jumps to the top item if cycled
// down on the last item.
fn (mut m Menu) move_down() {
	m.selected++
	if m.selected >= m.items.len {
		m.selected = 0
	}
	for m.items[m.selected].state == .disabled {
		m.move_down()
	}
}

// move_up cycles up the `Menu`. It jumps to the bottom item if cycled
// up on the last item.
fn (mut m Menu) move_up() {
	m.selected--
	if m.selected < 0 {
		m.selected += m.items.len
	}
	for m.items[m.selected].state == .disabled {
		m.move_up()
	}
}
