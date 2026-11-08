extends Control
# Main hub: top bar + tabs (play, friends, character, shop, challenges).

var tabs: TabContainer
var name_lbl: Label
var coins_lbl: Label
var level_lbl: Label
var hb_timer: Timer


func _ready() -> void:
	theme = UI.make_theme()
	Gfx.apply_viewport(get_viewport())
	if Api.token == "":
		get_tree().change_scene_to_file("res://scenes/Login.tscn")
		return

	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)

	var root := UI.vbox(12)
	margin.add_child(root)
	root.add_child(_top_bar())

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	var tab_defs := [
		["اللعب", PlayTab.new()],
		["الأصدقاء", FriendsTab.new()],
		["الشخصية", CharacterTab.new()],
		["المتجر", ShopTab.new()],
		["المستويات", ChallengesTab.new()],
	]
	for i in tab_defs.size():
		tabs.add_child(tab_defs[i][1])
		tabs.set_tab_title(i, tab_defs[i][0])

	Api.user_updated.connect(_refresh_bar)
	_refresh_bar()

	hb_timer = Timer.new()
	hb_timer.wait_time = 10.0
	hb_timer.autostart = true
	hb_timer.timeout.connect(_heartbeat)
	add_child(hb_timer)
	_heartbeat()
	Api.call_api("me")  # refresh coins/items


func _top_bar() -> Control:
	var p := UI.panel()
	var h := UI.hbox(18)
	p.add_child(h)
	h.add_child(UI.label("LoCal LoL", 30, UI.ACCENT))
	name_lbl = UI.label("", 22)
	level_lbl = UI.label("", 20, Color("9aa6c4"))
	coins_lbl = UI.label("", 22, Color("ffd24a"))
	h.add_child(name_lbl)
	h.add_child(level_lbl)
	h.add_child(coins_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	h.add_child(UI.label("الجرافيك", 18, Color("9aa6c4")))
	var q := OptionButton.new()
	for n in Gfx.QUALITY_NAMES:
		q.add_item(n)
	q.selected = Gfx.quality
	q.item_selected.connect(func(i):
		Gfx.quality = i
		Gfx.save_prefs()
		Gfx.apply_viewport(get_viewport()))
	h.add_child(q)

	h.add_child(UI.label("الفريمات", 18, Color("9aa6c4")))
	var f := OptionButton.new()
	for n in Gfx.FPS_OPTIONS:
		f.add_item("بدون حد" if n == 0 else str(n))
	f.selected = maxi(Gfx.FPS_OPTIONS.find(Gfx.fps_cap), 0)
	f.item_selected.connect(func(i):
		Gfx.fps_cap = Gfx.FPS_OPTIONS[i]
		Gfx.save_prefs()
		Gfx.apply_global())
	h.add_child(f)

	h.add_child(UI.button("خروج", _logout))
	return p


func _refresh_bar() -> void:
	if name_lbl == null:
		return
	name_lbl.text = str(Api.user.get("display_name", ""))
	level_lbl.text = "مستوى %d" % int(Api.user.get("level", 1))
	coins_lbl.text = "🪙 %d" % int(Api.user.get("coins", 0))


func _heartbeat() -> void:
	if Api.token == "":
		return
	var count := 0
	if Net.in_room:
		count = Net.players.size()
	var host_room := Net.is_host() and not Net.solo
	if host_room:
		await Api.call_api("host_room", {"lan_ip": PlayTab.local_ip(), "port": Net.PORT, "max": Net.MAX_PLAYERS})
	await Api.call_api("heartbeat", {"players": count})


func _logout() -> void:
	if Net.in_room:
		Net.leave()
	await Api.call_api("close_room")
	Api.token = ""
	Api.user = {}
	get_tree().change_scene_to_file("res://scenes/Login.tscn")
