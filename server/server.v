module main

import net
import term
import rand
import core
import math
import time
import sync

const default_read_timeout = time.minute * 5
const default_write_timeout = time.second * 10

// a game is force ended after this long, in seconds
const game_max_age_seconds = 60 * 60
// how often ended games are drained and active games scanned for staleness
const reap_interval = 5 * time.second

// GamePhase is what part of a match the game is currently in.
enum GamePhase {
	playing
	post_game
}

// Server handles everything related to player connections.
@[heap]
struct Server {
mut:
	listener net.TcpListener
	queue    []&PlayerTcpConn
	games    map[string]&Game
	// receives the uuid of the game being played
	ended_games_chan   chan string = chan string{ cap: 100 }
	clean_games_thread thread
	mutex              &sync.Mutex = sync.new_mutex()
}

// PlayerTcpConn is a TCP connection with an associated index in server queue.
@[heap]
pub struct PlayerTcpConn {
	core.BufferedTcpConn
mut:
	id string = rand.uuid_v4()
}

// Game is the game that two players are currently playing.
@[heap]
struct Game {
	id string = rand.uuid_v4()
mut:
	created_at         i64       = time.now().unix()
	phase              GamePhase = .playing
	rematch_requests   [2]bool
	mutex              &sync.Mutex = sync.new_mutex()
	states             []core.GameState
	players            []&PlayerTcpConn
	handle_tcp_threads []thread
	grids              []core.Grid = []core.Grid{}
	server             &Server
}

fn main() {
	mut server := &Server{}
	server.init() or {
		println(term.bright_red('[Server] ') + err.msg())
		exit(1)
	}
	server.clean_games_thread = spawn server.dispose_of_ended_games()
	for {
		accepted := server.listener.accept() or {
			println(term.bright_red('[Server] ') + 'Failed to start listener: ${err.msg()}')
			exit(1)
		}
		mut socket := &PlayerTcpConn{
			BufferedTcpConn: core.BufferedTcpConn{
				TcpConn: accepted
			}
		}
		client_addr := socket.peer_addr() or {
			println(term.bright_red('[Server] Failed to get peer address.'))
			socket.close() or {}
			continue
		}

		println('[Server] new client (${socket.id}): ${client_addr}')
		spawn server.handle_client(socket)
	}

	server.listener.close() or { eprintln('[Server] Failed to close TCP listener:\n${err.msg()}.') }
}

// start pairs two players into a fresh game and begins the first round.
fn (mut g Game) start() {
	g.begin_round(false)
	g.handle_tcp_threads << spawn g.gameplay(0)
	g.handle_tcp_threads << spawn g.gameplay(1)
}

// begin_round resets the per-round state and tells the players who goes
// first. Rematch rounds first ask both clients to reset their boards.
fn (mut g Game) begin_round(is_rematch bool) {
	if is_rematch {
		g.players[0].writef(core.Message.rematch_start.to_bytes()) or {
			g.end()
			return
		}
		g.players[1].writef(core.Message.rematch_start.to_bytes()) or {
			g.end()
			return
		}
	}

	g.mutex.lock()
	g.phase = .playing
	g.created_at = time.now().unix()
	g.rematch_requests[0] = false
	g.rematch_requests[1] = false
	g.mutex.unlock()

	// choose the player at random to start the round
	start_player := rand.int_in_range(0, 2) or {
		// just make player[0] go first if this fails
		println('[Server] Failed to generate random number: ${err.msg()}')
		0
	}
	end_player := math.abs(start_player - 1)

	g.players[start_player].writef(core.Message.start_player.to_bytes()) or {
		println('[Server] failed to write to player[${start_player}]: ${err.msg()}')
		g.end()
		return
	}
	g.players[end_player].writef(core.Message.not_start_player.to_bytes()) or {
		println('[Server] Failed to write to player[${end_player}]: ${err.msg()}')
		g.end()
		return
	}
}

// gameplay is the meat and potatoes of the game of shattlebip where the
// players take turns blasting away towards the demise of each other.
fn (mut g Game) gameplay(index int) {
	mut player := g.players[index]
	mut enemy := g.players[math.abs(index - 1)]

	for {
		sz_msg := int(sizeof(core.Message))
		raw_msg := player.read_chunk(sz_msg) or {
			println('[Server] Failed to read bytes from client: ${err.msg()}')
			g.end()
			return
		}
		msg := core.Message.from_bytes(raw_msg) or { core.Message.invalid_bytes }
		match msg {
			.attack_cell {
				sz_pos := int(sizeof(core.Pos))
				pos_bytes := player.read_chunk(sz_pos) or {
					println('[Server] failed to read Pos data: ${err.msg()}')
					g.end()
					return
				}
				enemy.write_buffered(core.Message.attack_cell.to_bytes())
				enemy.write_buffered(pos_bytes)
				enemy.flush() or {
					println('[Server] Failed to flush bytes: ${err.msg()}')
					g.end()
					return
				}
				// The opponent's own gameplay thread reads their reply and
				// forwards it back to us. Do NOT read from `enemy` here:
				// two threads reading one socket is the race that ends games.
			}
			.set_cursor_pos {
				sz_pos := int(sizeof(core.Pos))
				pos_bytes := player.read_chunk(sz_pos) or {
					println('[Server] failed to read Pos data: ${err.msg()}')
					g.end()
					return
				}
				enemy.write_buffered(raw_msg)
				enemy.write_buffered(pos_bytes)
				enemy.flush() or {
					println('[Server] failed to flush to enemy: ${err.msg()}')
					g.end()
					return
				}
			}
			.placed_ships {
				enemy.writef(raw_msg) or {
					println('[Server] failed to write message: ${err.msg()}')
					g.end()
					return
				}
			}
			.hit, .miss, .not_your_turn {
				// This thread owns the player who answered an attack, so
				// forward their reply to the opponent (the attacker).
				enemy.writef(raw_msg) or {
					println('[Server] failed to write reply: ${err.msg()}')
					g.end()
					return
				}
			}
			.defeated {
				// This player's fleet is gone; let the opponent know they won.
				g.mutex.lock()
				g.phase = .post_game
				g.mutex.unlock()
				enemy.writef(core.Message.opponent_defeated.to_bytes()) or {
					println('[Server] failed to write defeat: ${err.msg()}')
					g.end()
					return
				}
			}
			.rematch_request {
				mut both := false
				mut allowed := false
				g.mutex.lock()
				if g.phase == .post_game {
					g.rematch_requests[index] = true
					both = g.rematch_requests[0] && g.rematch_requests[1]
					allowed = true
				}
				g.mutex.unlock()
				if !allowed {
					continue
				}
				enemy.writef(core.Message.opponent_requested_rematch.to_bytes()) or {
					println('[Server] failed to write rematch request: ${err.msg()}')
					g.end()
					return
				}
				if both {
					g.begin_round(true)
				}
			}
			.find_new_opponent {
				enemy.writef(core.Message.opponent_left.to_bytes()) or {}
				g.end()
				return
			}
			.terminate_connection {
				g.end()
				return
			}
			.paired_with_player {}
			else {
				println('[Server] unexpected Message received: ${msg}')
				g.end()
				return
			}
		}
	}
}

// end push the Game.id to the channel for the server to handle.
@[inline]
fn (mut g Game) end() {
	g.server.ended_games_chan <- g.id
}

// close_game closes all the connections to players in a game.
@[inline]
fn (mut g Game) close_game() {
	for i in 0 .. g.players.len {
		g.players[i].close() or {
			println(term.bright_red('[Server]') + 'Failed to properly close connection to player.')
		}
	}
}

// dispose_of_ended_games reaps games that have ended or gotten too old.
fn (mut server Server) dispose_of_ended_games() {
	for {
		// drain every game that has ended since the last pass
		for {
			mut uuid := ''
			if server.ended_games_chan.try_pop(mut uuid) != .success {
				break
			}
			server.end_game(uuid)
		}

		now := time.now().unix()
		mut stale := []string{}
		server.mutex.lock()
		for game_id, game in server.games {
			if now - game.created_at > game_max_age_seconds {
				stale << game_id
			}
		}
		server.mutex.unlock()
		for game_id in stale {
			println('[Server] Reaping game past its ${game_max_age_seconds / 60} minute limit: ${game_id}')
			server.end_game(game_id)
		}

		time.sleep(reap_interval)
	}
}

// end_game removes a game from the active games and closes its connections.
fn (mut server Server) end_game(uuid string) {
	server.mutex.lock()
	game := server.games[uuid] or {
		server.mutex.unlock()
		return
	}
	server.games.delete(uuid)
	server.mutex.unlock()
	println('[Server] Ending game: ${uuid}')
	game.close_game()
}

// handle_client either queues players or pairs them for a game.
fn (mut server Server) handle_client(raw_socket &PlayerTcpConn) {
	// V 0.5.2 corrupts a spawned method's `mut &T` argument, so take an
	// immutable pointer and reborrow it as mutable for this thread.
	mut socket := unsafe { &PlayerTcpConn(raw_socket) }
	// connection settings
	socket.sock.set_option_bool(.keep_alive, true) or {
		println('[Server] Failed to set socket to keep alive. Cannot continue. Rejecting connection.')
		return
	}
	socket.set_write_timeout(default_write_timeout)
	socket.set_read_timeout(default_read_timeout)

	// queue the player or start the game
	server.mutex.lock()
	if server.queue.len == 0 {
		server.queue << socket
		server.mutex.unlock()
		socket.writef(core.Message.added_player_to_queue.to_bytes()) or {
			println(term.bright_red('[Server]') + ' failed to write line: ${err.msg()}')
			server.mutex.lock()
			server.dequeue(socket.id)
			server.mutex.unlock()
			return
		}
	} else {
		mut foe := server.queue.first()
		server.queue.delete(0)
		mut g := &Game{
			server: server
		}
		g.players << foe
		g.players << socket
		g.states = [.placing_ships, .placing_ships]
		server.games[g.id] = g
		server.mutex.unlock()

		socket.writef(core.Message.paired_with_player.to_bytes()) or {
			println(term.bright_red('[Server]') + ' failed to write message: ${err.msg()}')
			g.end()
			return
		}
		foe.writef(core.Message.paired_with_player.to_bytes()) or {
			println(term.bright_red('[Server]') + ' failed to write message: ${err.msg()}')
			g.end()
			return
		}
		g.start()
	}
}

// init sets up the server and and loads config files.
fn (mut server Server) init() ! {
	server.listener = net.listen_tcp(.ip, '127.0.0.1:1902') or {
		return error('failed to listen on 127.0.0.1:1902')
	}
	laddr := server.listener.addr()!
	println('[Server] Listen on ${laddr} ...')
}

// dequeue removes a player from the queue of connections waiting to join a
// game. Callers must hold Server.mutex.
fn (mut server Server) dequeue(id string) {
	mut index := -1
	for i, conn in server.queue {
		if conn.id == id {
			index = i
		}
	}
	if _likely_(index != -1) {
		server.queue.delete(index)
	}
}
