module main

import io
import net
import term
import rand
import core
import math

// Server handles everything related to player connections.
@[heap]
struct Server {
mut:
	listener net.TcpListener
	queue    []&net.TcpConn = []&net.TcpConn{cap: 10}
	games    map[string]&Game
}

// Game is the game that two players are currently playing.
@[heap]
struct Game {
	id string
mut:
	players []&net.TcpConn = []&net.TcpConn{cap: 2}
	grids   []core.Grid    = []core.Grid{cap: 2}
}

fn main() {
	mut server := &Server{
		listener: net.listen_tcp(.ip6, ':1902')!
	}
	laddr := server.listener.addr()!
	eprintln('Listen on ${laddr} ...')
	for {
		mut socket := server.listener.accept()!
		spawn server.handle_client(mut socket)
	}
}

// start starts a game by responding to player ship placement status.
// And by selecting a random player to start the game.
fn (mut g Game) start() {
	// Pre-game: placing ships.
	// read bytes from player[0] and send to player[1]
	mut buf := []u8{len: 1000, init: 0}
	g.players[0].read(mut buf) or {
		g.players[1].write(core.messages['server']['failed_to_read']) or {
			println('[Server] Failed to write to player[1]: ${err.msg()}')
		}
		println('[Server] Failed to read from player[0]: ${err.msg()}')
		return
	}
	mut bytes := []u8{cap: 1000}
	for b in buf {
		if b == 0 {
			break
		}
		bytes << b
	}
	g.players[1].write(bytes) or {
		println('[Server] Failed to write to player[1]: ${err.msg()}')
		return
	}

	// read bytes from player[1] and send to player[0]
	buf = []u8{len: 1000, init: 0}
	g.players[1].read(mut buf) or {
		g.players[0].write(core.messages['server']['failed_to_read']) or {
			println('[Server] Failed to write to player[1]: ${err.msg()}')
		}
		println('[Server] Failed to read from player[0]: ${err.msg()}')
		return
	}
	bytes = []u8{cap: 1000}
	for b in buf {
		if b == 0 {
			break
		}
		bytes << b
	}
	g.players[0].write(bytes) or {
		println('[Server] Failed to write to player[0]: ${err.msg()}')
		return
	}

	// choose the player at random to start the game
	start_player := rand.int_in_range(0, 2) or {
		// just make player[0] go first if this fails
		println('[Server] Failed to generate random number: ${err.msg()}')
		0
	}
	// since the only indices in the array are 0 and 1
	// abs(0-1) = 1 or abs(1-0) = 0
	end_player := math.abs(start_player - 1)
	// send bytes to player letting them know who won the random chance
	g.players[start_player].write(core.messages['server']['start_player']) or {
		println('[Server] Failed to write to player[${start_player}]: ${err.msg()}')
		g.players[end_player].write(core.messages['server']['failed_to_write']) or {
			println('[Server] Failed to write to player[${end_player}]: ${err.msg()}')
		}
		return
	}
	g.players[end_player].write(core.messages['server']['end_player']) or {
		println('[Server] Failed to write to player[${end_player}]: ${err.msg()}')
		g.players[end_player].write(core.messages['server']['failed_to_write']) or {
			println('[Server] Failed to write to player[${end_player}]: ${err.msg()}')
		}
		return
	}

	g.gameplay(start_player)
}

// gameplay is the meat and potatoes of the game of shattlebip where the
// players take turns blasting away towards the demise of each other.
fn (mut g Game) gameplay(index int) {
	// mut turn := index
	for {
		// assumes index is either 0 or 1
		i := index
		j := math.abs(i - 1)
		// read message type from player
		mut buf := []u8{len: 2}
		g.players[i].read(mut buf) or {
			println('[Server] Failed to read bytes from player[${i}]: ${err.msg()}')
			g.players[j].write(core.messages['server']['failed_to_read']) or {
				println('[Server] Failed to write bytes to player[${j}]: ${err.msg()}')
			}
			return
		}

		// if message type is not in known list
		if buf !in core.messages['client'].values() {
			g.players[j].write(core.messages['server']['invalid_bytes']) or {
				println('[Server] Failed to write to player[${j}]: ${err.msg()}')
			}
			return
		}

		// write type of message to other player
		g.players[j].write(buf) or {
			println('[Server] Failed to write to player[${j}]: ${err.msg()}')
			g.players[i].write(core.messages['server']['failed_to_write']) or {
				println('[Server] Faield to write to player[${i}]: ${err.msg()}')
			}
			return
		}
		// read message contents from player
		passthrough := g.players[i].read_line()
		// write message contents to other player
		g.players[j].write_string(passthrough) or {
			println('[Server] Failed to write to player[${j}]: ${err.msg()}')
			g.players[i].write(core.messages['server']['failed_to_write']) or {
				println('[Server] Failed to write to player[${i}]: ${err.msg()}')
			}
			return
		}
	}
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

// handle_client either queues players or pairs them for a game.
fn (mut server Server) handle_client(mut socket net.TcpConn) {
	client_addr := socket.peer_addr() or { return }
	eprintln('> new client: ${client_addr}')
	mut reader := io.new_buffered_reader(reader: socket)
	defer {
		unsafe {
			reader.free()
		}
	}
	socket.write_string('Connection received.\n') or { return }
	if server.queue.len == 0 {
		writeln(mut socket, 'No available players. Adding to queue.')
		server.queue << socket
	} else {
		mut g := &Game{
			id: rand.uuid_v4()
		}
		mut foe := server.queue.first()
		g.players << foe
		g.players << socket
		server.queue.delete(0)
		// server.games[g.id] = g

		// server.games << game
		writeln(mut socket, 'Paired with player. Game will start soon.')
		writeln(mut foe, 'Paired with player. Game will start soon.')
		g.start()
	}
}

// writeln sends a line across the TCP connection without regard to
// whether or not an error returned.
@[inline]
fn writeln(mut con net.TcpConn, str string) {
	con.write_string(str + '\n') or {
		println(term.bright_red('[Server]') + 'writeln: ${err.msg()}')
	}
}
