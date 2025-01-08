module main

import net
import term
import rand
import core
import math
import time

const default_read_timeout = time.minute * 5
const default_write_timeout = time.second * 10

// Server handles everything related to player connections.
@[heap]
struct Server {
mut:
	listener net.TcpListener
	queue    shared []&PlayerTcpConn = []&PlayerTcpConn{}
	games    map[string]&Game
	// receives the uuid of the game being played
	ended_games_chan   chan string
	clean_games_thread thread
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
	states             []core.GameState
	players            []&PlayerTcpConn = []&PlayerTcpConn{}
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
		mut socket := &PlayerTcpConn{
			TcpConn: server.listener.accept() or {
				println(term.bright_red('[Server] ') + 'Failed to start listener: ${err.msg()}')
				exit(1)
			}
		}
		client_addr := socket.peer_addr() or {
			println(term.bright_red('[Server] Failed to get peer address.'))
			socket.close() or {}
			continue
		}

		println('[Server] new client (${socket.id}): ${client_addr}')
		spawn server.handle_client(mut socket)
	}

	server.listener.close() or { eprintln('[Server] Failed to close TCP listener:\n${err.msg()}.') }
}

// start starts a game by responding to player ship placement status.
// And by selecting a random player to start the game.
fn (mut g Game) start() {
	// choose the player at random to start the game
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

	g.handle_tcp_threads << spawn g.gameplay(start_player)
	g.handle_tcp_threads << spawn g.gameplay(end_player)
}

// gameplay is the meat and potatoes of the game of shattlebip where the
// players take turns blasting away towards the demise of each other.
fn (mut g Game) gameplay(index int) {
	mut player := g.players[index]
	mut enemy := g.players[math.abs(index - 1)]

	for {
		sz_msg := int(sizeof(core.Message))
		raw_msg := player.read_chunk(sz_msg) or {
			println('[Server] Failed to read bytes from client (blocking: ${player.get_blocking()}): ${err.msg()}')
			if err.code() == net.error_ewouldblock {
				time.sleep(10 * time.millisecond)
				continue
			}
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
				enemy.write(core.Message.attack_cell.to_bytes())
				enemy.write(pos_bytes)
				enemy.flush() or {
					println('[Server] Failed to flush bytes: ${err.msg()}')
					g.end()
					return
				}
				hit_or_miss_bytes := enemy.read_chunk(sz_msg) or {
					println('[Server] Failed to read Message: ${err.msg()}')
					g.end()
					return
				}
				hit_or_miss := core.Message.from_bytes(hit_or_miss_bytes) or {
					core.Message.invalid_bytes
				}
				if hit_or_miss !in [core.Message.hit, .miss, .not_your_turn] {
					println('[Server] unexpected message: ${hit_or_miss}')
					g.end()
					return
				}
				player.writef(hit_or_miss_bytes) or {
					println('[Server] Failed to write to player: ${err.msg()}')
					g.end()
					return
				}
			}
			.set_cursor_pos {
				sz_pos := int(sizeof(core.Pos))
				pos_bytes := player.read_chunk(sz_pos) or {
					println('[Server] failed to read Pos data: ${err.msg()}')
					g.end()
					return
				}
				enemy.write(raw_msg)
				enemy.write(pos_bytes)
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
			.terminate_connection {
				g.end()
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
	for mut player in g.players {
		player.writef(core.Message.connection_terminated.to_bytes()) or {
			println('[Server] Failed to write termination message: ${err.msg()}')
		}
	}
	g.server.ended_games_chan <- g.id
}

// close_game closes all the connections to players in a game.
@[inline]
fn (mut g Game) close_game() {
	for mut player in g.players {
		player.close() or {
			println(term.bright_red('[Server]') + 'Failed to properly close connection to player.')
		}
	}
}

// dispose_of_ended_games
fn (mut server Server) dispose_of_ended_games() {
	for {
		uuid := <-server.ended_games_chan
		mut game := server.games[uuid] or { continue }
		game.close_game()
		server.games.delete(uuid)
	}
}

// handle_client either queues players or pairs them for a game.
fn (mut server Server) handle_client(mut socket PlayerTcpConn) {
	// connection settings
	socket.set_blocking(true) or {
		println('[Server] failed to set blocking to true. Closing connection.')
		socket.close() or { println('[Server] failed to close connection: ${err.msg()}') }
		return
	}
	socket.set_write_timeout(default_write_timeout)
	socket.set_read_timeout(default_read_timeout)

	// queue the player or start the game
	if server.queue.len == 0 {
		socket.writef(core.Message.added_player_to_queue.to_bytes()) or {
			println(term.bright_red('[Server]') + ' failed to write line: ${err.msg()}')
			return
		}

		lock server.queue {
			server.queue << socket
		}
	} else {
		mut g := &Game{
			server: server
		}
		mut foe := unsafe { &PlayerTcpConn(nil) }
		lock server.queue {
			foe = server.queue.first()
			server.queue.delete(0)
		}
		g.players << foe
		g.players << socket
		g.states = [.placing_ships, .placing_ships]

		server.games[g.id] = g

		socket.writef(core.Message.paired_with_player.to_bytes()) or {
			println(term.bright_red('[Server]') + ' failed to write message: ${err.msg()}')
			return
		}
		foe.writef(core.Message.paired_with_player.to_bytes()) or {
			println(term.bright_red('[Server]') + ' failed to write message: ${err.msg()}')
			return
		}
		g.start()
	}
}

// init sets up the server and and loads config files.
fn (mut server Server) init() ! {
	server.listener = net.listen_tcp(.ip6, '[::1]:1902') or {
		return error('failed to listen on [::1]:1902')
	}
	laddr := server.listener.addr()!
	println('[Server] Listen on ${laddr} ...')
}

// unqueue removes a player from the queue of connections waiting to join a game.
fn (mut server Server) unqueue(id string) {
	mut index := -1
	rlock server.queue {
		for i, conn in server.queue {
			if conn.id == id {
				index = i
			}
		}
	}
	if _likely_(index != -1) {
		lock server.queue {
			server.queue.delete(index)
		}
	}
}
