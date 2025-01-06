import core
import net

fn test_message_to_from_bytes() {
	msg := core.Message.paired_with_player
	assert core.Message.null.to_bytes() == []u8{len: 4}
	assert msg == core.Message.from_bytes(msg.to_bytes())!
}

fn test_message_write_read_conn() {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:')!
	port := listener.addr()!.port()!
	spawn fn [mut listener, port] () ! {
		mut client := listener.accept()!
		msg := core.Message.read(mut client)!
		assert msg == core.Message.terminate_connection
		client.close()!
	}()
	mut server := net.dial_tcp('127.0.0.1:${port}')!
	core.Message.terminate_connection.write(mut server)!
	listener.close()!
	server.close()!
}
