module core

import term

// colorizer function i.e., `fn cursor_color(string) string`
pub const cursor_color = term.bright_yellow

// Cursor is a position on the `Grid` which the user has
// currently selected.
pub struct Cursor {
	Pos
__global:
	selected Pos   = Pos.null()
	history  []Pos = []Pos{cap: 200}
}

// val converts the X value to a letter concatenated with the Y value.
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

// nullify sets the `Cursor.selected` field to `fn Pos.null`.
@[inline]
pub fn (mut c Cursor) nullify() {
	c.history << c.selected
	c.selected = Pos.null()
}

// has_selected returns whether or not a position on the `Grid` has
// been selected.
@[inline]
pub fn (c Cursor) has_selected() bool {
	return !c.selected.is_null()
}

// last returns the previous value selected.
@[inline]
pub fn (c Cursor) last() Pos {
	return c.history.last()
}

// select_pos sets the current position on the `Grid` as the selected
// position.
pub fn (mut c Cursor) select_pos() {
	c.history << c.selected
	c.selected = c.Pos
}
