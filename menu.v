import strings
import term

const(
	clr_default = Color{r: 255, g: 255, b: 255}
)

enum CheckboxState {
	disabled
	unselected
	selected
	active
}

struct MenuItem {
	label string
	state CheckboxState = .unselected
}

fn (mi MenuItem) str() string {
	str := match mi.state {
		.disabled {
			term.dim('[ ] $mi.label')
		}
		.unselected {
			d('[ ] $mi.label')
		}
		.selected {
			d('[x] $mi.label')
		}
		.active {
			d('[+] $mi.label')
		}
	}
	return str
}

struct Menu {
	label string
	items []MenuItem
}

fn (m Menu) draw_center(mut app App) {
	mut sb := strings.new_builder(0)
	mut longest := m.label.len
	sb.writeln(d(m.label))
	for item in m.items {
		if item.str().len > longest {
			longest = item.str().len
		}
		sb.writeln(item.str())
	}
	str := sb.str().split_into_lines()
	x := (app.width/2) - (longest/4)
	y := (app.height/2) - (str.len/2)
	
	for i, line in str {
		app.tui.draw_text(x, y+i, line)
	}
}

fn (m Menu) draw(mut app App, x int, y int) {
	app.tui.draw_text(x, y, m.label)
	for i, item in m.items {
		app.tui.draw_text(x, y+i+1, item.str())
	}
}

[inline]
fn d(str string) string {
	return term.rgb(clr_default.r, clr_default.g, clr_default.b, str)
}