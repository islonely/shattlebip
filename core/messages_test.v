import core

fn test_message_to_from_bytes() {
	msg := core.Message.paired_with_player
	unsafe {
		assert core.Message.null.to_bytes() == []u8{len: 4}
		assert msg == core.Message.from_bytes(msg.to_bytes())!
	}
}
