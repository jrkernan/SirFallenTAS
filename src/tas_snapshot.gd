extends Node
class_name TASSnapshot

## Snapshot of player state for step-back
var position: Vector2
var velocity: Vector2
var state: String
var just_jumped: bool
var jump_buffer: bool
var double_jump: bool
var max_velocity: float
var max_fall_velocity: float
var gravity: float
var wall_slide_speed: float
var in_sand: bool
var in_space: bool
var current_velocity: float
var last_facing: int
var interacting: bool
var interacting_type: String
var global_time: float
var global_timer_on: bool
var timers: Dictionary = {}
var drop_through_platform: bool = true
var platform_times: Dictionary = {}     # NodePath string -> time float for each moving platform
var spawn_point: Vector2 = Vector2.ZERO
var active_checkpoint: String = ""
var sprite_frame: int = 0
var sprite_flip_h: bool = false
var anim_name: String = ""
var anim_position: float = 0.0

func capture(player: Node) -> void:
	if player == null:
		return
	position = player.global_position
	velocity = player.velocity if "velocity" in player else Vector2.ZERO
	state = player.state if "state" in player else ""
	just_jumped = player.just_jumped if "just_jumped" in player else false
	jump_buffer = player.jump_buffer if "jump_buffer" in player else false
	double_jump = player.double_jump if "double_jump" in player else false
	max_velocity = player.max_velocity if "max_velocity" in player else 0.0
	max_fall_velocity = player.max_fall_velocity if "max_fall_velocity" in player else 0.0
	gravity = player.gravity if "gravity" in player else 0.0
	wall_slide_speed = player.wall_slide_speed if "wall_slide_speed" in player else 0.0
	in_sand = player.in_sand if "in_sand" in player else false
	in_space = player.in_space if "in_space" in player else false
	current_velocity = player.current_velocity if "current_velocity" in player else 0.0
	last_facing = player.last_facing if "last_facing" in player else 1
	interacting = player.interacting if "interacting" in player else false
	interacting_type = player.interacting_type if "interacting_type" in player else ""
	if GlobalTimer != null:
		global_time = GlobalTimer.time
		global_timer_on = GlobalTimer.timer_on
	drop_through_platform = player.get_collision_mask_value(8) if "get_collision_mask_value" in player else true

	_capture_timer(timers, player, "coyote_jump_timer")
	_capture_timer(timers, player, "coyote_wall_timer")
	_capture_timer(timers, player, "jump_timer")
	_capture_timer(timers, player, "jump_buffer_timer")
	_capture_timer(timers, player, "b_hop_timer")
	_capture_timer(timers, player, "drop_timer")

	var sp := player.get_node_or_null("sprite")
	if sp != null:
		sprite_frame = sp.frame
		sprite_flip_h = sp.flip_h
	var anim := player.get_node_or_null("AnimationPlayer")
	if anim != null:
		anim_name = anim.current_animation
		anim_position = anim.current_animation_position

func apply(player: Node) -> void:
	if player == null:
		return
	player.global_position = position
	if "velocity" in player:
		player.velocity = velocity
	if "state" in player:
		player.state = state
	if "just_jumped" in player:
		player.just_jumped = just_jumped
	if "jump_buffer" in player:
		player.jump_buffer = jump_buffer
	if "double_jump" in player:
		player.double_jump = double_jump
	if "max_velocity" in player:
		player.max_velocity = max_velocity
	if "max_fall_velocity" in player:
		player.max_fall_velocity = max_fall_velocity
	if "gravity" in player:
		player.gravity = gravity
	if "wall_slide_speed" in player:
		player.wall_slide_speed = wall_slide_speed
	if "in_sand" in player:
		player.in_sand = in_sand
	if "in_space" in player:
		player.in_space = in_space
	if "current_velocity" in player:
		player.current_velocity = current_velocity
	if "last_facing" in player:
		player.last_facing = last_facing
	if "interacting" in player:
		player.interacting = interacting
	if "interacting_type" in player:
		player.interacting_type = interacting_type
	if GlobalTimer != null:
		GlobalTimer.time = global_time
		GlobalTimer.timer_on = global_timer_on
	player.set_collision_mask_value(8, drop_through_platform)

	_restore_timer(timers, player, "coyote_jump_timer")
	_restore_timer(timers, player, "coyote_wall_timer")
	_restore_timer(timers, player, "jump_timer")
	_restore_timer(timers, player, "jump_buffer_timer")
	_restore_timer(timers, player, "b_hop_timer")
	_restore_timer(timers, player, "drop_timer")

	var sp := player.get_node_or_null("sprite")
	var anim := player.get_node_or_null("AnimationPlayer")
	if anim != null:
		if anim_name != "":
			anim.play(anim_name)
			anim.seek(anim_position, true)
		else:
			anim.stop()
			if sp != null:
				sp.frame = sprite_frame
	if sp != null:
		sp.flip_h = sprite_flip_h

func to_dict() -> Dictionary:
	return {
		"position": [position.x, position.y],
		"velocity": [velocity.x, velocity.y],
		"state": state,
		"just_jumped": just_jumped,
		"jump_buffer": jump_buffer,
		"double_jump": double_jump,
		"max_velocity": max_velocity,
		"max_fall_velocity": max_fall_velocity,
		"gravity": gravity,
		"wall_slide_speed": wall_slide_speed,
		"in_sand": in_sand,
		"in_space": in_space,
		"current_velocity": current_velocity,
		"last_facing": last_facing,
		"interacting": interacting,
		"interacting_type": interacting_type,
		"global_time": global_time,
		"global_timer_on": global_timer_on,
		"timers": timers,
		"drop_through_platform": drop_through_platform,
		"platform_times": platform_times,
		"spawn_point": [spawn_point.x, spawn_point.y],
		"active_checkpoint": active_checkpoint,
		"sprite_frame": sprite_frame,
		"sprite_flip_h": sprite_flip_h,
		"anim_name": anim_name,
		"anim_position": anim_position,
	}

static func from_dict(data: Dictionary) -> TASSnapshot:
	var snap := TASSnapshot.new()
	if data.has("position"):
		var p = data["position"]
		snap.position = Vector2(p[0], p[1])
	if data.has("velocity"):
		var v = data["velocity"]
		snap.velocity = Vector2(v[0], v[1])
	snap.state = data.get("state", "")
	snap.just_jumped = data.get("just_jumped", false)
	snap.jump_buffer = data.get("jump_buffer", false)
	snap.double_jump = data.get("double_jump", false)
	snap.max_velocity = data.get("max_velocity", 0.0)
	snap.max_fall_velocity = data.get("max_fall_velocity", 0.0)
	snap.gravity = data.get("gravity", 0.0)
	snap.wall_slide_speed = data.get("wall_slide_speed", 0.0)
	snap.in_sand = data.get("in_sand", false)
	snap.in_space = data.get("in_space", false)
	snap.current_velocity = data.get("current_velocity", 0.0)
	snap.last_facing = data.get("last_facing", 1)
	snap.interacting = data.get("interacting", false)
	snap.interacting_type = data.get("interacting_type", "")
	snap.global_time = data.get("global_time", 0.0)
	snap.global_timer_on = data.get("global_timer_on", false)
	snap.timers = data.get("timers", {})
	snap.drop_through_platform = data.get("drop_through_platform", true)
	snap.platform_times = data.get("platform_times", {})
	if data.has("spawn_point"):
		var sp = data["spawn_point"]
		snap.spawn_point = Vector2(sp[0], sp[1])
	snap.active_checkpoint = data.get("active_checkpoint", "")
	snap.sprite_frame = data.get("sprite_frame", 0)
	snap.sprite_flip_h = data.get("sprite_flip_h", false)
	snap.anim_name = data.get("anim_name", "")
	snap.anim_position = data.get("anim_position", 0.0)
	return snap

func _capture_timer(store: Dictionary, owner: Node, name: String) -> void:
	if not owner.has_node(name):
		return
	var t: Timer = owner.get_node(name)
	store[name] = t.time_left

func _restore_timer(store: Dictionary, owner: Node, name: String) -> void:
	if not owner.has_node(name):
		return
	if not store.has(name):
		return
	var t: Timer = owner.get_node(name)
	var time_left: float = store[name]
	var configured_wait := t.wait_time  # Timer.start(n) sets wait_time=n, corrupting future start() calls
	t.stop()
	if time_left > 0:
		t.start(time_left)
		t.wait_time = configured_wait  # restore so jump_timer.start() etc. use the scene-configured timeout
