module core

// messages are the bytes sent back and forth between the server and clients.
pub const messages = {
	'server': {
		// 0xF used to denote all messages from the server.
		'failed_to_read':  [u8(0xF0), 0x00]
		'failed_to_write': [u8(0xF0), 0x01]
		'start_player':    [u8(0xF0), 0x02]
		'end_player':      [u8(0xF0), 0x03]
		'invalid_bytes':   [u8(0xF0), 0x04]
	}
	'client': {
		// 0x1 used to denote allmessages sent from a client.
		'ships_placed':    [u8(0x10), 0x01]
		'cursor_position': [u8(0x10), 0x02]
	}
}
