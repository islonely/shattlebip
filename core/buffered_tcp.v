module core

import net

// BufferedTcpConn is a TCP connection that allows you to
// buffer data that is read/written instead of waiting on
// each packet sent to be manually read from the other end.
@[heap]
pub struct BufferedTcpConn {
	net.TcpConn
pub mut:
	read_buffer  []u8 = []u8{cap: 1024}
	write_buffer []u8 = []u8{cap: 1024}
__global:
	// the amount of bytes that will be sent across the connection at one time
	// if none, then all bytes will be sent at once.
	packet_size ?u16
}

// BufferedTcpConn.new creates a buffered reader for the provided
// TCP connection.
@[inline]
pub fn BufferedTcpConn.new(mut conn net.TcpConn) &BufferedTcpConn {
	mut bufconn := &BufferedTcpConn{
		TcpConn: conn
	}

	return bufconn
}

// write adds the provided bytes to the buffer.
@[inline]
pub fn (mut conn BufferedTcpConn) write(bytes []u8) int {
	conn.write_buffer << bytes
	return bytes.len
}

// writef adds the data to the buffer and flushes to the TCP connection.
@[inline]
pub fn (mut conn BufferedTcpConn) writef(bytes []u8) !int {
	len := conn.write(bytes)
	conn.flush()!
	return len
}

// flush sends the buffer contents to the TCP connection.
pub fn (mut conn BufferedTcpConn) flush() ! {
	if packet_size := conn.packet_size {
		for conn.write_buffer.len > 0 {
			sz := if conn.write_buffer.len < packet_size {
				conn.write_buffer.len
			} else {
				packet_size
			}
			conn.TcpConn.write(conn.write_buffer[0..sz])!
			conn.write_buffer = conn.write_buffer[sz..]
		}
	} else {
		conn.TcpConn.write(conn.write_buffer)!
		conn.write_buffer = []u8{cap: 1024}
	}
}

// read reads data into the provided buffer.
pub fn (mut conn BufferedTcpConn) read(mut buf []u8) !int {
	bytes := conn.read_chunk(buf.len)!
	unsafe { vmemcpy(buf.data, bytes.data, bytes.len) }
	return bytes.len
}

// read_chunk reads `chunk_size` amount of data from the buffer.
pub fn (mut conn BufferedTcpConn) read_chunk(chunk_size int) ![]u8 {
	// if buffer has enough data read from buffer
	if conn.read_buffer.len >= chunk_size {
		chunk := conn.read_buffer[..chunk_size].clone()
		conn.read_buffer = conn.read_buffer[chunk_size..]
		return chunk
	}

	// read more data from connection
	mut buf := []u8{len: 1024}
	len := conn.TcpConn.read(mut buf) or { return err }
	conn.read_buffer << buf[..len]

	// if buffer still does not have enough data return error
	if conn.read_buffer.len < chunk_size {
		return error('not enough data')
	}

	chunk := conn.read_buffer[..chunk_size].clone()
	conn.read_buffer = conn.read_buffer[chunk_size..]
	return chunk
}
