class_name TouchControls
extends Control
# On-screen controls for phones: left thumb = move joystick, right thumb = look,
# FIRE and JUMP buttons, small pause button. Used only on mobile builds.

const JOY_R := 110.0
const LOOK_SENS := 0.0045

var match_node: Node
var move := Vector2.ZERO
var fire_held := false
var jump_held := false
var look_accum := Vector2.ZERO

var _joy_id := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_id := -1
var _fire_id := -1
var _jump_id := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _vp() -> Vector2:
	return get_viewport_rect().size


func _fire_c() -> Vector2:
	var s := _vp()
	return Vector2(s.x - 170.0, s.y - 170.0)


func _jump_c() -> Vector2:
	var s := _vp()
	return Vector2(s.x - 360.0, s.y - 105.0)


func _pause_c() -> Vector2:
	return Vector2(70.0, 70.0)


func consume_look() -> Vector2:
	var l := look_accum * LOOK_SENS
	look_accum = Vector2.ZERO
	return l


func _release_all() -> void:
	_joy_id = -1
	_look_id = -1
	_fire_id = -1
	_jump_id = -1
	move = Vector2.ZERO
	fire_held = false
	jump_held = false


func _input(e: InputEvent) -> void:
	if match_node == null or match_node.paused or match_node.ended:
		if _joy_id != -1 or _fire_id != -1 or _jump_id != -1 or _look_id != -1:
			_release_all()
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			_press(e.index, e.position)
		else:
			_release(e.index)
	elif e is InputEventScreenDrag:
		_drag(e.index, e.position, e.relative)


func _press(idx: int, pos: Vector2) -> void:
	var s := _vp()
	if pos.distance_to(_pause_c()) < 50.0:
		match_node.toggle_pause()
		return
	if _fire_id == -1 and pos.distance_to(_fire_c()) < 105.0:
		_fire_id = idx
		fire_held = true
	elif _jump_id == -1 and pos.distance_to(_jump_c()) < 85.0:
		_jump_id = idx
		jump_held = true
	elif _joy_id == -1 and pos.x < s.x * 0.42:
		_joy_id = idx
		_joy_origin = pos
		_joy_pos = pos
		move = Vector2.ZERO
	elif _look_id == -1 and pos.x >= s.x * 0.42:
		_look_id = idx


func _release(idx: int) -> void:
	if idx == _joy_id:
		_joy_id = -1
		move = Vector2.ZERO
	elif idx == _look_id:
		_look_id = -1
	elif idx == _fire_id:
		_fire_id = -1
		fire_held = false
	elif idx == _jump_id:
		_jump_id = -1
		jump_held = false


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if idx == _joy_id:
		_joy_pos = pos
		var d := (pos - _joy_origin) / JOY_R
		move = d.limit_length(1.0)
		if move.length() < 0.15:
			move = Vector2.ZERO
	elif idx == _look_id:
		look_accum += rel
	elif idx == _fire_id:
		look_accum += rel * 0.7   # aim while holding fire


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if match_node == null or match_node.paused or match_node.ended:
		return
	var white := Color(1, 1, 1, 0.35)
	var s := _vp()
	# joystick
	var o := _joy_origin if _joy_id != -1 else Vector2(190.0, s.y - 190.0)
	var p := _joy_pos if _joy_id != -1 else o
	draw_circle(o, JOY_R, Color(1, 1, 1, 0.10))
	draw_arc(o, JOY_R, 0.0, TAU, 48, white, 3.0, true)
	draw_circle(o + (p - o).limit_length(JOY_R), 46.0, Color(1, 1, 1, 0.30))
	# fire
	var fc := _fire_c()
	draw_circle(fc, 90.0, Color(1.0, 0.25, 0.2, 0.55 if fire_held else 0.30))
	draw_arc(fc, 90.0, 0.0, TAU, 48, Color(1.0, 0.5, 0.4, 0.7), 4.0, true)
	draw_line(fc + Vector2(-26, 0), fc + Vector2(26, 0), Color(1, 1, 1, 0.8), 4.0)
	draw_line(fc + Vector2(0, -26), fc + Vector2(0, 26), Color(1, 1, 1, 0.8), 4.0)
	# jump
	var jc := _jump_c()
	draw_circle(jc, 66.0, Color(0.3, 0.7, 1.0, 0.55 if jump_held else 0.28))
	draw_arc(jc, 66.0, 0.0, TAU, 40, Color(0.6, 0.85, 1.0, 0.7), 4.0, true)
	draw_line(jc + Vector2(0, 18), jc + Vector2(0, -18), Color(1, 1, 1, 0.8), 4.0)
	draw_line(jc + Vector2(-14, -6), jc + Vector2(0, -20), Color(1, 1, 1, 0.8), 4.0)
	draw_line(jc + Vector2(14, -6), jc + Vector2(0, -20), Color(1, 1, 1, 0.8), 4.0)
	# pause
	var pc := _pause_c()
	draw_circle(pc, 38.0, Color(0, 0, 0, 0.35))
	draw_rect(Rect2(pc + Vector2(-12, -14), Vector2(8, 28)), Color(1, 1, 1, 0.8))
	draw_rect(Rect2(pc + Vector2(4, -14), Vector2(8, 28)), Color(1, 1, 1, 0.8))
