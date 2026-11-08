class_name Fighter
extends CharacterBody3D
# One combatant: a human (controlled by its owner peer), or an AI bot / boss (simulated on the host).

const GRAVITY := 24.0
const JUMP_SPEED := 8.0
const HUMAN_SPEED := 6.5
const HUMAN_DMG := 14.0
const HUMAN_FIRE_RATE := 0.11

var fname := ""
var team := 0
var human := false
var boss := false
var cfg := {}
var look := {}
var hp := 100.0
var max_hp := 100.0
var alive := true
var kills := 0
var deaths := 0
var match_node: Node
var model: CharacterModel
var cam: Camera3D
var pivot: Node3D
var is_local := false
var body_scale := 1.0

var yaw := 0.0
var pitch := 0.0
var moving := false
var fire_cd := 0.0

# remote interpolation
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var _sync_t := 0.0

# AI state
var ai_target: Fighter
var ai_retarget := 0.0
var ai_react := 0.5
var ai_strafe := 1.0
var ai_strafe_t := 1.0
var ai_stuck_t := 0.0
var ai_slam_t := 6.0


func setup(p_name: String, p_team: int, p_look: Dictionary, p_human: bool, p_cfg: Dictionary, p_boss: bool, p_match: Node) -> void:
	fname = p_name
	team = p_team
	look = p_look
	human = p_human
	cfg = p_cfg
	boss = p_boss
	match_node = p_match
	body_scale = 2.2 if boss else 1.0
	collision_layer = 2
	collision_mask = 1
	max_hp = float(cfg.get("hp", 100.0))
	hp = max_hp

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35 * body_scale
	cap.height = 1.8 * body_scale
	cs.shape = cap
	cs.position.y = 0.9 * body_scale
	add_child(cs)

	model = CharacterModel.new()
	model.scale = Vector3.ONE * body_scale
	add_child(model)
	model.build(look, fname, Catalog.TEAM_COLORS[clampi(team, 0, 2)])
	model.aiming = true
	var tag := model.get_node_or_null("NameTag")
	if tag:
		tag.position.y = 2.25

	is_local = human and is_multiplayer_authority()
	net_pos = global_position
	if is_local:
		yaw = rotation.y
		pivot = Node3D.new()
		pivot.position = Vector3(0, 1.55, 0)
		add_child(pivot)
		var arm := SpringArm3D.new()
		arm.spring_length = 3.3
		arm.collision_mask = 1
		arm.margin = 0.25
		arm.position = Vector3(0.65, 0.15, 0)
		arm.shape = null
		pivot.add_child(arm)
		cam = Camera3D.new()
		cam.fov = 78.0
		cam.near = 0.05
		cam.far = 600.0
		arm.add_child(cam)
		cam.make_current()
		if tag:
			tag.visible = false


func _unhandled_input(e: InputEvent) -> void:
	if not is_local or not alive:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.0022
		pitch = clampf(pitch - e.relative.y * 0.0022, -1.2, 1.15)
		rotation.y = yaw
		pivot.rotation.x = pitch


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var mv := Vector2.ZERO
	var fire := false
	var jump := false
	var sprint := false
	if alive:
		if human:
			if match_node.input_enabled:
				mv.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
				mv.y = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
				mv.x += float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
				mv.y += float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))
				jump = Input.is_physical_key_pressed(KEY_SPACE)
				sprint = Input.is_physical_key_pressed(KEY_SHIFT)
				fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
				var tc = match_node.touch
				if tc != null:
					mv += tc.move
					jump = jump or tc.jump_held
					fire = fire or tc.fire_held
					sprint = sprint or tc.move.length() > 0.92
		else:
			var it := _ai_intent(delta)
			mv = it.move
			fire = it.fire
			jump = it.jump
			sprint = it.sprint
	mv = mv.limit_length(1.0)

	var base_speed: float = HUMAN_SPEED if human else float(cfg.get("speed", 5.0))
	var spd := base_speed * (1.5 if sprint else 1.0)
	var wish := (global_transform.basis * Vector3(mv.x, 0.0, mv.y)) * spd
	var k := clampf(delta * 14.0, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, wish.x, k)
	velocity.z = lerpf(velocity.z, wish.z, k)
	if is_on_floor():
		velocity.y = JUMP_SPEED if jump else -0.5
	else:
		velocity.y -= GRAVITY * delta
	if alive:
		move_and_slide()
	moving = Vector2(velocity.x, velocity.z).length() > 0.6 and alive

	fire_cd -= delta
	if fire and fire_cd <= 0.0 and alive:
		_shoot()

	_sync_t += delta
	if _sync_t >= 1.0 / 30.0:
		_sync_t = 0.0
		net_state.rpc(global_position, rotation.y, pitch, moving)


@rpc("authority", "unreliable")
func net_state(p: Vector3, y: float, pt: float, mv: bool) -> void:
	net_pos = p
	net_yaw = y
	net_pitch = pt
	moving = mv


func _process(delta: float) -> void:
	if model == null:
		return
	if not is_multiplayer_authority():
		var k := clampf(delta * 16.0, 0.0, 1.0)
		global_position = global_position.lerp(net_pos, k)
		rotation.y = lerp_angle(rotation.y, net_yaw, k)
		pitch = lerpf(pitch, net_pitch, k)
	elif is_local and cam:
		var tc = match_node.touch
		if tc != null:
			var l: Vector2 = tc.consume_look()
			if alive and match_node.input_enabled:
				yaw -= l.x
				pitch = clampf(pitch - l.y, -1.2, 1.15)
				rotation.y = yaw
		pivot.rotation.x = pitch
	model.walk_amount = lerpf(model.walk_amount, 1.0 if moving else 0.0, clampf(delta * 10.0, 0.0, 1.0))
	model.aim_pitch = pitch


# ---------------- shooting ----------------
func _shoot() -> void:
	var dmg: float
	var spread := 0.0
	if human:
		fire_cd = HUMAN_FIRE_RATE
		dmg = HUMAN_DMG
	else:
		fire_cd = float(cfg.get("fire_rate", 0.2))
		dmg = float(cfg.get("dmg", 8.0))
		spread = float(cfg.get("spread", 3.0))

	var muzzle := global_transform * Vector3(0.32 * body_scale, 1.38 * body_scale, -0.75 * body_scale)
	var origin: Vector3
	var dir: Vector3
	if is_local:
		origin = cam.global_position
		dir = -cam.global_transform.basis.z
	else:
		if ai_target == null or not is_instance_valid(ai_target):
			return
		origin = global_position + Vector3(0, 1.45 * body_scale, 0)
		var aim_at := ai_target.global_position + Vector3(0, 1.2 * ai_target.body_scale, 0)
		dir = (aim_at - origin).normalized()
	if spread > 0.0:
		var s := tan(deg_to_rad(spread))
		dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s).normalized()

	var to := origin + dir * 220.0
	var q := PhysicsRayQueryParameters3D.create(origin, to, 3)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	if hit:
		end = hit.position
		var c = hit.collider
		if c is Fighter and c.alive and c.team != team:
			var head_y: float = c.global_position.y + 1.55 * c.body_scale
			var head := hit.position.y > head_y
			var final_dmg := dmg * (2.0 if head else 1.0)
			match_node.request_damage.rpc_id(1, str(c.name), final_dmg, str(name))
			if is_local:
				match_node.show_hit_marker(head)
	match_node.fire_fx.rpc(muzzle, end)


# ---------------- AI ----------------
func _ai_intent(delta: float) -> Dictionary:
	var it := {"move": Vector2.ZERO, "fire": false, "jump": false, "sprint": false}
	ai_retarget -= delta
	if ai_retarget <= 0.0 or ai_target == null or not is_instance_valid(ai_target) or not ai_target.alive:
		ai_retarget = 0.6
		var nt: Fighter = match_node.nearest_enemy(self)
		if nt != ai_target:
			ai_react = float(cfg.get("reaction", 0.5))
		ai_target = nt
	if boss:
		ai_slam_t -= delta
		if ai_slam_t <= 0.0:
			ai_slam_t = 7.0
			match_node.host_slam(self)
	if ai_target == null:
		return it

	var to := ai_target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var want_yaw := atan2(-to.x, -to.z)
	rotation.y = lerp_angle(rotation.y, want_yaw, clampf(delta * float(cfg.get("turn", 4.0)), 0.0, 1.0))
	var aim_dy := (ai_target.global_position.y + 1.2) - (global_position.y + 1.45)
	pitch = lerpf(pitch, clampf(atan2(aim_dy, maxf(dist, 1.0)), -0.6, 0.6), clampf(delta * 6.0, 0.0, 1.0))

	var rng := float(cfg.get("range", 30.0))
	var mv := Vector2.ZERO
	if dist > rng * 0.55:
		mv.y = -1.0
		it.sprint = dist > rng
	elif dist < rng * 0.22:
		mv.y = 1.0
	ai_strafe_t -= delta
	if ai_strafe_t <= 0.0:
		ai_strafe_t = randf_range(0.7, 1.8)
		if randf() < 0.5:
			ai_strafe = -ai_strafe
	if dist < rng * 0.9:
		mv.x = ai_strafe * 0.7

	if mv.length() > 0.1 and Vector2(velocity.x, velocity.z).length() < 0.9:
		ai_stuck_t += delta
	else:
		ai_stuck_t = maxf(0.0, ai_stuck_t - delta)
	if ai_stuck_t > 0.5:
		it.jump = true
		mv.x = ai_strafe
		if ai_stuck_t > 1.1:
			ai_strafe = -ai_strafe
			ai_stuck_t = 0.0
	it.move = mv

	var facing := absf(angle_difference(rotation.y, want_yaw))
	if dist < rng and facing < 0.22:
		ai_react -= delta
		if ai_react <= 0.0 and _has_los():
			it.fire = true
	elif dist >= rng or facing >= 0.5:
		ai_react = float(cfg.get("reaction", 0.5))
	return it


func _has_los() -> bool:
	if ai_target == null:
		return false
	var a := global_position + Vector3(0, 1.45 * body_scale, 0)
	var b := ai_target.global_position + Vector3(0, 1.2 * ai_target.body_scale, 0)
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# ---------------- life cycle (called from Match on every peer) ----------------
func die() -> void:
	alive = false
	hp = 0.0
	moving = false
	model.play_death()
	var tag := model.get_node_or_null("NameTag")
	if tag:
		tag.visible = false


func respawn(pos: Vector3) -> void:
	alive = true
	hp = max_hp
	global_position = pos
	net_pos = pos
	velocity = Vector3.ZERO
	ai_target = null
	model.reset_pose()
	var tag := model.get_node_or_null("NameTag")
	if tag and not is_local:
		tag.visible = true
