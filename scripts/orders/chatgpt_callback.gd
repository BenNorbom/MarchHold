extends RefCounted
## A short-lived loopback listener for a single browser OAuth callback.

const PATH := "/auth/callback"

var server := TCPServer.new()
var peer: StreamPeerTCP
var headers := ""
var peer_deadline := 0


func start() -> String:
	if server.listen(0, "127.0.0.1") != OK:
		return ""
	return "http://127.0.0.1:%d%s" % [server.get_local_port(), PATH]


func stop() -> void:
	if peer != null:
		peer.disconnect_from_host()
		peer = null
	server.stop()


func poll(state: String) -> Dictionary:
	if peer == null:
		if not server.is_connection_available():
			return {}
		peer = server.take_connection()
		if peer == null:
			return {}
		headers = ""
		peer_deadline = Time.get_ticks_msec() + 2000
	peer.poll()
	var available := peer.get_available_bytes()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() > peer_deadline or headers.length() + available > 16384:
		peer.disconnect_from_host()
		peer = null
		return {}
	if available == 0:
		return {}
	headers += peer.get_utf8_string(available)
	if not headers.contains("\r\n\r\n"):
		return {}
	var query := _parse(headers.get_slice("\r\n", 0), state)
	var status := "404 Not Found" if query.is_empty() else "200 OK"
	var message := "Callback not found." if query.is_empty() else "Return to MarchHold to finish signing in."
	var response := "HTTP/1.1 %s\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s"
	peer.put_data((response % [status, message.length(), message]).to_utf8_buffer())
	peer.disconnect_from_host()
	peer = null
	return query


static func _parse(request_line: String, state: String) -> Dictionary:
	var parts := request_line.split(" ")
	if parts.size() != 3 or parts[0] != "GET" or parts[1].get_slice("?", 0) != PATH:
		return {}
	var query := {}
	for pair in parts[1].get_slice("?", 1).split("&"):
		var entry := pair.split("=", true, 1)
		if entry.size() != 2:
			continue
		var key := entry[0].uri_decode()
		if query.has(key):
			return {}
		query[key] = entry[1].replace("+", " ").uri_decode()
	return query if query.get("state") == state else {}
