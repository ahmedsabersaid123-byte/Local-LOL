class_name PlayTab
extends HBoxContainer
# Host a room, join a friend's room by username (or direct IP), split teams any way you like.

var status_lbl: Label
var join_user: LineEdit
var join_ip: LineEdit
var lobby_panel: PanelContainer
var lobby_box: VBoxContainer
var bot_level_opt: OptionButton
var host_btn: Button


static func local_ip() -> String:
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and (a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172.")):
			return a
	return ""


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	_build_left()
	_build_right()
	Net.lobby_changed.connect(_render_lobby)
	Net.status.connect(_on_status)
	Net.left_room.connect(_render_lobby)
	_render_lobby()


func _build_left() -> void:
	var p := UI.panel()
	p.custom_minimum_size = Vector2(430, 0)
	add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)

	v.add_child(UI.label("اعمل غرفة", 26, UI.ACCENT))
	host_btn = UI.button("ابدأ غرفة جديدة", _host, true)
	v.add_child(host_btn)

	v.add_child(HSeparator.new())
	v.add_child(UI.label("ادخل غرفة صاحبك (باليوزر)", 22))
	join_user = UI.line_edit("يوزر صاحب الغرفة")
	v.add_child(join_user)
	v.add_child(UI.button("ادخل", _join_by_user))

	v.add_child(HSeparator.new())
	v.add_child(UI.label("أو بالـ IP مباشرة (نفس الشبكة)", 22))
	join_ip = UI.line_edit("مثال 192.168.1.20")
	v.add_child(join_ip)
	v.add_child(UI.button("ادخل بالـ IP", _join_by_ip))

	status_lbl = UI.label("", 18, Color("9aa6c4"))
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status_lbl)


func _build_right() -> void:
	lobby_panel = UI.panel()
	lobby_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(lobby_panel)
	lobby_box = UI.vbox(12)
	lobby_panel.add_child(lobby_box)


func _on_status(msg: String) -> void:
	if status_lbl:
		status_lbl.text = msg


# ---------------- actions ----------------
func _host() -> void:
	if Net.in_room:
		status_lbl.text = "إنت جوه غرفة بالفعل"
		return
	var err := Net.host_game()
	if err != OK:
		status_lbl.text = "مقدرتش أفتح الغرفة (البورت %d مشغول؟)" % Net.PORT
		return
	var res := await Api.call_api("host_room", {"lan_ip": local_ip(), "port": Net.PORT, "max": Net.MAX_PLAYERS})
	var extra := ""
	if res.has("error"):
		extra = "\n(مش متسجلة على السيرفر: %s)" % res.error
	status_lbl.text = "الغرفة شغالة. صحابك يدخلوا بيوزرك: %s\nأو بالـ IP: %s%s" % [Api.user.get("username", ""), local_ip(), extra]


func _join_by_user() -> void:
	if Net.in_room:
		status_lbl.text = "اخرج من الغرفة الحالية الأول"
		return
	var u := join_user.text.strip_edges().to_lower()
	if u == "":
		return
	status_lbl.text = "بدور على الغرفة..."
	var res := await Api.call_api("find_room", {"host": u})
	if res.has("error"):
		status_lbl.text = str(res.error)
		return
	var room: Dictionary = res.room
	var addrs: Array = []
	var lan := str(room.get("lan_ip", ""))
	var mine := local_ip()
	if lan != "" and mine != "" and lan.get_slice(".", 0) == mine.get_slice(".", 0) \
			and lan.get_slice(".", 1) == mine.get_slice(".", 1) and lan.get_slice(".", 2) == mine.get_slice(".", 2):
		addrs.append(lan)
	if str(room.get("ip", "")) != "":
		addrs.append(str(room.ip))
	if lan != "" and not addrs.has(lan):
		addrs.append(lan)
	Net.join_game(addrs, int(room.get("port", Net.PORT)))


func _join_by_ip() -> void:
	if Net.in_room:
		status_lbl.text = "اخرج من الغرفة الحالية الأول"
		return
	var ip := join_ip.text.strip_edges()
	if ip != "":
		Net.join_game([ip], Net.PORT)


# ---------------- lobby view ----------------
func _render_lobby() -> void:
	if lobby_box == null:
		return
	UI.clear(lobby_box)
	if not Net.in_room:
		lobby_box.add_child(UI.label("مفيش غرفة دلوقتي.\nاعمل غرفة أو ادخل غرفة صاحبك.", 22, Color("9aa6c4")))
		return

	var host := Net.is_host()
	lobby_box.add_child(UI.label("الغرفة", 28, UI.ACCENT))

	# mode row
	var mode_row := UI.hbox(10)
	mode_row.add_child(UI.label("نوع اللعب:", 20))
	if host:
		var mo := OptionButton.new()
		mo.add_item("فريق ضد فريق")
		mo.add_item("الكل ضد البوس")
		mo.selected = 0 if Net.mode == "tdm" else 1
		mo.item_selected.connect(func(i): Net.set_mode("tdm" if i == 0 else "boss"))
		mode_row.add_child(mo)
		if Net.mode == "boss":
			var bo := OptionButton.new()
			for i in Catalog.BOSS_LEVELS.size():
				bo.add_item(Catalog.BOSS_LEVELS[i].name)
			bo.selected = Net.boss_level - 1
			bo.item_selected.connect(func(i): Net.set_boss_level(i + 1))
			mode_row.add_child(bo)
	else:
		var txt := "فريق ضد فريق" if Net.mode == "tdm" else "الكل ضد البوس (%s)" % Catalog.BOSS_LEVELS[Net.boss_level - 1].name
		mode_row.add_child(UI.label(txt, 20, Color("ffd24a")))
	lobby_box.add_child(mode_row)

	# teams
	var teams := UI.hbox(14)
	teams.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobby_box.add_child(teams)
	for t in 2:
		teams.add_child(_team_column(t, host))

	# host controls
	if host:
		var bots_row := UI.hbox(8)
		bots_row.add_child(UI.label("بوت:", 18))
		bot_level_opt = OptionButton.new()
		for i in Catalog.BOT_LEVELS.size():
			bot_level_opt.add_item("Lv%d %s" % [i + 1, Catalog.BOT_LEVELS[i].name])
		bot_level_opt.selected = 1
		bots_row.add_child(bot_level_opt)
		bots_row.add_child(UI.button("+ للأزرق", func(): Net.add_bot(0, bot_level_opt.selected + 1)))
		bots_row.add_child(UI.button("+ للأحمر", func(): Net.add_bot(1, bot_level_opt.selected + 1)))
		lobby_box.add_child(bots_row)

	var bottom := UI.hbox(10)
	if host:
		var start := UI.button("ابدأ اللعب", func(): Net.start_match(), true)
		start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(start)
	else:
		var wait := UI.label("مستني صاحب الغرفة يبدأ...", 20, Color("9aa6c4"))
		wait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(wait)
	bottom.add_child(UI.button("خروج من الغرفة", _leave))
	lobby_box.add_child(bottom)


func _leave() -> void:
	var was_host := Net.is_host() and not Net.solo
	Net.leave()
	if was_host:
		await Api.call_api("close_room")
	if status_lbl:
		status_lbl.text = ""


func _team_column(t: int, host: bool) -> Control:
	var col := PanelContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Catalog.TEAM_COLORS[t].darkened(0.75)
	sb.border_color = Catalog.TEAM_COLORS[t]
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(12)
	col.add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(8)
	col.add_child(v)
	v.add_child(UI.label("%s (%d)" % [Catalog.TEAM_NAMES[t], Net.team_count(t)], 22, Catalog.TEAM_COLORS[t].lightened(0.3)))

	var my_id := multiplayer.get_unique_id()
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		var pl: Dictionary = Net.players[id]
		if int(pl.team) != t:
			continue
		var row := UI.hbox(6)
		var nm := UI.label(str(pl.name) + ("  (إنت)" if id == my_id else ""), 20)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		if host or id == my_id:
			var pid: int = id
			row.add_child(UI.button("↔", func(): Net.move_player(pid, 1 - t)))
		v.add_child(row)
	for i in Net.bots.size():
		var b: Dictionary = Net.bots[i]
		if int(b.team) != t:
			continue
		var row2 := UI.hbox(6)
		var lbl := UI.label("%s  Lv%d" % [b.name, int(b.level)], 18, Color("b8c2dd"))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(lbl)
		if host:
			var bi: int = i
			row2.add_child(UI.button("↔", func(): Net.set_bot_team(bi, 1 - t)))
			row2.add_child(UI.button("✕", func(): Net.remove_bot(bi)))
		v.add_child(row2)
	return col
