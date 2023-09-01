module main

// Banner is used to like a namespace.
[noinit]
struct Banner {}

// Banner.text returns a string inside of a banner for output
// onto a terminal UI.
fn Banner.text(str string) string {
	len := 62
	// s := if str.len > len {
	// 	str[0..47] + '...'
	// } else {
	// 	str
	// }
	s := str
	// vfmt off
	return ' ________________________________________________________________ \n' +
		   '|                                                                |\n' +
		   '| ${s}' + ' '.repeat(len-s.len) + ' |\n' +
		   '|________________________________________________________________|\n'
	// vfmt on
}
