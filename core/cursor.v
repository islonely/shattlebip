module core

pub struct Cursor {
	Pos
__global:
	selected Pos   = Pos.null()
	history  []Pos = []Pos{cap: 200}
}

pub fn (c Cursor) val() string {
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

[inline]
pub fn (mut c Cursor) nullify() {
	c.history << c.selected
	c.selected = Pos.null()
}

[inline]
pub fn (c Cursor) has_selected() bool {
	return !c.selected.is_null()
}

[inline]
pub fn (c Cursor) last() Pos {
	return c.history.last()
}

pub fn (mut c Cursor) select_pos() {
	c.history << c.selected
	c.selected = c.Pos
}
