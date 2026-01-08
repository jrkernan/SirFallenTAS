extends Node
class_name TASSnapshot

## Minimal snapshot of player state for one-frame step-back
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
var global_time: float
var global_timer_on: bool
var timers: Dictionary = {}

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
	if GlobalTimer != null:
		global_time = GlobalTimer.time
		global_timer_on = GlobalTimer.timer_on

	_capture_timer(timers, player, "coyote_jump_timer")
	_capture_timer(timers, player, "coyote_wall_timer")
	_capture_timer(timers, player, "jump_timer")
	_capture_timer(timers, player, "jump_buffer_timer")
	_capture_timer(timers, player, "b_hop_timer")
	_capture_timer(timers, player, "drop_timer")

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
	if GlobalTimer != null:
		GlobalTimer.time = global_time
		GlobalTimer.timer_on = global_timer_on

	_restore_timer(timers, player, "coyote_jump_timer")
	_restore_timer(timers, player, "coyote_wall_timer")
	_restore_timer(timers, player, "jump_timer")
	_restore_timer(timers, player, "jump_buffer_timer")
	_restore_timer(timers, player, "b_hop_timer")
	_restore_timer(timers, player, "drop_timer")

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
	t.stop()
	if time_left > 0:
		t.start(time_left)
