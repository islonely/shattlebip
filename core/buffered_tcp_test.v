import core { Message }
import net

fn test_buffered_tcp() {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:')!
	port := listener.addr()!.port()!
	spawn fn [mut listener, port] () ! {
		mut conn := listener.accept()!
		mut client := core.BufferedTcpConn.new(mut conn)
		sz := int(sizeof(Message))
		msg_bytes := client.read_chunk(sz)!
		msg := Message.from_bytes(msg_bytes)!
		assert msg == Message.terminate_connection
		pos_msg_bytes := client.read_chunk(sz)!
		pos_msg := Message.from_bytes(pos_msg_bytes)!
		assert pos_msg == Message.set_cursor_pos
		pos_sz := int(sizeof(core.Pos))
		pos_bytes := client.read_chunk(pos_sz)!
		pos := core.Pos.from_bytes(pos_bytes)
		assert pos == core.Pos{5, 8}
		client.close() or {}
	}()
	mut conn := net.dial_tcp('127.0.0.1:${port}')!
	mut server := core.BufferedTcpConn.new(mut conn)
	server.writef(Message.terminate_connection.to_bytes())!
	server.write(Message.set_cursor_pos.to_bytes())
	server.write(core.Pos{5, 8}.to_bytes())
	server.flush()!
	listener.close() or {}
	server.close() or {}
}
