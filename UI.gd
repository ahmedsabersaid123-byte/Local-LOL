class_name UI
extends RefCounted
# Small helpers for building the menu UI from code.

const BG := Color("0d111c")
const PANEL := Color("171d2e")
const ACCENT := Color("ff9a1f")
const GOOD := Color("3ddc84")
const BAD := Color("ff5252")


static func _sb(color: Color, radius := 10, margin := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.6
	s.content_margin_bottom = margin * 0.6
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_stylebox("normal", "Button", _sb(Color("26304a")))
	t.set_stylebox("hover", "Button", _sb(Color("34416a")))
	t.set_stylebox("pressed", "Button", _sb(ACCENT.darkened(0.2)))
	t.set_stylebox("disabled", "Button", _sb(Color("1a2033")))
	t.set_stylebox("focus", "Button", _sb(Color(0, 0, 0, 0)))
	t.set_stylebox("normal", "LineEdit", _sb(Color("0f1424")))
	t.set_stylebox("focus", "LineEdit", _sb(Color("141b30")))
	t.set_stylebox("panel", "PanelContainer", _sb(PANEL, 14, 14))
	t.set_stylebox("panel", "TabContainer", _sb(Color(0, 0, 0, 0)))
	t.set_stylebox("tab_selected", "TabContainer", _sb(ACCENT.darkened(0.25)))
	t.set_stylebox("tab_unselected", "TabContainer", _sb(Color("1a2033")))
	t.set_stylebox("tab_hovered", "TabContainer", _sb(Color("2a3556")))
	t.set_stylebox("panel", "ItemList", _sb(Color("0f1424")))
	t.set_stylebox("normal", "OptionButton", _sb(Color("26304a")))
	t.set_stylebox("hover", "OptionButton", _sb(Color("34416a")))
	t.set_stylebox("normal", "CheckButton", _sb(Color(0, 0, 0, 0)))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	return t


static func label(text: String, size := 20, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.text_direction = Control.TEXT_DIRECTION_AUTO
	return l


static func button(text: String, cb: Callable, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	if accent:
		b.add_theme_stylebox_override("normal", _sb(ACCENT.darkened(0.15)))
		b.add_theme_stylebox_override("hover", _sb(ACCENT))
		b.add_theme_color_override("font_color", Color.BLACK)
		b.add_theme_color_override("font_hover_color", Color.BLACK)
	b.pressed.connect(cb)
	return b


static func line_edit(placeholder: String, secret := false, text := "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.text = text
	e.custom_minimum_size = Vector2(0, 46)
	return e


static func panel() -> PanelContainer:
	return PanelContainer.new()


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()
