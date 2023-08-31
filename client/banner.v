module main

struct Banner {}

fn Banner.text(str string) string {
	len := 62
	s := if str.len > len {
		str[0..47] + '...'
	} else {
		str
	}
	// vfmt off
	return ' ________________________________________________________________ \n' +
		   '|                                                                |\n' +
		   '| ${s}' + ' '.repeat(len-s.len) + ' |\n' +
		   '|________________________________________________________________|\n'
	// vfmt on
}
