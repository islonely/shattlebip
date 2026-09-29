module core

fn test_place_and_bounds() {
	mut g := Grid{}
	assert g.can_place_ship(5, Pos{0, 0}, .horizontal) == true
	assert g.can_place_ship(5, Pos{6, 0}, .horizontal) == false
	assert g.can_place_ship(5, Pos{0, 6}, .vertical) == false
	assert g.can_place_ship(3, Pos{-1, 0}, .horizontal) == false

	g.place_ship(.carrier, 5, Pos{0, 0}, .horizontal)!
	assert g.grid[0][0].state == .carrier
	assert g.grid[0][4].state == .carrier
	// overlapping placement is rejected
	assert g.can_place_ship(2, Pos{0, 0}, .vertical) == false
	assert g.can_place_ship(2, Pos{0, 1}, .vertical) == true
}

fn test_all_ships_sunk() {
	mut g := Grid{}
	g.place_ship(.destroyer, 2, Pos{0, 0}, .horizontal)!
	assert g.all_ships_sunk() == false
	g.grid[0][0].state = .hit
	assert g.all_ships_sunk() == false
	g.grid[0][1].state = .hit
	assert g.all_ships_sunk() == true
}

fn test_ship_fully_hit_and_remove() {
	mut g := Grid{}
	g.place_ship(.cruiser, 3, Pos{2, 2}, .vertical)!
	assert g.ship_fully_hit(.cruiser) == false
	g.remove_ship(.cruiser)
	assert g.ship_fully_hit(.cruiser) == true
	assert g.grid[2][2].state == .empty
}

fn test_set_neutrality_and_flash_bounds() {
	mut g := Grid{}
	g.set_neutrality(Pos{1, 1}, .good)
	assert g.grid[1][1].neutrality == .good
	g.set_flash(Pos{1, 1}, true)
	assert g.grid[1][1].flash == true
	// out-of-bounds positions are ignored, not a crash
	g.set_neutrality(Pos{-1, 20}, .bad)
	g.set_flash(Pos{20, -1}, true)
}
