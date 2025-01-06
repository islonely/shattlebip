module main

import net
import term
import rand
import core
import math
import time

const default_read_timeout = time.minute * 5
const default_write_timeout = time.minute * 5

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
	net.TcpConn
mut:
	queue_index ?int
}

// Game is the game that two players are currently playing.
@[heap]
struct Game {
	id string = rand.uuid_v4()
mut:
	states             shared []core.GameState
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
		mut socket := server.listener.accept() or {
			println(term.bright_red('[Server] ') + 'Failed to start listener: ${err.msg()}')
			exit(1)
		}
		spawn server.handle_client(mut &PlayerTcpConn(socket))
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

	core.Message.start_player.write(mut g.players[start_player]) or {
		println('[Server] Failed to write to player[${start_player}]: ${err.msg()}')
		core.Message.failed_to_write.write(mut g.players[end_player]) or {
			println('[Server] Failed to write to player[${end_player}]: ${err.msg()}')
		}
		g.end()
		return
	}
	core.Message.not_start_player.write(mut g.players[end_player]) or {
		println('[Server] Failed to write to player[${end_player}]: ${err.msg()}')
		core.Message.failed_to_write.write(mut g.players[start_player]) or {
			println('[Server] Failed to write to player[${start_player}]: ${err.msg()}')
		}
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
		mut raw_msg := []u8{len: 4}
		player.read(mut raw_msg) or {
			println('[Server] failed to read bytes from client: ${err.msg()}')
			g.end()
			return
		}
		msg := core.Message.from_bytes(raw_msg) or {
			println('[Server] failed to convert bytes to Message: ${err.msg()}')
			g.end()
			return
		}
		match msg {
			.set_cursor_pos {
				mut pos_bytes := []u8{len: int(sizeof(core.Pos))}
				player.read(mut pos_bytes) or {
					println('[Server] failed to read Pos data: ${err.msg()}')
					g.end()
					return
				}
				core.Message.set_cursor_pos.write(mut enemy) or {
					println('[Server] failed to write Message: ${err.msg()}')
					g.end()
					return
				}
				enemy.write(pos_bytes) or {
					println('[Server] failed to write pos bytes: ${err.msg()}')
					g.end()
					return
				}
			}
			.placed_ships {
				msg.write(mut enemy) or {
					println('[Server] failed to write message: ${err.msg()}')
					g.end()
					return
				}
			}
			.terminate_connection {
				g.end()
			}
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
		core.Message.connection_terminated.write(mut player) or {}
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
	client_addr := socket.peer_addr() or {
		println(term.bright_red('[Server] Failed to get peer address.'))
		socket.close() or {}
		return
	}
	socket.set_read_timeout(default_read_timeout)
	socket.set_write_timeout(default_write_timeout)

	println('[Server] new client: ${client_addr}')
	if server.queue.len == 0 {
		core.Message.added_player_to_queue.write(mut socket) or {
			println(term.bright_red('[Server]') + ' failed to write line: ${err.msg()}')
			return
		}

		lock server.queue {
			socket.queue_index = server.queue.len
			server.queue << socket
		}
		for {
			msg := core.Message.read(mut socket) or {
				println(term.bright_red('[Server]') + ' Failed to read message: ${err.msg()}')
				return
			}

			match msg {
				.terminate_connection {
					if index := socket.queue_index {
						lock server.queue {
							server.queue.delete(index)
						}
						socket.queue_index = none
					}
					core.Message.connection_terminated.write(mut socket) or {}
					socket.close() or {}
				}
				else {}
			}
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
		lock g.states {
			g.states = [.placing_ships, .placing_ships]
		}

		server.games[g.id] = g

		core.Message.paired_with_player.write(mut socket) or {
			println(term.bright_red('[Server]') + ' failed to write line: ${err.msg()}')
			return
		}
		core.Message.paired_with_player.write(mut foe) or {
			println(term.bright_red('[Server]') + ' failed to write line: ${err.msg()}')
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
