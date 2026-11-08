class_name CharacterTab
extends HBoxContainer
# Customize: boy/girl body, your own face photo, owned skins and outfits.

var preview: PreviewBox
var look := {}
var skin_list: ItemList
var outfit_list: ItemList
var msg: Label
var file_dialog: FileDialog
var body_male_btn: Button
var body_female_btn: Button


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	look = Api.current_look()

	var left := UI.panel()
	add_child(left)
	preview = PreviewBox.new()
	left.add_child(preview)

	var right := UI.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var v := UI.vbox(10)
	right.add_child(v)
	v.add_child(UI.label("شخصيتك", 28, UI.ACCENT))

	var body_row := UI.hbox(8)
	body_row.add_child(UI.label("الجسم:", 20))
	body_male_btn = UI.button("ولد", func(): _set_body("male"))
	body_female_btn = UI.button("بنت", func(): _set_body("female"))
	body_row.add_child(body_male_btn)
	body_row.add_child(body_female_btn)
	v.add_child(body_row)

	var face_row := UI.hbox(8)
	face_row.add_child(UI.label("الوش:", 20))
	face_row.add_child(UI.button("اختار صورتك", _pick_face, true))
	face_row.add_child(UI.button("شيل الصورة", _clear_face))
	v.add_child(face_row)

	v.add_child(UI.label("السكنات (اللي معاك)", 20))
	skin_list = ItemList.new()
	skin_list.custom_minimum_size = Vector2(0, 150)
	skin_list.item_selected.connect(_on_skin)
	v.add_child(skin_list)

	v.add_child(UI.label("اللبسات (اللي معاك)", 20))
	outfit_list = ItemList.new()
	outfit_list.custom_minimum_size = Vector2(0, 150)
	outfit_list.item_selected.connect(_on_outfit)
	v.add_child(outfit_list)

	var save_btn := UI.button("حفظ الشخصية", _save, true)
	v.add_child(save_btn)
	msg = UI.label("", 18, Color("9aa6c4"))
	v.add_child(msg)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; صور"])
	file_dialog.title = "اختار صورة وشك"
	file_dialog.file_selected.connect(_on_face_file)
	add_child(file_dialog)

	Api.user_updated.connect(_fill_lists)
	_fill_lists()
	_update_preview()


func _fill_lists() -> void:
	skin_list.clear()
	outfit_list.clear()
	for id in Catalog.SKINS:
		if Api.owned(id):
			var i := skin_list.add_item(Catalog.SKINS[id].name)
			skin_list.set_item_metadata(i, id)
			if id == look.skin:
				skin_list.select(i)
	for id in Catalog.OUTFITS:
		if Api.owned(id):
			var i2 := outfit_list.add_item(Catalog.OUTFITS[id].name)
			outfit_list.set_item_metadata(i2, id)
			if id == look.outfit:
				outfit_list.select(i2)
	_refresh_body_buttons()


func _refresh_body_buttons() -> void:
	body_male_btn.disabled = look.body == "male"
	body_female_btn.disabled = look.body == "female"


func _update_preview() -> void:
	preview.show_look(look, str(Api.user.get("display_name", "")))


func _set_body(b: String) -> void:
	look.body = b
	_refresh_body_buttons()
	_update_preview()


func _on_skin(i: int) -> void:
	look.skin = skin_list.get_item_metadata(i)
	_update_preview()


func _on_outfit(i: int) -> void:
	look.outfit = outfit_list.get_item_metadata(i)
	_update_preview()


func _pick_face() -> void:
	file_dialog.popup_centered_ratio(0.7)


func _clear_face() -> void:
	look.face_b64 = ""
	_update_preview()


func _on_face_file(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		msg.text = "مقدرتش أفتح الصورة"
		return
	var s := mini(img.get_width(), img.get_height())
	var sq := img.get_region(Rect2i((img.get_width() - s) / 2, (img.get_height() - s) / 2, s, s))
	sq.convert(Image.FORMAT_RGB8)
	sq.resize(192, 192, Image.INTERPOLATE_LANCZOS)
	look.face_b64 = Marshalls.raw_to_base64(sq.save_jpg_to_buffer(0.88))
	msg.text = "الصورة اتحطت على وشك. اضغط حفظ."
	_update_preview()


func _save() -> void:
	msg.text = "بحفظ..."
	var res := await Api.call_api("save_look", {
		"body": look.body,
		"face_b64": look.face_b64,
		"equipped": {"skin": look.skin, "outfit": look.outfit},
	})
	msg.text = str(res.error) if res.has("error") else "اتحفظت ✔"
