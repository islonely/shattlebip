module core

// GameState is the state the game is currently in.
pub enum GameState {
	placing_ships
	wait_for_enemy_ship_placement
	main_menu
	my_turn
	their_turn
}
