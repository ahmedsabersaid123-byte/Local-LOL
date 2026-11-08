extends Node
# Graphics quality + FPS cap. quality: 0 متوسط, 1 عالي, 2 فائق, 3 أقصى (SDFGI + كل المؤثرات)

const CFG := "user://local_lol.cfg"
const QUALITY_NAMES := ["متوسط", "عالي", "فائق", "أقصى"]
const FPS_OPTIONS := [60, 120, 144, 240, 0]   # 0 = بدون حد

var quality := 3
var fps_cap := 0


func _ready() -> void:
	if OS.has_feature("mobile"):
		quality = 0      # phones: lightest preset by default
		fps_cap = 60
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		quality = int(cf.get_value("gfx", "quality", quality))
		fps_cap = int(cf.get_value("gfx", "fps", fps_cap))
	apply_global()


func save_prefs() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("gfx", "quality", quality)
	cf.set_value("gfx", "fps", fps_cap)
	cf.save(CFG)


func apply_global() -> void:
	Engine.max_fps = fps_cap
	if fps_cap == 60:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.directional_shadow_atlas_set_size(4096, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)


func apply_viewport(vp: Viewport) -> void:
	match quality:
		0:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.use_taa = false
		1:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.use_taa = false
		2:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.use_taa = true
		_:
			vp.msaa_3d = Viewport.MSAA_8X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.use_taa = true
	vp.mesh_lod_threshold = 0.0 if quality >= 2 else 1.0


func make_environment() -> Environment:
	var q := mini(quality, 1) if OS.has_feature("mobile") else quality
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("2f6fb8")
	sm.sky_horizon_color = Color("bcd4ea")
	sm.ground_horizon_color = Color("a9b4bd")
	sm.ground_bottom_color = Color("3b4148")
	sm.sun_angle_max = 30.0
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_512
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0

	env.ssao_enabled = q >= 1
	env.ssao_intensity = 2.0
	env.ssil_enabled = q >= 2
	env.ssr_enabled = q >= 2
	env.ssr_max_steps = 128
	env.sdfgi_enabled = q >= 3
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4

	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	env.fog_enabled = true
	env.fog_light_color = Color("c3d3e6")
	env.fog_density = 0.0025
	env.volumetric_fog_enabled = q >= 2
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color("e8eef7")
	env.volumetric_fog_gi_inject = 1.0

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	return env


func make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 170.0
	sun.light_angular_distance = 0.5
	return sun
