module main

// Banner is used to like a namespace.
@[noinit]
struct Banner {}

// Banner.text returns a string inside of a banner for output
// onto a terminal UI.
fn Banner.text(str string) string {
	width := 62
	max_text := 50
	s := if str.len > max_text { str[..max_text - 3] + '...' } else { str }
	pad := if width - s.len > 0 { ' '.repeat(width - s.len) } else { '' }
	// vfmt off
	return ' ________________________________________________________________ \n' +
		   '|                                                                |\n' +
		   '| ${s}' + pad + ' |\n' +
		   '|________________________________________________________________|\n'
	// vfmt on
}
