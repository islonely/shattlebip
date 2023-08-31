module main

import io
import net
import term
import islonely.hex
import core

// Server handles everything related to player connections.
[heap]
struct Server {
mut:
	listener net.TcpListener
	queue    []&net.TcpConn = []&net.TcpConn{cap: 10}
	games    []&Game
}

// Game is the game that two players are currently playing.
[heap]
struct Game {
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

fn (mut g Game) start() {
}

// close_game closes all the connections to players in a game.
[inline]
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
		mut g := &Game{}
		mut foe := server.queue.first()
		g.players << foe
		g.players << socket
		server.queue.delete(0)

		// server.games << game
		writeln(mut socket, 'Paired with player. Game will start soon.')
		writeln(mut foe, 'Paired with player. Game will start soon.')
		g.start()
	}
}

[inline]
fn writeln(mut con net.TcpConn, str string) {
	con.write_string(str + '\n') or {
		println(term.bright_red('[Server]') + 'writeln: ${err.msg()}')
	}
}
