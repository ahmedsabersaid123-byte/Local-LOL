class_name ChallengesTab
extends VBoxContainer
# Bot levels + boss levels, and solo practice.

var bot_opt: OptionButton
var boss_opt: OptionButton
var msg: Label


func _ready() -> void:
	add_theme_constant_override("separation", 14)

	var tables := UI.hbox(16)
	tables.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tables)
	tables.add_child(_table("مستويات البوتات", Catalog.BOT_LEVELS, false))
	tables.add_child(_table("مستويات البوس", Catalog.BOSS_LEVELS, true))

	var p := UI.panel()
	add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	v.add_child(UI.label("تدريب فردي (من غير ما تفتح غرفة)", 24, UI.ACCENT))

	var row := UI.hbox(10)
	row.add_child(UI.label("مستوى البوتات:", 20))
	bot_opt = OptionButton.new()
	for i in Catalog.BOT_LEVELS.size():
		bot_opt.add_item("Lv%d %s" % [i + 1, Catalog.BOT_LEVELS[i].name])
	bot_opt.selected = 1
	row.add_child(bot_opt)
	row.add_child(UI.button("ابدأ: أنا وبوتين ضد 3 بوتات", _solo_tdm, true))
	v.add_child(row)

	var row2 := UI.hbox(10)
	row2.add_child(UI.label("مستوى البوس:", 20))
	boss_opt = OptionButton.new()
	for i in Catalog.BOSS_LEVELS.size():
		boss_opt.add_item(Catalog.BOSS_LEVELS[i].name)
	row2.add_child(boss_opt)
	row2.add_child(UI.button("ابدأ: أنا و3 بوتات ضد البوس", _solo_boss, true))
	v.add_child(row2)

	msg = UI.label("", 18, Color("9aa6c4"))
	v.add_child(msg)


func _table(title: String, levels: Array, boss: bool) -> Control:
	var p := UI.panel()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(8)
	p.add_child(v)
	v.add_child(UI.label(title, 24, UI.ACCENT))
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 8)
	v.add_child(g)
	for h in ["المستوى", "الصحة", "الضرر", "الدقة", "السرعة", "المكافأة"]:
		g.add_child(UI.label(h, 16, Color("9aa6c4")))
	for i in levels.size():
		var lv: Dictionary = levels[i]
		var acc := clampi(int(100.0 - float(lv.spread) * 8.0), 10, 99)
		g.add_child(UI.label("%d  %s" % [i + 1, lv.name], 18, Color("ffd24a") if boss else Color.WHITE))
		g.add_child(UI.label(str(int(lv.hp)), 18))
		g.add_child(UI.label(str(int(lv.dmg)), 18))
		g.add_child(UI.label("%d%%" % acc, 18))
		g.add_child(UI.label("%.1f" % float(lv.speed), 18))
		g.add_child(UI.label("🪙 %d" % int(lv.reward), 18, Color("ffd24a")))
	if boss:
		v.add_child(UI.label("البوس بيعمل ضربة أرضية قوية كل كام ثانية - اتفرقوا!", 16, Color("9aa6c4")))
	return p


func _solo_tdm() -> void:
	if Net.in_room:
		msg.text = "اخرج من الغرفة الحالية الأول"
		return
	var lv := bot_opt.selected + 1
	Net.host_solo()
	Net.mode = "tdm"
	for i in 2:
		Net.add_bot(0, lv)
	for i in 3:
		Net.add_bot(1, lv)
	Net.start_match()


func _solo_boss() -> void:
	if Net.in_room:
		msg.text = "اخرج من الغرفة الحالية الأول"
		return
	Net.host_solo()
	Net.mode = "boss"
	Net.boss_level = boss_opt.selected + 1
	for i in 3:
		Net.add_bot(0, 2)
	Net.start_match()
