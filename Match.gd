extends Node3D
# The 3D arena: world, spawning (players + bots + boss), damage/kill/respawn flow, HUD, match end.
# Host is authoritative for health, kills and the match result.

const KILL_LIMIT := 25
const TDM_TIME := 300.0
const BOSS_TIME := 420.0
const ARENA := 60.0

var fighters := {}            # node name -> Fighter
var fighters_root: Node3D
var local: Fighter
var input_enabled := true
var scores := [0, 0]
var time_left := TDM_TIME
var ended := false
var paused := false
var mode := "tdm"
var respawn_t := 0.0
var use_touch := OS.has_feature("mobile")
var touch: Control = null

var _nrm_tex: NoiseTexture2D
var _alb_tex: NoiseTexture2D
var _tracer_mat: StandardMaterial3D

# HUD
var top_lbl: Label
var hp_bar: ProgressBar
var hp_lbl: Label
var boss_bar: ProgressBar
var boss_lbl: Label
var feed_box: VBoxContainer
var hit_lbl: Label
var flash: ColorRect
var center_lbl: Label
var board_lbl: Label
var pause_panel: PanelContainer
var result_panel: PanelContainer
var result_lbl: Label


func _ready() -> void:
	mode = Net.mode
	time_left = TDM_TIME if mode == "tdm" else BOSS_TIME
	Gfx.apply_viewport(get_viewport())
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.85, 0.3)
	_tracer_mat.emission_enabled = true
	_tracer_mat.emission = Color(1.0, 0.8, 0.25)
	_tracer_mat.emission_energy_multiplier = 4.0
	_build_world()
	_spawn_all()
	_build_hud()
	if not use_touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	multiplayer.peer_disconnected.connect(_on_peer_left)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# =====================================================================
# World
# =====================================================================
func _pbr(color: Color, rough: float, metal := 0.0, tri_scale := 0.18) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.albedo_texture = _alb_tex
	m.normal_enabled = true
	m.normal_texture = _nrm_tex
	m.normal_scale = 1.2
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * tri_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _solid(pos: Vector3, size: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation_degrees = rot_deg
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	return body


func _build_world() -> void:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.035
	n.fractal_octaves = 5
	_nrm_tex = NoiseTexture2D.new()
	_nrm_tex.noise = n
	_nrm_tex.width = 1024
	_nrm_tex.height = 1024
	_nrm_tex.seamless = true
	_nrm_tex.as_normal_map = true
	_nrm_tex.bump_strength = 7.0
	var n2 := FastNoiseLite.new()
	n2.noise_type = FastNoiseLite.TYPE_CELLULAR
	n2.frequency = 0.02
	n2.fractal_octaves = 3
	_alb_tex = NoiseTexture2D.new()
	_alb_tex.noise = n2
	_alb_tex.width = 1024
	_alb_tex.height = 1024
	_alb_tex.seamless = true
	var g := Gradient.new()
	g.set_color(0, Color(0.62, 0.62, 0.62))
	g.set_color(1, Color(1, 1, 1))
	_alb_tex.color_ramp = g

	var we := WorldEnvironment.new()
	we.environment = Gfx.make_environment()
	add_child(we)
	add_child(Gfx.make_sun())

	var rp := ReflectionProbe.new()
	rp.size = Vector3(150, 40, 150)
	rp.position = Vector3(0, 12, 0)
	rp.update_mode = ReflectionProbe.UPDATE_ONCE
	rp.intensity = 1.0
	add_child(rp)

	var ground_mat := _pbr(Color("7b7f84"), 0.82, 0.0, 0.12)
	var wall_mat := _pbr(Color("5c6068"), 0.7, 0.2, 0.1)
	var concrete := _pbr(Color("a3a6a8"), 0.9, 0.0, 0.2)
	var metal := _pbr(Color("4a5568"), 0.38, 0.85, 0.25)
	var paint := _pbr(Color("d9731a"), 0.55, 0.1, 0.25)

	_solid(Vector3(0, -0.5, 0), Vector3(ARENA * 2.0, 1.0, ARENA * 2.0), ground_mat)
	var h := 9.0
	_solid(Vector3(0, h / 2.0 - 0.5, -ARENA - 1.0), Vector3(ARENA * 2.0 + 4.0, h, 2.0), wall_mat)
	_solid(Vector3(0, h / 2.0 - 0.5, ARENA + 1.0), Vector3(ARENA * 2.0 + 4.0, h, 2.0), wall_mat)
	_solid(Vector3(-ARENA - 1.0, h / 2.0 - 0.5, 0), Vector3(2.0, h, ARENA * 2.0), wall_mat)
	_solid(Vector3(ARENA + 1.0, h / 2.0 - 0.5, 0), Vector3(2.0, h, ARENA * 2.0), wall_mat)

	# central platform with two ramps
	_solid(Vector3(0, 0.75, 0), Vector3(14, 1.5, 14), concrete)
	_solid(Vector3(10.6, 0.72, 0), Vector3(8.0, 0.4, 12), metal, Vector3(0, 0, -11.0))
	_solid(Vector3(-10.6, 0.72, 0), Vector3(8.0, 0.4, 12), metal, Vector3(0, 0, 11.0))

	# seeded cover (same on every peer)
	var rng := RandomNumberGenerator.new()
	rng.seed = Net.match_seed
	var mats := [concrete, metal, paint]
	var placed: Array = []
	var tries := 0
	while placed.size() < 34 and tries < 300:
		tries += 1
		var size := Vector3(rng.randf_range(3.0, 9.0), rng.randf_range(1.6, 5.0), rng.randf_range(3.0, 9.0))
		var pos := Vector3(rng.randf_range(-50.0, 50.0), size.y / 2.0, rng.randf_range(-34.0, 34.0))
		if Vector2(pos.x, pos.z).length() < 15.0:
			continue
		var ok := true
		for p in placed:
			if absf(pos.x - p.x) < (size.x + p.w) / 2.0 + 3.0 and absf(pos.z - p.z) < (size.z + p.d) / 2.0 + 3.0:
				ok = false
				break
		if not ok:
			continue
		placed.append({"x": pos.x, "z": pos.z, "w": size.x, "d": size.z})
		_solid(pos, size, mats[rng.randi() % mats.size()], Vector3(0, rng.randf_range(-12.0, 12.0), 0))

	# pillars
	for i in 6:
		var px := rng.randf_range(-45.0, 45.0)
		var pz := rng.randf_range(-30.0, 30.0)
		if Vector2(px, pz).length() < 14.0:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.position = Vector3(px, 4.5, pz)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.5
		cm.bottom_radius = 1.7
		cm.height = 9.0
		cm.radial_segments = 40
		mi.mesh = cm
		mi.material_override = metal
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.6
		cyl.height = 9.0
		cs.shape = cyl
		body.add_child(cs)
		add_child(body)

	# team bases (glowing floor pads + lights)
	for t in 2:
		var z := -50.0 if t == 0 else 50.0
		var col: Color = Catalog.TEAM_COLORS[t]
		var em := StandardMaterial3D.new()
		em.albedo_color = col.darkened(0.5)
		em.emission_enabled = true
		em.emission = col
		em.emission_energy_multiplier = 1.6
		var pad := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(44, 0.06, 12)
		pad.mesh = pm
		pad.material_override = em
		pad.position = Vector3(0, 0.03, z)
		add_child(pad)
		for lx in [-18.0, 18.0]:
			var l := OmniLight3D.new()
			l.light_color = col
			l.light_energy = 2.5
			l.omni_range = 26.0
			l.position = Vector3(lx, 6.0, z)
			add_child(l)


# =====================================================================
# Spawning
# =====================================================================
func spawn_point(team: int, idx: int) -> Vector3:
	if team == 2:
		return Vector3(0, 0.3, 40)
	var z := -50.0 if team == 0 else 50.0
	var inward := 1.0 if team == 0 else -1.0
	var col := idx % 8
	var row := idx / 8
	return Vector3(-14.0 + col * 4.0, 0.3, z + inward * row * 3.0)


func _random_spawn(team: int) -> Vector3:
	var z := -50.0 if team == 0 else 50.0
	var inward := 3.0 if team == 0 else -3.0
	return Vector3(randf_range(-18.0, 18.0), 0.3, z + inward * randf_range(0.0, 2.0))


func _yaw_for(team: int) -> float:
	return PI if team == 0 else 0.0


func _spawn_all() -> void:
	fighters_root = Node3D.new()
	fighters_root.name = "Fighters"
	add_child(fighters_root)
	var idx := [0, 0, 0]

	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		var pl: Dictionary = Net.players[id]
		var team := 0 if mode == "boss" else int(pl.team)
		var f := Fighter.new()
		f.name = "p%d" % int(id)
		f.set_multiplayer_authority(int(id))
		f.position = spawn_point(team, idx[team])
		f.rotation.y = _yaw_for(team)
		idx[team] += 1
		fighters_root.add_child(f)
		f.setup(str(pl.name), team, pl.look, true, {"hp": 100.0}, false, self)
		fighters[str(f.name)] = f
		if int(id) == multiplayer.get_unique_id():
			local = f

	var skins: Array = ["skin_default", "skin_default", "skin_ice", "skin_neon"]
	var outfits: Array = Catalog.OUTFITS.keys()
	for i in Net.bots.size():
		var b: Dictionary = Net.bots[i]
		var team2 := 0 if mode == "boss" else int(b.team)
		var r := RandomNumberGenerator.new()
		r.seed = Net.match_seed + i * 7919
		var blook := {
			"body": "female" if r.randf() < 0.5 else "male",
			"skin": skins[r.randi() % skins.size()],
			"outfit": outfits[r.randi() % outfits.size()],
			"face_b64": "",
		}
		var bf := Fighter.new()
		bf.name = "b%d" % i
		bf.position = spawn_point(team2, idx[team2])
		bf.rotation.y = _yaw_for(team2)
		idx[team2] += 1
		fighters_root.add_child(bf)
		var lv := clampi(int(b.level), 1, Catalog.BOT_LEVELS.size())
		bf.setup(str(b.name), team2, blook, false, Catalog.BOT_LEVELS[lv - 1], false, self)
		fighters[str(bf.name)] = bf

	if mode == "boss":
		var bl := clampi(Net.boss_level, 1, Catalog.BOSS_LEVELS.size())
		var bc: Dictionary = Catalog.BOSS_LEVELS[bl - 1]
		var boss := Fighter.new()
		boss.name = "boss"
		boss.position = spawn_point(2, 0)
		boss.rotation.y = 0.0
		fighters_root.add_child(boss)
		boss.setup("👑 " + str(bc.name), 2, {"body": "male", "skin": "skin_lava", "outfit": "outfit_knight", "face_b64": ""}, false, bc, true, self)
		fighters["boss"] = boss


func nearest_enemy(f: Fighter) -> Fighter:
	var best: Fighter = null
	var bd := INF
	for o in fighters.values():
		if o.alive and o.team != f.team:
			var d: float = f.global_position.distance_squared_to(o.global_position)
			if d < bd:
				bd = d
				best = o
	return best


func _on_peer_left(id: int) -> void:
	var key := "p%d" % id
	if fighters.has(key):
		fighters[key].queue_free()
		fighters.erase(key)


# =====================================================================
# Damage / death / respawn (host decides, everyone applies)
# =====================================================================
@rpc("any_peer", "call_local", "reliable")
func request_damage(target_name: String, dmg: float, shooter_name: String) -> void:
	if not multiplayer.is_server() or ended:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	var t: Fighter = fighters.get(target_name)
	var s: Fighter = fighters.get(shooter_name)
	if t == null or s == null:
		return
	if s.get_multiplayer_authority() != sender:
		return
	if not t.alive or not s.alive or t.team == s.team:
		return
	_host_damage(t, clampf(dmg, 0.0, 400.0), s)


func _host_damage(t: Fighter, dmg: float, s: Fighter) -> void:
	if not t.alive:
		return
	t.hp -= dmg
	sync_hp.rpc(str(t.name), t.hp)
	if t.hp <= 0.0:
		t.alive = false
		sync_death.rpc(str(t.name), str(s.name))


@rpc("authority", "call_local", "reliable")
func sync_hp(target_name: String, hp: float) -> void:
	var f: Fighter = fighters.get(target_name)
	if f == null:
		return
	var old := f.hp
	f.hp = hp
	if f.is_local and hp < old:
		flash.color.a = 0.35
		create_tween().tween_property(flash, "color:a", 0.0, 0.35)


@rpc("authority", "call_local", "reliable")
func sync_death(target_name: String, shooter_name: String) -> void:
	var t: Fighter = fighters.get(target_name)
	var s: Fighter = fighters.get(shooter_name)
	if t == null:
		return
	t.die()
	t.deaths += 1
	if s != null:
		s.kills += 1
		if mode == "tdm" and s.team < 2 and s.team != t.team:
			scores[s.team] += 1
	_feed("%s  ➜  %s" % [s.fname if s else "؟", t.fname], t.team)
	if t == local:
		respawn_t = 4.0
	if multiplayer.is_server():
		_host_after_death(t)


func _host_after_death(t: Fighter) -> void:
	if mode == "tdm":
		if scores[0] >= KILL_LIMIT or scores[1] >= KILL_LIMIT:
			end_match.rpc(0 if scores[0] >= scores[1] else 1)
			return
	elif t.boss:
		end_match.rpc(0)
		return
	if t.boss:
		return
	var key := str(t.name)
	await get_tree().create_timer(4.0).timeout
	if ended or not fighters.has(key):
		return
	respawn.rpc(key, _random_spawn(t.team))


@rpc("authority", "call_local", "reliable")
func respawn(target_name: String, pos: Vector3) -> void:
	var f: Fighter = fighters.get(target_name)
	if f == null:
		return
	f.respawn(pos)
	if f == local:
		center_lbl.text = ""


func host_slam(b: Fighter) -> void:
	slam_fx.rpc(b.global_position)
	for f in fighters.values():
		if f.alive and f.team != b.team and f.global_position.distance_to(b.global_position) < 9.0:
			_host_damage(f, float(b.cfg.get("slam", 30.0)), b)


@rpc("authority", "call_local", "unreliable")
func slam_fx(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.25
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.4, 0.1, 0.8)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.35, 0.05)
	m.emission_energy_multiplier = 3.0
	mi.material_override = m
	add_child(mi)
	mi.global_position = Vector3(pos.x, 0.15, pos.z)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(9.0, 1.0, 9.0), 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.5)
	tw.tween_callback(mi.queue_free)


@rpc("any_peer", "call_local", "unreliable")
func fire_fx(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.2:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = length
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = (a + b) * 0.5
	var dir := (b - a).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	mi.look_at(b, up)
	mi.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)

	var spark := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 8
	sm.rings = 4
	spark.mesh = sm
	spark.material_override = _tracer_mat
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(spark)
	spark.global_position = b
	get_tree().create_timer(0.1).timeout.connect(spark.queue_free)


@rpc("authority", "call_local", "reliable")
func end_match(winner: int) -> void:
	if ended:
		return
	ended = true
	input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var my_team := local.team if local != null else 0
	var tie := winner == -1
	var win := winner == my_team
	var reward := 150 if win else (90 if tie else 60)
	if local != null:
		reward += local.kills * 10
	if mode == "boss" and win:
		reward += int(Catalog.BOSS_LEVELS[clampi(Net.boss_level, 1, Catalog.BOSS_LEVELS.size()) - 1].reward)
	reward = mini(reward, 800)
	Api.call_api("add_coins", {"amount": reward})
	var title := "تعادل" if tie else ("🎉 فزتم!" if win else "خسرتم")
	var detail := ""
	if mode == "tdm":
		detail = "النتيجة: %d - %d" % [scores[0], scores[1]]
	result_lbl.text = "%s\n%s\n+%d 🪙" % [title, detail, reward]
	result_panel.visible = true
	pause_panel.visible = false


func show_hit_marker(head: bool) -> void:
	hit_lbl.modulate = Color(1, 0.25, 0.25) if head else Color.WHITE
	hit_lbl.visible = true
	get_tree().create_timer(0.12).timeout.connect(func(): hit_lbl.visible = false)


# =====================================================================
# HUD
# =====================================================================
func _hud_label(text: String, size := 26) -> Label:
	var l := UI.label(text, size)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.make_theme()
	layer.add_child(root)

	flash = ColorRect.new()
	flash.color = Color(1, 0, 0, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)

	if use_touch:
		var tcn := TouchControls.new()
		tcn.match_node = self
		root.add_child(tcn)
		tcn.set_anchors_preset(Control.PRESET_FULL_RECT)
		touch = tcn

	top_lbl = _hud_label("", 30)
	root.add_child(top_lbl)
	top_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	top_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var cross := _hud_label("+", 40)
	root.add_child(cross)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	cross.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cross.grow_vertical = Control.GROW_DIRECTION_BOTH

	hit_lbl = _hud_label("✕", 34)
	hit_lbl.visible = false
	root.add_child(hit_lbl)
	hit_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	hit_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hit_lbl.grow_vertical = Control.GROW_DIRECTION_BOTH

	var hp_box := UI.vbox(2)
	hp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_lbl = _hud_label("", 22)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(380, 24)
	hp_bar.show_percentage = false
	hp_bar.max_value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = UI.GOOD
	fill.set_corner_radius_all(6)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	back.set_corner_radius_all(6)
	hp_bar.add_theme_stylebox_override("fill", fill)
	hp_bar.add_theme_stylebox_override("background", back)
	hp_box.add_child(hp_lbl)
	hp_box.add_child(hp_bar)
	root.add_child(hp_box)
	hp_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)

	var boss_box := UI.vbox(2)
	boss_lbl = _hud_label("", 22)
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(640, 20)
	boss_bar.show_percentage = false
	boss_bar.max_value = 100.0
	var bfill := StyleBoxFlat.new()
	bfill.bg_color = Color("c0392b")
	bfill.set_corner_radius_all(6)
	boss_bar.add_theme_stylebox_override("fill", bfill)
	boss_bar.add_theme_stylebox_override("background", back)
	boss_box.add_child(boss_lbl)
	boss_box.add_child(boss_bar)
	boss_box.visible = mode == "boss"
	root.add_child(boss_box)
	boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 60)
	boss_box.grow_horizontal = Control.GROW_DIRECTION_BOTH

	feed_box = UI.vbox(2)
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed_box)
	feed_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	feed_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	center_lbl = _hud_label("", 36)
	center_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(center_lbl)
	center_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	center_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_lbl.position.y += 120

	board_lbl = _hud_label("", 22)
	board_lbl.visible = false
	board_lbl.add_theme_color_override("font_color", Color.WHITE)
	root.add_child(board_lbl)
	board_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	board_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	board_lbl.grow_vertical = Control.GROW_DIRECTION_BOTH

	var tip := _hud_label("WASD حركة • ماوس تصويب • كليك يمين/شمال: ضرب • Shift جري • Space نط • Tab نتيجة • Esc قائمة", 16)
	root.add_child(tip)
	tip.visible = not use_touch
	tip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	tip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tip.grow_vertical = Control.GROW_DIRECTION_BEGIN

	pause_panel = _make_panel(root)
	var pv := UI.vbox(12)
	pause_panel.add_child(pv)
	pv.add_child(UI.label("متوقف", 30, UI.ACCENT))
	pv.add_child(UI.button("كمّل", _resume, true))
	pv.add_child(UI.button("اخرج من الماتش والغرفة", func(): Net.leave()))
	pause_panel.visible = false

	result_panel = _make_panel(root)
	var rv := UI.vbox(14)
	result_panel.add_child(rv)
	result_lbl = UI.label("", 34, UI.ACCENT)
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(result_lbl)
	rv.add_child(UI.button("رجوع للقائمة", _back_to_menu, true))
	result_panel.visible = false


func _make_panel(root: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(420, 0)
	root.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	return p


func _feed(text: String, team: int) -> void:
	var l := _hud_label(text, 20)
	l.add_theme_color_override("font_color", Catalog.TEAM_COLORS[clampi(team, 0, 2)].lightened(0.4))
	feed_box.add_child(l)
	while feed_box.get_child_count() > 6:
		var old := feed_box.get_child(0)
		feed_box.remove_child(old)
		old.queue_free()
	get_tree().create_timer(5.0).timeout.connect(_expire.bind(l))


func _expire(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()


func _resume() -> void:
	paused = false
	pause_panel.visible = false
	input_enabled = not ended
	if not use_touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _back_to_menu() -> void:
	Net.in_match = false
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")


func toggle_pause() -> void:
	if ended:
		return
	if paused:
		_resume()
	else:
		paused = true
		input_enabled = false
		pause_panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(e: InputEvent) -> void:
	if ended:
		return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		toggle_pause()
	elif e is InputEventMouseButton and e.pressed and not paused and not use_touch and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if not ended:
		time_left = maxf(time_left - delta, 0.0)
		if multiplayer.is_server() and time_left <= 0.0:
			if mode == "tdm":
				end_match.rpc(0 if scores[0] > scores[1] else (1 if scores[1] > scores[0] else -1))
			else:
				end_match.rpc(2)

	var secs := int(time_left)
	var clock := "%d:%02d" % [secs / 60, secs % 60]
	if mode == "tdm":
		top_lbl.text = "🔵 %d   ⏱ %s   %d 🔴" % [scores[0], clock, scores[1]]
	else:
		top_lbl.text = "الكل ضد البوس   ⏱ %s" % clock

	if local != null:
		hp_bar.value = maxf(local.hp, 0.0) / local.max_hp * 100.0
		hp_lbl.text = "❤ %d   |   قتلات %d" % [int(maxf(local.hp, 0.0)), local.kills]
		if not local.alive and not ended:
			respawn_t = maxf(respawn_t - delta, 0.0)
			center_lbl.text = "هتنزل بعد %d" % ceili(respawn_t)
		elif local.alive:
			center_lbl.text = ""
	if mode == "boss" and fighters.has("boss"):
		var bf: Fighter = fighters["boss"]
		boss_bar.value = maxf(bf.hp, 0.0) / bf.max_hp * 100.0
		boss_lbl.text = "%s  (%d)" % [bf.fname, int(maxf(bf.hp, 0.0))]

	board_lbl.visible = Input.is_physical_key_pressed(KEY_TAB) and not ended
	if board_lbl.visible:
		board_lbl.text = _board_text()


func _board_text() -> String:
	var out := ""
	var teams: Array = [0, 1] if mode == "tdm" else [0, 2]
	for t in teams:
		out += "— %s —\n" % Catalog.TEAM_NAMES[t]
		var list: Array = []
		for f in fighters.values():
			if f.team == t:
				list.append(f)
		list.sort_custom(func(a, b): return a.kills > b.kills)
		for f in list:
			out += "%s     %d / %d\n" % [f.fname, f.kills, f.deaths]
		out += "\n"
	return out
