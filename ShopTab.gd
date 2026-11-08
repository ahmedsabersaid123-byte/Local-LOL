class_name ShopTab
extends HBoxContainer
# Shop: preview any skin/outfit on your character, buy with coins, equip.

var preview: PreviewBox
var list: ItemList
var info: Label
var action_btn: Button
var msg: Label
var coins_lbl: Label
var selected_id := ""
var ids: Array = []


func _ready() -> void:
	add_theme_constant_override("separation", 16)

	var left := UI.panel()
	add_child(left)
	preview = PreviewBox.new()
	left.add_child(preview)

	var right := UI.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var v := UI.vbox(10)
	right.add_child(v)
	v.add_child(UI.label("المتجر", 28, UI.ACCENT))
	coins_lbl = UI.label("", 22, Color("ffd24a"))
	v.add_child(coins_lbl)

	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(_on_select)
	v.add_child(list)

	info = UI.label("", 20)
	v.add_child(info)
	action_btn = UI.button("", _action, true)
	action_btn.disabled = true
	v.add_child(action_btn)
	msg = UI.label("", 18, Color("9aa6c4"))
	v.add_child(msg)

	Api.user_updated.connect(_refresh)
	_refresh()
	preview.show_look(Api.current_look(), str(Api.user.get("display_name", "")))


func _refresh() -> void:
	coins_lbl.text = "فلوسك: 🪙 %d" % int(Api.user.get("coins", 0))
	list.clear()
	ids.clear()
	for id in Catalog.SKINS:
		if id != "skin_default":
			_add_row(id, "سكن")
	for id in Catalog.OUTFITS:
		if id != "outfit_default":
			_add_row(id, "لبس")
	if selected_id != "":
		_update_action()


func _add_row(id: String, kind: String) -> void:
	var tag := ""
	if Api.owned(id):
		tag = "  ✔ معاك" + ("  (لابسه)" if Api.equipped("skin") == id or Api.equipped("outfit") == id else "")
	else:
		tag = "  🪙 %d" % Catalog.item_price(id)
	list.add_item("%s: %s%s" % [kind, Catalog.item_name(id), tag])
	ids.append(id)
	if id == selected_id:
		list.select(ids.size() - 1)


func _on_select(i: int) -> void:
	selected_id = ids[i]
	var look := Api.current_look()
	if Catalog.SKINS.has(selected_id):
		look.skin = selected_id
	else:
		look.outfit = selected_id
	preview.show_look(look, str(Api.user.get("display_name", "")))
	_update_action()


func _update_action() -> void:
	action_btn.disabled = false
	var price := Catalog.item_price(selected_id)
	info.text = Catalog.item_name(selected_id)
	if Api.owned(selected_id):
		var slot := "skin" if Catalog.SKINS.has(selected_id) else "outfit"
		if Api.equipped(slot) == selected_id:
			action_btn.text = "لابسه دلوقتي"
			action_btn.disabled = true
		else:
			action_btn.text = "البسه"
	else:
		action_btn.text = "اشتري بـ %d" % price
		action_btn.disabled = int(Api.user.get("coins", 0)) < price


func _action() -> void:
	if selected_id == "":
		return
	if not Api.owned(selected_id):
		var res := await Api.call_api("buy", {"item": selected_id})
		if res.has("error"):
			msg.text = str(res.error)
			return
		msg.text = "اشتريت %s ✔" % Catalog.item_name(selected_id)
	var slot := "skin" if Catalog.SKINS.has(selected_id) else "outfit"
	var eq := {"skin": Api.equipped("skin"), "outfit": Api.equipped("outfit")}
	eq[slot] = selected_id
	var res2 := await Api.call_api("save_look", {
		"body": Api.user.get("body", "male"),
		"face_b64": Api.user.get("face_b64", ""),
		"equipped": eq,
	})
	if res2.has("error"):
		msg.text = str(res2.error)
