extends Node
## Terra sends free-text orders using the player's chosen connection.
## It returns {kind, reply, steps}. The model only proposes; the
## simulation validates every step.

const Schema = preload("res://scripts/orders/schema.gd")
const URL := "https://api.openai.com/v1/responses"

signal answered(result: Dictionary)

var http: HTTPRequest
var busy := false
var requests := 0
var _plan_token := ""


func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 30.0
	http.use_threads = true
	http.max_redirects = 0
	http.body_size_limit = 4 * 1024 * 1024
	add_child(http)
	http.request_completed.connect(_on_done)


func available() -> bool:
	return Settings.terra_available()


func remaining() -> int:
	return int(Settings.get_val("request_limit", 120)) - requests


func _reasoning_for(model: String):
	var mm := model.to_lower()
	if mm.begins_with("gpt-4") or mm.begins_with("o1") or mm.begins_with("gpt-3"):
		return null
	if mm.begins_with("gpt-5-") or mm == "gpt-5" or mm.begins_with("o3") or mm.begins_with("o4"):
		return {"effort": "minimal"}
	return {"effort": "none"}


func ask(facts: Dictionary, message: String, history: Array) -> void:
	if busy:
		return
	if not available():
		answered.emit({"ok": false, "error": "Choose a Terra connection in Settings to give orders in your own words."})
		return
	if remaining() <= 0:
		answered.emit({"ok": false, "error": "Terra has answered the most requests allowed this match. Simple orders and slash commands still work."})
		return
	var input := {"facts": facts, "history": history, "message": message}
	busy = true
	_plan_token = ""
	if Settings.get_val("terra_provider") == Settings.CHATGPT_PLAN:
		await _ask_chatgpt(input)
		return
	var model := str(Settings.get_val("model", Settings.DEFAULT_MODEL))
	var body := {
		"model": model,
		"store": false,
		"max_output_tokens": 1200,
		"instructions": Schema.instructions(),
		"input": JSON.stringify(input),
		"text": {"format": {"type": "json_schema", "name": "village", "strict": true, "schema": Schema.plan_schema(_places(input))}},
	}
	var reasoning = _reasoning_for(model)
	if reasoning != null:
		body["reasoning"] = reasoning
	_send(body, Settings.api_key, "application/json")


func _ask_chatgpt(input: Dictionary) -> void:
	var model := str(Settings.get_val("chatgpt_model", ""))
	if model == "":
		_fail("Open Settings and choose an order model from your ChatGPT plan.")
		return
	var auth := await ChatGPT.access_token()
	if auth.has("error"):
		_fail(auth["error"])
		return
	_plan_token = auth["token"]
	var instructions := Schema.instructions() + "\nReturn only a JSON object matching this schema: " + JSON.stringify(Schema.plan_schema(_places(input)))
	_send({"model": model, "store": false, "stream": true, "instructions": instructions,
		"input": [{"role": "user", "content": JSON.stringify(input)}]}, _plan_token, "text/event-stream")


func _places(input: Dictionary) -> Array:
	return input["facts"].get("places", {}).keys()


func _send(body: Dictionary, token: String, accept: String) -> void:
	var headers := PackedStringArray(["Authorization: Bearer " + token, "Content-Type: application/json", "Accept: " + accept])
	var err := http.request(URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_fail("Could not reach OpenAI. Check your connection and try again.")
	else:
		requests += 1


func _fail(error: String) -> void:
	busy = false
	_plan_token = ""
	answered.emit({"ok": false, "error": error})


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_TIMEOUT:
		_fail("OpenAI took too long to respond. Try again.")
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("Could not reach OpenAI. Check your connection and try again.")
		return
	var text := body.get_string_from_utf8()
	if _plan_token != "":
		_on_chatgpt_done(code, text)
		return
	var data = JSON.parse_string(text)
	if code != 200:
		_fail(_error_text(code, data))
		return
	if not (data is Dictionary):
		_fail("Terra did not return a readable answer. Try rephrasing your order.")
		return
	var out := ""
	for item in data.get("output", []):
		if item is Dictionary:
			for c in item.get("content", []):
				if c is Dictionary and c.get("type", "") == "output_text":
					out = str(c.get("text", ""))
	_finish(out)


func _on_chatgpt_done(code: int, body: String) -> void:
	if code != 200:
		var data = JSON.parse_string(body)
		_fail(_plan_error(code, data.get("error") if data is Dictionary else null))
		return
	var response := _read_stream(body)
	if response.has("text"):
		var output := str(response["text"]).strip_edges()
		if output.begins_with("```") and output.ends_with("```"):
			output = output.substr(output.find("\n") + 1).trim_suffix("```").strip_edges()
		_finish(output)
	elif response.has("error"):
		_fail(_plan_error(0, response["error"]))
	else:
		_fail("ChatGPT did not finish the answer. Try again.")


static func _read_stream(body: String) -> Dictionary:
	var output := ""
	for event in body.replace("\r\n", "\n").split("\n\n", false):
		var data := PackedStringArray()
		for line in event.split("\n", false):
			if line.begins_with("data:"):
				data.append(line.substr(5).strip_edges())
		if data.is_empty() or data[0] == "[DONE]":
			continue
		var item = JSON.parse_string("\n".join(data))
		if not item is Dictionary:
			return {}
		match item.get("type"):
			"response.output_text.delta":
				output += str(item.get("delta", ""))
			"response.completed":
				return {"text": output}
			"response.failed":
				var response = item.get("response")
				return {"error": response.get("error") if response is Dictionary else null}
			"response.incomplete", "error":
				return {"error": item.get("error", item)}
	return {}


func _finish(output: String) -> void:
	var parsed := Schema.parse_plan(output)
	if parsed.is_empty():
		_fail("Terra did not return a readable answer. Try rephrasing your order.")
		return
	busy = false
	_plan_token = ""
	answered.emit({"ok": true, "data": parsed})


func _plan_error(status: int, error) -> String:
	var code := str(error.get("code", "")) if error is Dictionary else ""
	if code == "subscription_sharing_usage_limit_exceeded" or status == 429:
		ChatGPT.usage_limited = true
		return ChatGPT.USAGE_LIMIT
	if status == 401:
		ChatGPT.invalidate_token(_plan_token)
		return ChatGPT.SIGN_IN_REQUIRED
	if code == "subscription_sharing_user_not_eligible" or status == 403:
		return "ChatGPT plan access is unavailable for this account or workspace."
	if code in ["model_not_found", "subscription_sharing_unsupported_capability"] or status in [400, 404]:
		return "That model or request is unavailable on your ChatGPT plan. Check Order model in Settings."
	if status >= 500 or code in ["subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable"]:
		return "ChatGPT plan usage is temporarily unavailable. Try again shortly."
	return "ChatGPT could not finish Terra's answer. Try again."


## Local messages chosen from error codes (the API body is never shown, it can echo credentials).
func _error_text(code: int, data) -> String:
	var ecode := ""
	var etype := ""
	if data is Dictionary and data.get("error") is Dictionary:
		ecode = str(data["error"].get("code", ""))
		etype = str(data["error"].get("type", ""))
	if code == 401:
		return "OpenAI rejected the API key. Replace it in Settings."
	if code == 429:
		if ecode == "insufficient_quota" or etype == "insufficient_quota":
			return "Your OpenAI API quota is exhausted. Check API billing and spending limits."
		if ecode == "credit_balance_exhausted":
			return "Your OpenAI API credits are exhausted. Add credits in your OpenAI account."
		return "OpenAI is limiting requests (429). Wait a moment and try again."
	if ecode == "model_not_found" or code == 404:
		return "This API key can't use the model '%s'. Pick another model in Settings." % str(Settings.get_val("model", ""))
	if code == 403:
		return "This API key can't use the order model. Check model access in your OpenAI project."
	if code == 400:
		return "OpenAI rejected the request (400). Try a different model in Settings."
	if code >= 500:
		return "OpenAI is temporarily unavailable. Try again in a moment."
	return "OpenAI rejected the order request (%d)." % code
