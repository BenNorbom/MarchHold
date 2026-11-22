extends Node
## Player settings (user://settings.cfg) and the OpenAI key, which is stored
## encrypted with a key derived from this machine (user://terra.cfg).

signal changed

const PATH := "user://settings.cfg"
const KEY_PATH := "user://terra.cfg"
const DEFAULT_MODEL := "gpt-6.1-terra"
const CHATGPT_PLAN := 0
const API_KEY := 1
const TERRA_OFF := 2

var data := {
	"quality": 1,           # 0 low, 1 medium, 2 high
	"sensitivity": 0.11,
	"fov": 75.0,
	"volume": 0.8,
	"invert_y": false,
	"fullscreen": false,
	"model": DEFAULT_MODEL,
	"chatgpt_model": "",
	"terra_provider": -1,
	"chatgpt_usage_seen": false,
	"intro_seen": false,
	"matches_played": 0,
	"tutorial_done": false,
	"hints": true,
	"resource_labels": true, # names over stone and ore, and on the map
	"difficulty": 1,
	"mode": "standard",
	"map": "medium",
	"opponents": 1,
	"strategy": "random",
	"calm_start": false,
	"request_limit": 120,
}
var api_key := ""


func _ready() -> void:
	load_all()
	apply()


func _secret() -> String:
	return "marchhold-terra-" + OS.get_unique_id()


func load_all() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in data:
			data[k] = cfg.get_value("settings", k, data[k])
	elif DisplayServer.get_name() != "headless":
		# First run: integrated graphics start on Low.
		var gpu := RenderingServer.get_video_adapter_name().to_lower()
		if gpu.contains("intel") or gpu.contains("uhd") or gpu.contains("iris") or gpu.contains("radeon(tm) graphics") or gpu.contains("vega"):
			data["quality"] = 0
	var kc := ConfigFile.new()
	if kc.load_encrypted_pass(KEY_PATH, _secret()) == OK:
		api_key = str(kc.get_value("terra", "key", ""))
	if int(data["terra_provider"]) not in [CHATGPT_PLAN, API_KEY, TERRA_OFF]:
		data["terra_provider"] = API_KEY if has_key() else CHATGPT_PLAN


func save_all() -> void:
	var cfg := ConfigFile.new()
	for k in data:
		cfg.set_value("settings", k, data[k])
	cfg.save(PATH)
	changed.emit()


func set_api_key(key: String) -> void:
	api_key = key.strip_edges()
	var kc := ConfigFile.new()
	kc.set_value("terra", "key", api_key)
	kc.save_encrypted_pass(KEY_PATH, _secret())
	changed.emit()


func get_val(k: String, default = null):
	return data.get(k, default)


func set_val(k: String, v) -> void:
	data[k] = v
	save_all()
	apply()


func apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(0.0001, float(data["volume"]))))
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if data["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want and not (want == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
			DisplayServer.window_set_mode(want)


func has_key() -> bool:
	return api_key.length() > 20


func terra_available() -> bool:
	match int(data["terra_provider"]):
		CHATGPT_PLAN: return ChatGPT.can_use_plan()
		API_KEY: return has_key()
	return false
