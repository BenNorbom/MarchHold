extends Node
## Terra: sends free-text orders to the OpenAI Responses API with a strict JSON
## schema and returns {kind, reply, steps}. The model only proposes; the
## simulation validates every step.

const Schema = preload("res://scripts/orders/schema.gd")
const URL := "https://api.openai.com/v1/responses"

signal answered(result: Dictionary)

var http: HTTPRequest
var busy := false
var requests := 0


func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 30.0
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(_on_done)


func available() -> bool:
	return Settings.has_key()


func remaining() -> int:
	return int(Settings.get_val("request_limit", 120)) - requests


func _reasoning_for(model: String):
	var mm := model.to_lower()
	if mm.begins_with("gpt-4") or mm.begins_with("o1") or mm.begins_with("gpt-3"):
		return null
	if mm.begins_with("gpt-5-") or mm == "gpt-5" or mm.begins_with("o3") or mm.begins_with("o4"):
		return {"effort": "minimal"}
	return {"effort": "none"}


func ask(facts: Dictionary, message: String, history: Array, pending: Array) -> void:
	if busy:
		answered.emit({"ok": false, "error": "Terra is still thinking about your last order."})
		return
	if not available():
		answered.emit({"ok": false, "error": "Terra isn't set up. Add an OpenAI API key in Settings to give orders in your own words."})
		return
	if remaining() <= 0:
		answered.emit({"ok": false, "error": "Terra has answered the most requests allowed this match. Simple orders and slash commands still work."})
		return
	var model := str(Settings.get_val("model", Settings.DEFAULT_MODEL))
	var input := {"facts": facts, "history": history, "pending_plan": pending, "message": message}
	var schema := Schema.plan_schema()
	var body := {
		"model": model,
		"store": false,
		"max_output_tokens": 1200,
		"instructions": Schema.instructions(),
		"input": JSON.stringify(input),
		"text": {"format": {"type": "json_schema", "name": "village", "strict": true, "schema": schema}},
	}
	var reasoning = _reasoning_for(model)
	if reasoning != null:
		body["reasoning"] = reasoning
	var headers := PackedStringArray(["Authorization: Bearer " + Settings.api_key, "Content-Type: application/json"])
	busy = true
	requests += 1
	var err := http.request(URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		busy = false
		answered.emit({"ok": false, "error": "Could not reach OpenAI. Check your connection and try again."})


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if result == HTTPRequest.RESULT_TIMEOUT:
		answered.emit({"ok": false, "error": "OpenAI took too long to respond. Try again."})
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		answered.emit({"ok": false, "error": "Could not reach OpenAI. Check your connection and try again."})
		return
	var text := body.get_string_from_utf8()
	var data = JSON.parse_string(text)
	if code != 200:
		answered.emit({"ok": false, "error": _error_text(code, data)})
		return
	if not (data is Dictionary):
		answered.emit({"ok": false, "error": "Terra did not return a readable answer. Try rephrasing your order."})
		return
	var out := ""
	for item in data.get("output", []):
		if item is Dictionary:
			for c in item.get("content", []):
				if c is Dictionary and c.get("type", "") == "output_text":
					out = str(c.get("text", ""))
	var parsed = JSON.parse_string(out)
	if not (parsed is Dictionary) or not parsed.has("kind"):
		answered.emit({"ok": false, "error": "Terra did not return a readable answer. Try rephrasing your order."})
		return
	answered.emit({"ok": true, "data": parsed})


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
