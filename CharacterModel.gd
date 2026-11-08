class_name CharacterModel
extends Node3D
# Builds a detailed character from primitives: male/female body, skin, outfit, your face photo.
# Origin is at the feet, the character faces -Z.

static var _face_shader: Shader
static var _tex_cache := {}

var look := {}
var walk_amount := 0.0
var aiming := false
var aim_pitch := 0.0
var dead := false

var _t := 0.0
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _torso: Node3D
var _head: Node3D
var _skin_mat: StandardMaterial3D


func build(p_look: Dictionary, p_name := "", team_color := Color.TRANSPARENT) -> void:
	for c in get_children():
		c.queue_free()
	look = p_look
	dead = false
	rotation.x = 0.0
	var female: bool = str(look.get("body", "male")) == "female"
	var skin: Dictionary = Catalog.SKINS.get(str(look.get("skin", "skin_default")), Catalog.SKINS["skin_default"])
	var outfit: Dictionary = Catalog.OUTFITS.get(str(look.get("outfit", "outfit_default")), Catalog.OUTFITS["outfit_default"])

	_skin_mat = _mat(skin.color, skin.metal, skin.rough, skin.emit, skin.get("emit_color", skin.color))
	var top_mat := _mat(outfit.top, outfit.get("metal", 0.0), 0.55, outfit.emit, outfit.get("emit_color", outfit.top))
	var bot_mat := _mat(outfit.bottom, outfit.get("metal", 0.0), 0.6, 0.0, outfit.bottom)
	var shoe_mat := _mat(Color("1b1b1f"), 0.1, 0.5, 0.0, Color.BLACK)
	var hair_mat := _mat(Color("2a1a12") if not female else Color("4a2312"), 0.0, 0.35, 0.0, Color.BLACK)

	var shoulder := 0.27 if not female else 0.22
	var hip_w := 0.13 if not female else 0.15

	# legs
	_leg_l = _limb(Vector3(-hip_w, 0.9, 0), 0.86, 0.095, bot_mat, shoe_mat)
	_leg_r = _limb(Vector3(hip_w, 0.9, 0), 0.86, 0.095, bot_mat, shoe_mat)

	# torso (rotates a bit when aiming)
	_torso = Node3D.new()
	_torso.position = Vector3(0, 0.9, 0)
	add_child(_torso)
	var chest := _add(_torso, _capsule(0.2 if not female else 0.17, 0.75), top_mat, Vector3(0, 0.36, 0))
	chest.scale = Vector3(1.15 if not female else 1.0, 1.0, 0.7)
	var belt := _add(_torso, _cyl(0.2, 0.2, 0.08), bot_mat, Vector3(0, 0.02, 0))
	belt.scale = Vector3(1.1 if not female else 1.25, 1.0, 0.75)
	if female:
		var skirt := _add(_torso, _cyl(0.17, 0.27, 0.22), bot_mat, Vector3(0, -0.08, 0))
		skirt.scale = Vector3(1.0, 1.0, 0.8)

	# arms
	_arm_l = _limb(Vector3(-shoulder - 0.08, 0.7, 0), 0.62, 0.065, top_mat, _skin_mat, _torso)
	_arm_r = _limb(Vector3(shoulder + 0.08, 0.7, 0), 0.62, 0.065, top_mat, _skin_mat, _torso)

	# gun in right hand
	var gun_mat := _mat(Color("2b2d33"), 0.8, 0.35, 0.0, Color.BLACK)
	var gun := _add(_arm_r, _box(Vector3(0.07, 0.55, 0.11)), gun_mat, Vector3(0, -0.72, 0))
	gun.name = "Gun"

	# neck + head
	_add(_torso, _cyl(0.06, 0.06, 0.12), _skin_mat, Vector3(0, 0.78, 0))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.98, 0)
	_torso.add_child(_head)
	_add(_head, _sphere(0.2), _skin_mat, Vector3.ZERO).scale = Vector3(0.95, 1.08, 1.0)
	_build_face(str(look.get("face_b64", "")))

	# hair
	if female:
		var hair := _add(_head, _sphere(0.215), hair_mat, Vector3(0, 0.04, 0.05))
		hair.scale = Vector3(0.98, 1.0, 1.0)
		_add(_head, _capsule(0.07, 0.5), hair_mat, Vector3(0, -0.15, 0.22))      # ponytail
	else:
		var hair2 := _add(_head, _sphere(0.208), hair_mat, Vector3(0, 0.06, 0.06))
		hair2.scale = Vector3(0.97, 0.85, 0.98)

	_add_accessory(str(outfit.get("acc", "")), outfit, top_mat)

	# team ring + name tag
	if team_color != Color.TRANSPARENT:
		var ring := _add(self, _cyl(0.6, 0.6, 0.02), _mat(team_color, 0.0, 0.4, 2.0, team_color), Vector3(0, 0.02, 0))
		ring.name = "TeamRing"
	if p_name != "":
		var lb := Label3D.new()
		lb.text = p_name
		lb.font_size = 48
		lb.pixel_size = 0.0045
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.outline_size = 14
		lb.modulate = team_color if team_color != Color.TRANSPARENT else Color.WHITE
		lb.no_depth_test = false
		lb.position = Vector3(0, 2.2, 0)
		lb.name = "NameTag"
		add_child(lb)


func _add_accessory(acc: String, outfit: Dictionary, top_mat: StandardMaterial3D) -> void:
	var dark := _mat(Color("202228"), 0.6, 0.4, 0.0, Color.BLACK)
	match acc:
		"helmet":
			var m := _mat(outfit.top.darkened(0.1), 0.2, 0.5, 0.0, Color.BLACK)
			var h := _add(_head, _sphere(0.235), m, Vector3(0, 0.07, 0.02))
			h.scale = Vector3(1.0, 0.8, 1.05)
		"headband":
			var hb := _add(_head, _cyl(0.212, 0.212, 0.06), _mat(Color("d02020"), 0.0, 0.6, 0.0, Color.BLACK), Vector3(0, 0.08, 0))
			hb.scale = Vector3(0.97, 1.0, 1.0)
		"cape":
			var cape := _add(_torso, _box(Vector3(0.5, 0.95, 0.04)), _mat(Color("8a1020"), 0.0, 0.8, 0.0, Color.BLACK), Vector3(0, 0.25, 0.2))
			cape.name = "Cape"
		"visor":
			var vm := _mat(outfit.get("emit_color", Color.CYAN), 0.0, 0.1, 3.0, outfit.get("emit_color", Color.CYAN))
			_add(_head, _box(Vector3(0.36, 0.07, 0.06)), vm, Vector3(0, 0.03, -0.17))
		"cap":
			_add(_head, _sphere(0.215), _mat(Color("d6342c"), 0.0, 0.6, 0.0, Color.BLACK), Vector3(0, 0.08, 0.02)).scale = Vector3(1.0, 0.55, 1.0)
			_add(_head, _box(Vector3(0.3, 0.02, 0.18)), dark, Vector3(0, 0.07, -0.2))
		"hood":
			_add(_head, _sphere(0.24), top_mat, Vector3(0, 0.02, 0.05))


func _build_face(b64: String) -> void:
	var tex: Texture2D = null
	if b64 != "":
		tex = _tex_from_b64(b64)
	if tex != null:
		if _face_shader == null:
			_face_shader = Shader.new()
			_face_shader.code = """
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;
uniform sampler2D face_tex : source_color, filter_linear_mipmap, repeat_disable;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = texture(face_tex, UV).rgb;
	ALPHA = smoothstep(1.0, 0.82, d);
	ROUGHNESS = 0.55;
	SPECULAR = 0.3;
}
"""
		var sm := ShaderMaterial.new()
		sm.shader = _face_shader
		sm.set_shader_parameter("face_tex", tex)
		var quad := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.36, 0.36)
		quad.mesh = q
		quad.material_override = sm
		quad.position = Vector3(0, 0.0, -0.172)
		quad.rotation.y = PI
		_head.add_child(quad)
	else:
		var eye := _mat(Color("101010"), 0.0, 0.3, 0.0, Color.BLACK)
		for sx in [-1.0, 1.0]:
			_add(_head, _sphere(0.028), eye, Vector3(0.07 * sx, 0.03, -0.185))
		_add(_head, _box(Vector3(0.09, 0.015, 0.02)), _mat(Color("7a2a2a"), 0.0, 0.5, 0.0, Color.BLACK), Vector3(0, -0.07, -0.185))


static func _tex_from_b64(b64: String) -> Texture2D:
	var key := b64.hash()
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.new()
	var err := img.load_jpg_from_buffer(Marshalls.base64_to_raw(b64))
	if err != OK:
		return null
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t


func _limb(pos: Vector3, length: float, radius: float, mat: Material, end_mat: Material, parent: Node3D = null) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	(parent if parent != null else self).add_child(pivot)
	var upper := _add(pivot, _capsule(radius, length * 0.62), mat, Vector3(0, -length * 0.31, 0))
	upper.name = "Upper"
	var lower := _add(pivot, _capsule(radius * 0.95, length * 0.46), end_mat, Vector3(0, -length * 0.77, 0))
	lower.name = "Lower"
	return pivot


func _mat(color: Color, metal: float, rough: float, emit: float, emit_color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = emit_color
		m.emission_energy_multiplier = emit
	return m


func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0 + 0.01)
	c.radial_segments = 32
	c.rings = 12
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 48
	s.rings = 24
	return s


func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = 32
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _process(delta: float) -> void:
	if _leg_l == null or dead:
		return
	_t += delta * (3.0 + walk_amount * 7.0)
	var swing := sin(_t) * 0.75 * walk_amount
	_leg_l.rotation.x = swing
	_leg_r.rotation.x = -swing
	var breathe := sin(_t * 0.5) * 0.02
	_torso.position.y = 0.9 + absf(sin(_t)) * 0.02 * walk_amount + breathe * (1.0 - walk_amount)
	if aiming:
		_arm_r.rotation.x = 1.45 + aim_pitch * 0.9
		_arm_l.rotation.x = 1.25 + aim_pitch * 0.9
		_arm_l.rotation.y = -0.35
		_torso.rotation.y = -0.15
	else:
		_arm_l.rotation.x = -swing
		_arm_r.rotation.x = swing
		_arm_l.rotation.y = 0.0
		_torso.rotation.y = 0.0
	_head.rotation.x = aim_pitch * 0.6 if aiming else 0.0


func play_death() -> void:
	dead = true
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", -PI / 2.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "position:y", 0.2, 0.45)


func reset_pose() -> void:
	dead = false
	rotation.x = 0.0
	position.y = 0.0
