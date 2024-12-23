module core

// messages are the bytes sent back and forth between the server and clients.
pub const messages = {
	'server': {
		// 0xF used to denote all messages from the server.
		'failed_to_read':     [u8(0xF0), 0x00]
		'failed_to_write':    [u8(0xF0), 0x01]
		'start_player':       [u8(0xF0), 0x02]
		'end_player':         [u8(0xF0), 0x03]
		'invalid_bytes':      [u8(0xF0), 0x04]
		'paired_with_player': [u8(0xF0), 0x05]
	}
	'client': {
		// 0x1 used to denote all messages sent from a client.
		'ships_placed':    [u8(0x10), 0x01]
		'cursor_position': [u8(0x10), 0x02]
		'attack':          [u8(0x10), 0x03]
	}
}

// Messages represents the messages that can be sent to and from the
// server and clients. 0x01 represents messages to/from clients and 0x02
// represents messages from the server. This leaves 3 bytes for messages.
pub enum Messages {
	null
	// client messages
	placed_ships = 0x01_000001
	set_cursor_pos
	attack_cell
	// server messages
	failed_to_read = 0x02_000001
	failed_to_write
	start_player
	not_start_player
	invalid_bytes
}
