extends Node
## One local ChatGPT connection per Windows user. All network endpoints are fixed.

const Identity = preload("res://scripts/orders/chatgpt_identity.gd")
const Callback = preload("res://scripts/orders/chatgpt_callback.gd")
const Vault = preload("res://scripts/orders/chatgpt_vault.gd")
const ISSUER := Identity.ISSUER
const RESOURCE := "https://api.openai.com/v1"
const USAGE_URL := "https://chatgpt.com/settings/usage"
const PERMISSION := "chatgpt.tokens.use.direct"
const TOKEN_URL := ISSUER + "/api/accounts/oauth/token"
const NEW_CLIENT := "dynamic_agent_client"
const SIGN_IN_REQUIRED := "Continue with ChatGPT in Settings to use your plan."
const USAGE_LIMIT := "MarchHold reached a ChatGPT usage limit. Review Manage usage in Settings."

var waiting_for_browser := false
var usage_limited := false
var _busy := false
var _account := {}
var _http: HTTPRequest
var _crypto := Crypto.new()


func _ready() -> void:
	_account = Vault.read()
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	_http.use_threads = true
	_http.max_redirects = 0
	_http.body_size_limit = 2 * 1024 * 1024
	add_child(_http)


func signed_in() -> bool:
	return _account.has("subject") and _account.has("id_token")


func registered() -> bool:
	return _account.has("client")


func email() -> String:
	return str(_account.get("email", ""))


func can_use_plan() -> bool:
	return _account.has("access_token") and _has_permission(str(_account.get("scope", "")))


func cancel_sign_in() -> void:
	waiting_for_browser = false


func sign_in() -> String:
	if _busy:
		return "A ChatGPT connection request is already in progress."
	_busy = true
	var error := await _sign_in()
	_busy = false
	return error


func _sign_in() -> String:
	var host := str(_account.get("host", ""))
	if host == "":
		var bytes := _crypto.generate_random_bytes(16)
		bytes[6] = (bytes[6] & 0x0f) | 0x40
		bytes[8] = (bytes[8] & 0x3f) | 0x80
		var hex := bytes.hex_encode()
		host = "urn:uuid:%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20)]
		if not _save({"host": host}):
			return "MarchHold could not protect the ChatGPT connection on this PC."
	var callback := Callback.new()
	var redirect := callback.start()
	if redirect == "":
		return "Could not open the local ChatGPT sign-in callback."
	var client := str(_account.get("client", ""))
	var state := _random()
	var nonce := _random()
	var verifier := _random()
	var params := {
		"client_id": client if client != "" else NEW_CLIENT,
		"ext_agent_host_id": host,
		"response_type": "code",
		"redirect_uri": redirect,
		"scope": "openid profile email offline_access resource.invoke " + PERMISSION,
		"resource": RESOURCE,
		"state": state,
		"nonce": nonce,
		"code_challenge_method": "S256",
		"code_challenge": Identity.base64url(verifier.sha256_buffer()),
	}
	if client == "":
		params["agent_name_hint"] = "MarchHold"
	else:
		if _account.has("id_token"):
			params["id_token_hint"] = _account["id_token"]
		if not can_use_plan():
			params["prompt"] = "consent"
	if OS.shell_open(ISSUER + "/api/accounts/authorize?" + _form(params)) != OK:
		callback.stop()
		return "Could not open your browser for ChatGPT sign-in."
	waiting_for_browser = true
	var deadline := Time.get_ticks_msec() + 180000
	var query := {}
	while waiting_for_browser and query.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		query = callback.poll(state)
	callback.stop()
	var cancelled := not waiting_for_browser
	waiting_for_browser = false
	if cancelled:
		return "ChatGPT sign-in cancelled."
	if query.is_empty():
		return "ChatGPT sign-in timed out. Try again in Settings."
	if query.has("error"):
		return "ChatGPT sign-in or plan permission was declined." if query["error"] == "access_denied" else "ChatGPT sign-in was interrupted."
	var issued := str(query.get("client_id", client))
	if issued == "" or issued == NEW_CLIENT or (client != "" and issued != client) or str(query.get("code", "")) == "":
		return "ChatGPT did not return a valid MarchHold authorization."
	if client == "" and not _save({"host": host, "client": issued}):
		return "MarchHold could not save the new ChatGPT registration."
	var exchange := await _request(TOKEN_URL, {"grant_type": "authorization_code", "client_id": issued,
		"code": query["code"], "code_verifier": verifier, "redirect_uri": redirect, "resource": RESOURCE})
	if exchange["status"] != 200:
		return "ChatGPT could not finish sign-in. Try again in Settings."
	var tokens: Dictionary = exchange["data"]
	var jwks := await _request(ISSUER + "/.well-known/jwks.json")
	var keys = jwks["data"].get("keys")
	if jwks["status"] != 200 or not keys is Array:
		return "MarchHold could not verify your ChatGPT sign-in. Try again."
	var claims := Identity.verify(str(tokens.get("id_token", "")), keys, issued, nonce)
	if claims.is_empty():
		return "MarchHold could not verify your ChatGPT identity."
	if _account.has("subject") and _account["subject"] != claims["sub"]:
		return "ChatGPT returned a different account. Disconnect before switching accounts."
	var account := {"host": host, "client": issued, "subject": claims["sub"],
		"email": claims.get("email", ""), "id_token": tokens["id_token"]}
	var scope := str(tokens.get("scope", ""))
	if _has_permission(scope):
		if not _set_tokens(account, tokens, scope) or not account.has("refresh_token"):
			return "ChatGPT did not return a renewable plan connection. Sign in again."
	if not _save(account):
		return "MarchHold could not protect the ChatGPT connection on this PC."
	usage_limited = false
	return ""


func disconnect_account() -> String:
	if _busy:
		return "A ChatGPT connection request is already in progress."
	_busy = true
	var previous := _account
	if not _save({"host": previous.get("host", "")}):
		_busy = false
		return "MarchHold could not clear the local ChatGPT connection."
	usage_limited = false
	var error := ""
	if previous.has("refresh_token"):
		var fields := {"token": previous["refresh_token"], "token_type_hint": "refresh_token", "client_id": previous["client"]}
		var revoked := await _request(ISSUER + "/api/accounts/oauth/revoke", fields)
		if revoked["status"] == 0 or revoked["status"] >= 500:
			await get_tree().create_timer(0.5).timeout
			revoked = await _request(ISSUER + "/api/accounts/oauth/revoke", fields)
		if revoked["status"] != 200:
			error = "Disconnected here. To confirm removal, disconnect MarchHold in ChatGPT login connections."
	_busy = false
	return error


func access_token() -> Dictionary:
	if not can_use_plan():
		return {"error": SIGN_IN_REQUIRED}
	if usage_limited:
		return {"error": USAGE_LIMIT}
	if _busy:
		return {"error": "A ChatGPT connection request is already in progress. Try again shortly."}
	if float(_account.get("expires", 0)) > Time.get_unix_time_from_system() + 60:
		return {"token": _account["access_token"]}
	_busy = true
	var result := await _refresh()
	_busy = false
	return result


func _refresh() -> Dictionary:
	var fields := {"grant_type": "refresh_token", "client_id": _account["client"],
		"refresh_token": _account["refresh_token"], "resource": RESOURCE}
	var response := await _request(TOKEN_URL, fields)
	var tokens: Dictionary = response["data"]
	if response["status"] != 200:
		var code = tokens.get("error")
		if code is Dictionary:
			code = code.get("code")
		if code in ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"]:
			invalidate()
			return {"error": SIGN_IN_REQUIRED}
		return {"error": "Could not renew the ChatGPT connection. Try again shortly."}
	var refreshed := _account.duplicate()
	var scope := str(tokens.get("scope", refreshed.get("scope", "")))
	if not _has_permission(scope):
		invalidate()
		return {"error": "ChatGPT plan permission ended. " + SIGN_IN_REQUIRED}
	if not _set_tokens(refreshed, tokens, scope):
		return {"error": "ChatGPT returned an incomplete connection. Continue with ChatGPT in Settings."}
	if not _save(refreshed):
		# Keep the rotated token for a later save rather than reusing the old one.
		_account = refreshed
		return {"error": "MarchHold could not save the renewed ChatGPT connection."}
	return {"token": refreshed["access_token"]}


func invalidate() -> void:
	var registration := _account.duplicate()
	for key in ["access_token", "refresh_token", "expires", "scope"]:
		registration.erase(key)
	_save(registration)
	_account = registration


func invalidate_token(token: String) -> void:
	if _account.get("access_token") == token:
		invalidate()


func models() -> Dictionary:
	var auth := await access_token()
	if auth.has("error"):
		return auth
	_busy = true
	var response := await _request(RESOURCE + "/models", {}, auth["token"])
	_busy = false
	if response["status"] == 401:
		invalidate()
		return {"error": SIGN_IN_REQUIRED}
	var catalog = response["data"].get("models")
	if response["status"] != 200 or not catalog is Array:
		return {"error": "Could not load your ChatGPT models. Use Refresh models to try again."}
	var list: Array[Dictionary] = []
	for model in catalog:
		if model is Dictionary and model.get("visibility") == "list" and model.get("slug") is String:
			list.append({"id": model["slug"], "name": str(model.get("display_name", model["slug"]))})
	return {"models": list}


func _save(account: Dictionary) -> bool:
	if not Vault.write(account):
		return false
	_account = account
	return true


func _set_tokens(account: Dictionary, tokens: Dictionary, scope: String) -> bool:
	var access := str(tokens.get("access_token", ""))
	var seconds := int(tokens.get("expires_in", 0))
	if access == "" or seconds <= 0:
		return false
	account["access_token"] = access
	account["scope"] = scope
	account["expires"] = Time.get_unix_time_from_system() + seconds
	if str(tokens.get("refresh_token", "")) != "":
		account["refresh_token"] = tokens["refresh_token"]
	return true


func _random() -> String:
	return Identity.base64url(_crypto.generate_random_bytes(32))


func _has_permission(scope: String) -> bool:
	return PERMISSION in scope.split(" ", false)


func _request(url: String, form: Dictionary = {}, token: String = "") -> Dictionary:
	var headers := PackedStringArray(["Accept: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	if not form.is_empty():
		headers.append("Content-Type: application/x-www-form-urlencoded")
	var method := HTTPClient.METHOD_GET if form.is_empty() else HTTPClient.METHOD_POST
	if _http.request(url, headers, method, _form(form)) != OK:
		return {"status": 0, "data": {}}
	var response: Array = await _http.request_completed
	var data = JSON.parse_string(response[3].get_string_from_utf8()) if not response[3].is_empty() else null
	return {"status": response[1] if response[0] == HTTPRequest.RESULT_SUCCESS else 0,
		"data": data if data is Dictionary else {}}


func _form(fields: Dictionary) -> String:
	var form := PackedStringArray()
	for key in fields:
		form.append(str(key).uri_encode() + "=" + str(fields[key]).uri_encode())
	return "&".join(form)
