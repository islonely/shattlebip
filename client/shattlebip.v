module main

import term.ui as tui
import term
import rand
import log
import net
import core
import config
import util
import time

// 1902 = letters 19 and 02
//		= SB
// 		= ShattleBip
const log_file_path = './shattlebip.log'
const default_read_timeout = time.minute * 5
const default_write_timeout = time.minute * 5

fn main() {
	w, h := term.get_terminal_size()
	mut game := &Game{
		width:  w
		height: h
	}
	game.cfg = config.load()
	game.server_addr = game.cfg.addr()
	game.tui = tui.init(
		user_data:   game
		event_fn:    event
		frame_fn:    frame
		hide_cursor: true
	)
	game.menu = Menu{
		label: ''
		items: [
			MenuItem{
				label: 'Online Play'
				state: .unselected
				do:    fn [mut game] () {
					game.network_thread = spawn game.initiate_server_connection()
				}
			},
			MenuItem{
				label: 'Offline Play'
				state: .disabled
			},
			MenuItem{
				label: 'Settings'
				state: .unselected
				do:    fn [mut game] () {
					game.show_settings = true
				}
			},
			MenuItem{
				label: 'Disconnect'
				state: .disabled
				do:    fn [mut game] () {
					game.end('Connection terminated.')
				}
			},
			MenuItem{
				label: 'Quit'
				state: .unselected
				do:    fn () {
					exit(1)
				}
			},
		]
	}
	game.game_over_menu = Menu{
		label: 'Game Over'
		items: [
			MenuItem{
				label: 'Rematch'
				state: .unselected
				do:    fn [mut game] () {
					game.request_rematch()
				}
			},
			MenuItem{
				label: 'Find New Opponent'
				state: .unselected
				do:    fn [mut game] () {
					game.find_new_opponent()
				}
			},
			MenuItem{
				label: 'Quit'
				state: .unselected
				do:    fn () {
					exit(0)
				}
			},
		]
	}
	game.tui.run() or { panic('Failed to run game.') }
}

// Game is the primary game object.
struct Game {
mut:
	tui                        &tui.Context = unsafe { nil }
	width                      int
	height                     int
	colors                     []core.Color
	state                      core.GameState = .main_menu
	has_enemy_placed_ships     bool
	us_starts_game             bool
	ship_needs_placed          []core.CellState = [.carrier, .battleship, .cruiser, .submarine,
		.destroyer]
	placed_ships               []core.CellState
	ship_orientation           core.Orientation = .horizontal
	menu                       Menu
	game_over_menu             Menu
	won                        bool
	want_requeue               bool
	opponent_requested_rematch bool
	banner_text                string      = '                          SHATTLEBIP                          '
	banner_text_channel        chan string = chan string{ cap: 100 }
	server                     core.BufferedTcpConn
	server_addr                string = '127.0.0.1:1902'
	cfg                        config.Config
	show_settings              bool
	network_thread             thread
	logger                     shared log.ThreadSafeLog
	// cell the player most recently fired at; used to place the reply
	// because the cursor may move while waiting for it.
	last_attack_pos core.Pos
	// attack feedback flash
	flash_pos      core.Pos = core.Pos{-1, -1}
	flash_on_enemy bool
	flash_start    u64
	flash_until    u64

	player_grid core.Grid = core.Grid{
		name:           'Player'
		name_colorizer: fn (str string) string {
			return term.bright_blue(str)
		}
	}
	enemy_grid  core.Grid = core.Grid{
		name:           'Enemy'
		name_colorizer: fn (str string) string {
			return term.bright_red(str)
		}
	}
}

// draw_banner converts the Game.banner_text variable to the correct text
// and draws it to the screen.
fn (mut game Game) draw_banner() {
	banner := Banner.text(game.banner_text)
	for i, line in banner.split_into_lines() {
		x := (game.width / 2) - (line.len / 2)
		game.tui.draw_text(x, i + 2, line)
	}
}

// switch_state sets the game to the specified state. And sets the banner text
// to the specified text. As well as flushed and clears the terminal UI.
fn (mut game Game) switch_state(state core.GameState, banner_text ?string) {
	game.tui.clear()
	game.state = state
	if text := banner_text {
		game.banner_text_channel <- text
	}
}

// event passes an event to the respective function to be handled
// based on the current game state.
fn event(event &tui.Event, mut game Game) {
	if event.typ == .key_down && event.code == .escape {
		exit(0)
	}
	game.tui.clear()

	match game.state {
		.main_menu {
			game.main_menu_event(event)
		}
		.my_turn {
			game.my_turn_event(event) or {
				if !(err.code() == net.error_ewouldblock) {
					game.end(err.msg())
				}
			}
		}
		.placing_ships {
			game.placing_ships_event(event) or {
				if !(err.code() == net.error_ewouldblock) {
					game.end(err.msg())
				}
			}
		}
		.their_turn {
			game.their_turn_event(event)
		}
		.wait_for_enemy_ship_placement {
			game.wait_for_enemy_ship_placement_event(event)
		}
		.game_over {
			game.game_over_event(event)
		}
	}
}

// main_menu_event handles mouse, keyboard, and window events that
// hgameen during the .main_menu state.
fn (mut game Game) main_menu_event(event &tui.Event) {
	if game.show_settings {
		if event.typ == .key_down {
			game.show_settings = false
		}
		return
	}
	match event.typ {
		.key_down {
			match event.code {
				.up { game.menu.move_up() }
				.down { game.menu.move_down() }
				.space, .enter { game.menu.selected().do() }
				else {}
			}
		}
		else {}
	}
}

// my_turn_event handles mouse, keyboard, and window events that
// happen during the .my_turn state.
fn (mut game Game) my_turn_event(event &tui.Event) ! {
	match event.typ {
		.key_down {
			match event.code {
				.left, .right, .up, .down {
					game.move_cursor(event.code, mut game.enemy_grid, true)
				}
				.space {
					pos := game.enemy_grid.cursor.Pos
					already_tried := game.enemy_grid.grid[pos.y][pos.x].state in [
						core.CellState.hit,
						core.CellState.miss,
					]
					if already_tried {
						game.banner_text_channel <- 'You already attacked ${game.enemy_grid.cursor.val()}.'
						return
					}
					// Only send here. The server reply (hit/miss) is read by
					// the single network thread to avoid two threads reading
					// the same socket.
					game.last_attack_pos = pos
					game.start_flash(pos, true)
					msg := core.Message.attack_cell
					game.write_message(msg)!
					game.write_cursor()
					game.server.flush()!
					game.switch_state(.their_turn, none)
				}
				else {}
			}
		}
		else {}
	}
}

// their_turn_event handles mouse, keyboard, and window events that
// happen during the .their turn state.
fn (mut game Game) their_turn_event(event &tui.Event) {
	match event.typ {
		.key_down {
			match event.code {
				.left, .right, .up, .down {
					game.move_cursor(event.code, mut game.enemy_grid, true)
				}
				else {}
			}
		}
		else {}
	}
}

// placing_ships_event handles mouse, keyboard, and window events
// that happen during the .placing_ships state.
fn (mut game Game) placing_ships_event(event &tui.Event) ! {
	match event.typ {
		.key_down {
			match event.code {
				.left, .right, .up, .down {
					game.move_cursor(event.code, mut game.player_grid, false)
					game.update_ship_preview()
				}
				.r {
					game.ship_orientation = if game.ship_orientation == .horizontal {
						.vertical
					} else {
						.horizontal
					}
					game.update_ship_preview()
				}
				.space {
					game.place_current_ship()
				}
				.u, .backspace {
					game.undo_ship()
				}
				.a {
					game.randomly_place_ships()!
				}
				.enter {
					if game.ship_needs_placed.len == 0 {
						game.confirm_placement()!
					} else {
						game.banner_text_channel <- 'Place all your ships before starting.'
					}
				}
				else {}
			}
		}
		else {}
	}
}

// place_current_ship drops the next ship at the cursor if it fits.
fn (mut game Game) place_current_ship() {
	if game.ship_needs_placed.len == 0 {
		return
	}
	ship := game.ship_needs_placed.last()
	size := core.ship_sizes[ship]
	pos := game.player_grid.cursor.Pos
	if !game.player_grid.can_place_ship(size, pos, game.ship_orientation) {
		game.banner_text_channel <- 'Cannot place the ship there.'
		return
	}
	game.player_grid.place_ship(ship, size, pos, game.ship_orientation) or { return }
	game.placed_ships << ship
	game.ship_needs_placed.pop()
	game.update_ship_preview()
	if game.ship_needs_placed.len == 0 {
		game.banner_text_channel <- 'All ships placed. Press Enter to start.'
	} else {
		next := game.ship_needs_placed.last()
		game.banner_text_channel <- 'Place your ${next} (${core.ship_sizes[next]}).'
	}
}

// undo_ship lifts the most recently placed ship off the board.
fn (mut game Game) undo_ship() {
	if game.placed_ships.len == 0 {
		return
	}
	ship := game.placed_ships.pop()
	game.player_grid.remove_ship(ship)
	game.ship_needs_placed << ship
	game.update_ship_preview()
	game.banner_text_channel <- 'Place your ${ship} (${core.ship_sizes[ship]}).'
}

// randomly_place_ships fills the board with valid random placements.
fn (mut game Game) randomly_place_ships() ! {
	for game.ship_needs_placed.len > 0 {
		ship := game.ship_needs_placed.last()
		size := core.ship_sizes[ship]
		mut placed := false
		for _ in 0 .. 500 {
			o := unsafe { core.Orientation(rand.int_in_range(0, 2) or { 0 }) }
			pos := random_anchor(size, o)
			if !game.player_grid.can_place_ship(size, pos, o) {
				continue
			}
			game.player_grid.place_ship(ship, size, pos, o) or { continue }
			game.placed_ships << ship
			game.ship_needs_placed.pop()
			placed = true
			break
		}
		if !placed {
			game.banner_text_channel <- 'Could not place every ship randomly. Try again.'
			return
		}
	}
	game.confirm_placement()!
}

// random_anchor returns a random bow position where a ship of `size` fits.
fn random_anchor(size int, o core.Orientation) core.Pos {
	// vfmt off
	return match o {
		.horizontal {
			core.Pos{ rand.int_in_range(0, 11 - size) or { 0 }, rand.int_in_range(0, 10) or { 0 } }
		}
		.vertical {
			core.Pos{ rand.int_in_range(0, 10) or { 0 }, rand.int_in_range(0, 11 - size) or { 0 } }
		}
	}
	// vfmt on
}

// confirm_placement tells the server the fleet is ready and moves on.
fn (mut game Game) confirm_placement() ! {
	game.write_message(.placed_ships)!
	game.server.flush()!
	if game.has_enemy_placed_ships {
		if game.us_starts_game {
			game.switch_state(.my_turn, 'Game Start! Your turn first.')
		} else {
			game.switch_state(.their_turn, 'Game Start! Their turn first.')
		}
		return
	}
	game.switch_state(.wait_for_enemy_ship_placement, 'Waiting for opponent to place their ships.')
}

// update_ship_preview tints the cells the next ship would occupy, green
// when the placement is legal and red when it is not.
fn (mut game Game) update_ship_preview() {
	game.player_grid.neutralize()
	if game.ship_needs_placed.len == 0 {
		return
	}
	ship := game.ship_needs_placed.last()
	size := core.ship_sizes[ship]
	pos := game.player_grid.cursor.Pos
	ok := game.player_grid.can_place_ship(size, pos, game.ship_orientation)
	n := if ok { core.Neutrality.good } else { core.Neutrality.bad }
	for i in 0 .. size {
		cell_pos := match game.ship_orientation {
			.horizontal { core.Pos{pos.x + i, pos.y} }
			.vertical { core.Pos{pos.x, pos.y + i} }
		}
		game.player_grid.set_neutrality(cell_pos, n)
	}
}

// start_flash kicks off the attack feedback flash on the given grid.
fn (mut game Game) start_flash(pos core.Pos, on_enemy bool) {
	game.flash_pos = pos
	game.flash_on_enemy = on_enemy
	game.flash_start = time.sys_mono_now() / 1_000_000
	game.flash_until = game.flash_start + 600
}

// update_flash toggles the flashing cell and clears it when the flash ends.
fn (mut game Game) update_flash() {
	if game.flash_pos.is_null() {
		return
	}
	now := time.sys_mono_now() / 1_000_000
	if now >= game.flash_until {
		if game.flash_on_enemy {
			game.enemy_grid.set_flash(game.flash_pos, false)
		} else {
			game.player_grid.set_flash(game.flash_pos, false)
		}
		game.flash_pos = core.Pos{-1, -1}
		return
	}
	on := ((now - game.flash_start) / 110) % 2 == 0
	if game.flash_on_enemy {
		game.enemy_grid.set_flash(game.flash_pos, on)
	} else {
		game.player_grid.set_flash(game.flash_pos, on)
	}
}

// draw_placement_help writes the current ship and the controls below the boards.
fn (mut game Game) draw_placement_help() {
	line := if game.ship_needs_placed.len == 0 {
		'All ships placed! Press Enter to start.'
	} else {
		ship := game.ship_needs_placed.last()
		orientation := if game.ship_orientation == .horizontal { 'horizontal' } else { 'vertical' }
		'Placing ${ship} (${core.ship_sizes[ship]}) - ${orientation}'
	}
	game.tui.draw_text(0, 21, line)
	game.tui.draw_text(0, 22, 'arrows move | r rotate | space place | u undo | a random | enter start')
}

// wait_for_enemy_ship_placement_event handles events that occur during the
// .wait_for_enemy_ship_placement_event state.
fn (mut game Game) wait_for_enemy_ship_placement_event(event &tui.Event) {
	match event.typ {
		.key_down {
			if event.code in [tui.KeyCode.left, .right, .up, .down] {
				game.move_cursor(event.code, mut game.enemy_grid, false)
			}
		}
		else {}
	}
}

// move_cursor moves the cursor on the grid.
fn (mut game Game) move_cursor(direction tui.KeyCode, mut grid core.Grid, send_to_server bool) {
	match direction {
		.left {
			if grid.cursor.x > 0 {
				grid.cursor.x--
			}
		}
		.right {
			if grid.cursor.x < 9 {
				grid.cursor.x++
			}
		}
		.up {
			if grid.cursor.y > 0 {
				grid.cursor.y--
			}
		}
		.down {
			if grid.cursor.y < 9 {
				grid.cursor.y++
			}
		}
		else {}
	}

	if !send_to_server {
		return
	}
	game.write_message(.set_cursor_pos) or {
		game.end(err.msg())
		return
	}
	game.write_cursor()
	game.server.flush() or {
		game.end(err.msg())
		return
	}
}

// frame is what is drawn to the terminal UI each frame.
fn frame(mut game Game) {
	game.width, game.height = term.get_terminal_size()
	game.tui.set_cursor_position(0, 0)

	_ := game.banner_text_channel.try_pop(mut game.banner_text)
	game.update_flash()

	match game.state {
		.wait_for_enemy_ship_placement { game.wait_for_enemy_ship_placement_frame() }
		.main_menu { game.main_menu_frame() }
		.placing_ships { game.placing_ships_frame() }
		.my_turn { game.my_turn_frame() }
		.their_turn { game.their_turn_frame() }
		.game_over { game.game_over_frame() }
	}

	game.tui.reset()
	game.tui.flush()
}

// wait_for_enemy_ship_placement_frame draws the screen in the
// .wait_for_enemy_ship_placement state.
fn (mut game Game) wait_for_enemy_ship_placement_frame() {
	game.draw_game()
}

// main_menu_frame draws the screen in the .main_menu state.
fn (mut game Game) main_menu_frame() {
	game.draw_banner()
	if game.show_settings {
		game.draw_settings()
		return
	}
	game.menu.draw_center(mut game)
}

// draw_settings shows the loaded configuration; edit config.toml to change it.
fn (mut game Game) draw_settings() {
	lines := [
		'Settings (edit ${config.file_path} to change)',
		'',
		'Server address : ${game.cfg.addr()}',
		'Colors         : ${if game.cfg.no_color { 'off' } else { 'on' }}',
		'',
		'Press any key to go back',
	]
	y := (game.height / 2) - (lines.len / 2)
	for i, line in lines {
		game.tui.draw_text((game.width / 2) - (line.len / 2), y + i, term.bright_white(line))
	}
}

// my_turn_frame draws the screen in the .my_turn state.
fn (mut game Game) my_turn_frame() {
	game.draw_game()
}

// placing_ships_frame draws the screen in the .placing_ships state.
fn (mut game Game) placing_ships_frame() {
	game.update_ship_preview()
	game.draw_game()
	game.draw_placement_help()
}

// their_turn_frame draws the screen in the .their_turn state.
fn (mut game Game) their_turn_frame() {
	game.draw_game()
}

// draw_game draws the player grid, enemy player grid, cursor position, and
// banner text to the screen.
fn (mut game Game) draw_game() {
	player := game.player_grid.str()
	enemy := game.enemy_grid.str()
	game.tui.draw_text(0, 0, util.merge_strings(player, enemy, 4, '::'))
	game.tui.draw_text(0, 15, Banner.text(game.banner_text))
	game.tui.draw_text(0, 19, 'Player Cursor: ${game.player_grid.cursor.val()}')
	game.tui.draw_text(0, 20, 'Enemy Cursor: ${game.enemy_grid.cursor.val()}')
}

// draw_text_center draws text to the screen centered on both the horizontal
// and vertical axes.
fn draw_text_center(mut game Game, text string) {
	str_offset := text.len / 2
	game.tui.draw_text(game.width / 2 - str_offset, game.height / 2, text)
}

// end ends a game and closes the connection to the server.
fn (mut game Game) end(msg string) {
	game.switch_state(.main_menu, none)
	game.server.close() or {}
	game.banner_text_channel <- msg
	if index := game.menu.find('Disconnect') {
		game.menu.items[index].state = .disabled
	}
	if index := game.menu.find('Online Play') {
		game.menu.selected = index
	}
}

// reset_grids wipes both boards and the per-round bookkeeping so a new
// round (or a new opponent) can start cleanly.
fn (mut game Game) reset_grids() {
	game.player_grid = core.Grid{
		name:           'Player'
		name_colorizer: fn (str string) string {
			return term.bright_blue(str)
		}
	}
	game.enemy_grid = core.Grid{
		name:           'Enemy'
		name_colorizer: fn (str string) string {
			return term.bright_red(str)
		}
	}
	game.ship_needs_placed = [.carrier, .battleship, .cruiser, .submarine, .destroyer]
	game.placed_ships = []
	game.ship_orientation = .horizontal
	game.has_enemy_placed_ships = false
	game.us_starts_game = false
	game.opponent_requested_rematch = false
	game.won = false
	game.last_attack_pos = core.Pos{}
}

// enter_game_over switches to the game over screen with the given result.
fn (mut game Game) enter_game_over(won bool, msg string) {
	game.won = won
	game.game_over_menu.selected = 0
	game.switch_state(.game_over, msg)
}

// game_over_event handles events that occur during the .game_over state.
fn (mut game Game) game_over_event(event &tui.Event) {
	match event.typ {
		.key_down {
			match event.code {
				.up { game.game_over_menu.move_up() }
				.down { game.game_over_menu.move_down() }
				.space, .enter { game.game_over_menu.selected().do() }
				else {}
			}
		}
		else {}
	}
}

// game_over_frame draws the boards, the result banner and the post-game menu.
fn (mut game Game) game_over_frame() {
	game.draw_game()
	game.game_over_menu.draw(mut game, 2, 22)
}

// request_rematch asks the server for another round against the same opponent.
fn (mut game Game) request_rematch() {
	game.write_message(.rematch_request) or { return }
	game.server.flush() or { return }
	game.banner_text_channel <- 'Waiting for opponent to accept the rematch...'
}

// find_new_opponent leaves the current opponent and reconnects to the queue.
fn (mut game Game) find_new_opponent() {
	game.write_message(.find_new_opponent) or {}
	game.server.flush() or {}
	game.want_requeue = true
	game.server.close() or {}
}
