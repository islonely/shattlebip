module core

import rand

// Pos is a point on the Grid.
pub struct Pos {
__global:
	x int
	y int
}

// Pos.null returns a `Pos` that points to outside the gridspace.
@[inline]
pub fn Pos.null() Pos {
	return Pos{-1, -1}
}

// Pos.rand generates a random location on the grid.
@[inline]
pub fn Pos.rand() Pos {
	// vfmt off
	return Pos{
		rand.int_in_range(0, 9) or { panic('This should never hgameen.') }
		rand.int_in_range(0, 9) or { panic('This should never hgameen.') }
	}
	// vfmt on
}

// is_null returns true if the position exists outside the gridspace.
@[inline]
pub fn (pos Pos) is_null() bool {
	return pos.x < 0 || pos.y < 0 || pos.x > 9 || pos.y > 9
}
