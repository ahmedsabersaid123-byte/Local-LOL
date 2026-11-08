class_name FriendsTab
extends HBoxContainer
# Search players by username, add friends, see who is online / in a room.

var search_edit: LineEdit
var results_box: VBoxContainer
var friends_box: VBoxContainer
var msg: Label
var timer: Timer


func _ready() -> void:
	add_theme_constant_override("separation", 16)

	var left := UI.panel()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(left)
	var lv := UI.vbox(10)
	left.add_child(lv)
	lv.add_child(UI.label("دوّر على صاحبك باليوزر", 26, UI.ACCENT))
	var row := UI.hbox(8)
	search_edit = UI.line_edit("اكتب جزء من اليوزر")
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_edit.text_submitted.connect(func(_t): _search())
	row.add_child(search_edit)
	row.add_child(UI.button("بحث", _search, true))
	lv.add_child(row)
	msg = UI.label("", 18, Color("9aa6c4"))
	lv.add_child(msg)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(sc)
	results_box = UI.vbox(8)
	results_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(results_box)

	var right := UI.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var rv := UI.vbox(10)
	right.add_child(rv)
	rv.add_child(UI.label("أصحابي", 26, UI.ACCENT))
	var sc2 := ScrollContainer.new()
	sc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(sc2)
	friends_box = UI.vbox(8)
	friends_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.add_child(friends_box)

	timer = Timer.new()
	timer.wait_time = 8.0
	timer.autostart = true
	timer.timeout.connect(_load_friends)
	add_child(timer)
	_load_friends()


func _search() -> void:
	var q := search_edit.text.strip_edges().to_lower()
	UI.clear(results_box)
	if q.length() < 2:
		msg.text = "اكتب حرفين على الأقل"
		return
	msg.text = "بدور..."
	var res := await Api.call_api("search", {"query": q})
	if res.has("error"):
		msg.text = str(res.error)
		return
	var list: Array = res.results
	msg.text = "لقيت %d" % list.size() if list.size() > 0 else "مفيش حد بالاسم ده"
	for r in list:
		var h := UI.hbox(8)
		var l := UI.label("%s  (@%s)" % [r.display_name, r.username], 20)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		if r.online:
			h.add_child(UI.label("● أونلاين", 16, UI.GOOD))
		if r.is_friend:
			h.add_child(UI.label("صاحبك", 16, Color("9aa6c4")))
		else:
			var un: String = r.username
			h.add_child(UI.button("إضافة", func(): _add_friend(un)))
		results_box.add_child(h)


func _add_friend(un: String) -> void:
	var res := await Api.call_api("add_friend", {"username": un})
	msg.text = str(res.error) if res.has("error") else "اتضاف"
	_search()
	_load_friends()


func _load_friends() -> void:
	var res := await Api.call_api("friends")
	if res.has("error") or friends_box == null or not is_instance_valid(friends_box):
		return
	UI.clear(friends_box)
	var list: Array = res.friends
	if list.is_empty():
		friends_box.add_child(UI.label("لسه مفيش أصحاب - دوّر عليهم باليوزر", 18, Color("9aa6c4")))
	for f in list:
		var h := UI.hbox(8)
		var dot := UI.label("●", 18, UI.GOOD if f.online else Color("555d70"))
		h.add_child(dot)
		var l := UI.label("%s  (@%s)" % [f.display_name, f.username], 20)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		if str(f.room) != "":
			var host_u: String = f.room
			h.add_child(UI.button("ادخل غرفته", func(): _join_friend(host_u), true))
		friends_box.add_child(h)


func _join_friend(host_user: String) -> void:
	if Net.in_room:
		msg.text = "اخرج من غرفتك الأول"
		return
	var res := await Api.call_api("find_room", {"host": host_user})
	if res.has("error"):
		msg.text = str(res.error)
		return
	var room: Dictionary = res.room
	var addrs: Array = []
	var lan := str(room.get("lan_ip", ""))
	var mine := PlayTab.local_ip()
	if lan != "" and mine != "" and lan.get_slice(".", 0) == mine.get_slice(".", 0) \
			and lan.get_slice(".", 1) == mine.get_slice(".", 1) and lan.get_slice(".", 2) == mine.get_slice(".", 2):
		addrs.append(lan)
	if str(room.get("ip", "")) != "":
		addrs.append(str(room.ip))
	if lan != "" and not addrs.has(lan):
		addrs.append(lan)
	Net.join_game(addrs, int(room.get("port", Net.PORT)))
	msg.text = "بتدخل غرفة %s..." % host_user
