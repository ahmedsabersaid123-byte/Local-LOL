extends Control
# Login / register screen: username + password + display name.

var server_edit: LineEdit
var user_edit: LineEdit
var pass_edit: LineEdit
var name_edit: LineEdit
var msg: Label
var busy := false


func _ready() -> void:
	theme = UI.make_theme()
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := UI.panel()
	card.custom_minimum_size = Vector2(520, 0)
	center.add_child(card)

	var v := UI.vbox(12)
	card.add_child(v)

	var title := UI.label("LoCal LoL", 56, UI.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UI.label("ساحة المعركة مع أصحابك", 20, Color("9aa6c4"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	server_edit = UI.line_edit("عنوان السيرفر مثال: http://192.168.1.5:8080", false, Api.base_url)
	user_edit = UI.line_edit("اليوزر (إنجليزي)", false, Api.last_username)
	pass_edit = UI.line_edit("كلمة السر", true)
	name_edit = UI.line_edit("الاسم داخل اللعبة (للحساب الجديد)")
	for e in [server_edit, user_edit, pass_edit, name_edit]:
		v.add_child(e)
	pass_edit.text_submitted.connect(func(_t): _do_login())

	var row := UI.hbox(10)
	var login_btn := UI.button("دخول", _do_login, true)
	login_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var reg_btn := UI.button("حساب جديد", _do_register)
	reg_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(login_btn)
	row.add_child(reg_btn)
	v.add_child(row)

	msg = UI.label("", 18, UI.BAD)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(msg)


func _set_busy(b: bool, text := "") -> void:
	busy = b
	msg.add_theme_color_override("font_color", Color("9aa6c4") if b else UI.BAD)
	msg.text = text


func _do_login() -> void:
	await _submit("login")


func _do_register() -> void:
	await _submit("register")


func _submit(endpoint: String) -> void:
	if busy:
		return
	Api.base_url = server_edit.text.strip_edges()
	Api.last_username = user_edit.text.strip_edges().to_lower()
	Api.token = ""
	_set_busy(true, "لحظة...")
	var res := await Api.call_api(endpoint, {
		"username": Api.last_username,
		"password": pass_edit.text,
		"display_name": name_edit.text.strip_edges(),
	})
	if res.has("error"):
		_set_busy(false, str(res.error))
		return
	Api.save_prefs()
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")
