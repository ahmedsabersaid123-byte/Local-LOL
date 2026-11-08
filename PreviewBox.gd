class_name PreviewBox
extends SubViewportContainer
# A rotating 3D preview of a character, used in the character and shop tabs.

var model: CharacterModel
var vp: SubViewport
var spin := true


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(380, 520)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	add_child(vp)

	var cam := Camera3D.new()
	cam.fov = 38.0
	vp.add_child(cam)
	cam.position = Vector3(0, 1.15, 4.2)
	cam.look_at(Vector3(0, 0.95, 0))

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8899bb")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -30, 0)
	key.light_energy = 1.8
	key.shadow_enabled = true
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-2.5, 2.0, -2.0)
	rim.light_color = Color("ff9a1f")
	rim.light_energy = 3.0
	rim.omni_range = 8.0
	vp.add_child(rim)

	var floor_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 0.95
	cyl.height = 0.06
	floor_mesh.mesh = cyl
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("20283d")
	fm.metallic = 0.6
	fm.roughness = 0.3
	floor_mesh.material_override = fm
	floor_mesh.position.y = -0.03
	vp.add_child(floor_mesh)

	model = CharacterModel.new()
	vp.add_child(model)


func _ready() -> void:
	Gfx.apply_viewport(vp)


func show_look(look: Dictionary, nm := "") -> void:
	model.build(look, nm)


func _process(delta: float) -> void:
	if spin:
		model.rotation.y += delta * 0.7
