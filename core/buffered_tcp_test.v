module core

fn test_write_buffering() {
	mut c := BufferedTcpConn{}
	c.write_buffered([u8(1), 2, 3])
	assert c.write_buffer == [u8(1), 2, 3]
	c.write_buffered([u8(4)])
	assert c.write_buffer.len == 4
}

fn test_must_read_chunk_from_buffer() {
	mut c := BufferedTcpConn{}
	c.read_buffer = [u8(1), 2, 3, 4, 5]
	chunk := c.must_read_chunk(3)!
	assert chunk == [u8(1), 2, 3]
	assert c.read_buffer == [u8(4), 5]
}

fn test_message_and_pos_round_trip() {
	msg := Message.terminate_connection
	assert Message.from_bytes(msg.to_bytes())! == msg
	pos := Pos{5, 8}
	assert unsafe { Pos.from_bytes(pos.to_bytes()) } == pos
}
