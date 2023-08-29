struct Cursor {
mut:
	x int
	y int
}

fn (c Cursor) val() string {
	col := c.x.str()
	row := match c.y {
		0 { 'A' }
		1 { 'B' }
		2 { 'C' }
		3 { 'D' }
		4 { 'E' }
		5 { 'F' }
		6 { 'G' }
		7 { 'H' }
		8 { 'I' }
		9 { 'J' }
		else { 'err' }
	}
	return row + col
}
