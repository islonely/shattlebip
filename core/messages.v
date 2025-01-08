module core

// Message represents the messages that can be sent to and from the
// server and clients. 0x01 represents messages to/from clients and 0x02
// represents messages from the server. This leaves 3 bytes for messages.
pub enum Message as u32 {
	// message errors
	null
	invalid_bytes
	// client messages
	client_lower = 0x01_000000
	placed_ships
	set_cursor_pos
	attack_cell
	terminate_connection
	hit
	miss
	not_your_turn
	client_upper
	// server messages
	server_lower = 0x02_000000
	connection_terminated
	failed_to_read
	failed_to_write
	start_player
	not_start_player
	added_player_to_queue
	paired_with_player
	raw_bytes
	server_upper
}

// to_bytes converts Message to bytes.
pub fn (msg Message) to_bytes() []u8 {
	sz := sizeof(Message)
	mut return_bytes := []u8{len: int(sz)}
	unsafe {
		vmemcpy(return_bytes.data, &msg, sz)
	}
	return return_bytes
}

// Message.from_bytes takes bytes and converts them to Message.
pub fn Message.from_bytes(src_bytes []u8) !Message {
	sz := sizeof(Message)
	mut return_msg := vcalloc(sz)
	unsafe {
		vmemcpy(return_msg, src_bytes.data, int(sz))
	}

	// check that the value exists in Message before attempting to cast
	// return_msg to &Message.
	int_val := unsafe { *&int(return_msg) }
	is_val_in_message_enum := int_val in [0, 1]
		|| (int_val > int(Message.client_lower) && int_val < int(Message.client_upper))
		|| (int_val > int(Message.server_lower) && int_val < int(Message.server_upper))
	if _unlikely_(!is_val_in_message_enum) {
		return error('invalid val (${int_val})')
	}

	unsafe { free(return_msg) }
	return unsafe { Message(int_val) }
}

// Message.is_valid_bytes checks whether the bytes are a valid value in enum Message.
pub fn Message.is_valid_bytes(src_bytes []u8) bool {
	sz := sizeof(Message)
	if src_bytes.len != sz {
		return false
	}
	mut return_msg := vcalloc(sz)
	unsafe {
		vmemcpy(return_msg, src_bytes.data, int(sz))
	}

	// check that the value exists in Message before attempting to cast
	// return_msg to &Message.
	int_val := unsafe { *&int(return_msg) }
	is_val_in_message_enum := int_val in [0, 1]
		|| (int_val > int(Message.client_lower) && int_val < int(Message.client_upper))
		|| (int_val > int(Message.server_lower) && int_val < int(Message.server_upper))
	if is_val_in_message_enum {
		return true
	}
	return false
}
