extends Node
# Talks to backend/server.js (accounts, friends, shop, rooms).

signal user_updated

const CFG := "user://local_lol.cfg"

var base_url := "http://127.0.0.1:8080"
var token := ""
var user := {}
var last_username := ""


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		base_url = cf.get_value("net", "server", base_url)
		last_username = cf.get_value("net", "username", "")


func save_prefs() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("net", "server", base_url)
	cf.set_value("net", "username", last_username)
	cf.save(CFG)


func call_api(endpoint: String, data: Dictionary = {}) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 10.0
	add_child(req)
	data["token"] = token
	var err := req.request(base_url.rstrip("/") + "/" + endpoint, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(data))
	if err != OK:
		req.queue_free()
		return {"error": "مفيش اتصال بالسيرفر (تأكد من العنوان)"}
	var res: Array = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "السيرفر مش بيرد - تأكد إنه شغال والعنوان صح"}
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"error": "رد غير صالح من السيرفر"}
	if parsed.has("user"):
		user = parsed["user"]
		user_updated.emit()
	if parsed.has("token"):
		token = parsed["token"]
	return parsed


func owned(id: String) -> bool:
	return (user.get("owned", []) as Array).has(id)


func equipped(slot: String) -> String:
	return str((user.get("equipped", {}) as Dictionary).get(slot, ""))


func current_look() -> Dictionary:
	return {
		"body": user.get("body", "male"),
		"skin": equipped("skin"),
		"outfit": equipped("outfit"),
		"face_b64": user.get("face_b64", ""),
	}
