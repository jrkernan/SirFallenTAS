extends Node

const TAS_DEFAULT_PATH := "user://tas/SirFallen.tas"
const MAX_SPEED := 9

var controller := TASInputController.new()
var snapshots: Array[TASSnapshot] = []
var enabled := false
var frame_step := false
var pending_step_once := false
var speed := 1
var current_actions: Array[bool] = []
var current_pressed: Array[bool] = []
var current_released: Array[bool] = []
var status_text := ""

var _prev_keys := {}
var _last_time_scale := 1.0
var _last_actions: Array[bool] = []
var _paused_by_tas := false
var _prev_tree_paused := false
var _step_unpause := false
var _prev_timer_on := false

func _ready():
	process_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS
	controller.file_path = TAS_DEFAULT_PATH
	controller.reload_from_disk()
	controller.initialize_playback()
	set_physics_process(true)
	_create_overlay()

func _physics_process(_delta: float) -> void:
	_update_hotkeys()
	if not enabled:
		status_text = ""
		_set_time_scale(1.0)
		_update_overlay()
		return

	if frame_step:
		if _step_unpause:
			_tick()
			_step_unpause = false
			pending_step_once = false
			_pause_tree_for_frame_step()
			_update_overlay()
			return
		if pending_step_once:
			_step_unpause = true
			_resume_tree_from_frame_step()
			_update_overlay()
			return
		_set_time_scale(1.0)
		_update_overlay()
		return

	_resume_tree_from_frame_step()

	_apply_speed()

	_tick()

	if pending_step_once:
		pending_step_once = false

	_update_overlay()

func _tick() -> void:
	if not controller.can_playback():
		_disable()
		return

	current_actions = controller.current_actions()
	current_pressed = _calc_pressed(current_actions, _last_actions)
	current_released = _calc_released(current_actions, _last_actions)
	_last_actions = current_actions.duplicate()

	_capture_snapshot()

	controller.playback_tick()

	if controller.current != null:
		status_text = "Line %d (%d)" % [controller.current.line_number, controller.current_frame]

	if controller.current != null and controller.current.fast_forward and controller.current.force_break:
		frame_step = true
		speed = 1
		_set_time_scale(1.0)

func _capture_snapshot() -> void:
	var p = _get_player()
	if p == null:
		return
	var snap := TASSnapshot.new()
	snap.capture(p)
	snapshots.append(snap)

func _step_back() -> void:
	if snapshots.size() < 2:
		return
	snapshots.pop_back() # drop current frame
	var snap: TASSnapshot = snapshots.pop_back()
	var frame_number := snapshots.size() + 1
	controller.reload_playback_at(frame_number)
	var p = _get_player()
	if p != null:
		snap.apply(p)
	if _paused_by_tas and GlobalTimer != null:
		GlobalTimer.timer_on = false
	if controller.current != null:
		status_text = "Line %d (%d)" % [controller.current.line_number, controller.current_frame]
	_update_overlay()
	snapshots.append(snap)
	frame_step = true
	speed = 1
	_set_time_scale(1.0)
	_last_actions = []

func _toggle_enable() -> void:
	if enabled:
		_disable()
	else:
		_enable()

func _enable() -> void:
	enabled = true
	frame_step = false
	pending_step_once = false
	speed = 1
	snapshots.clear()
	controller.initialize_playback()
	_last_actions = []
	status_text = "TAS ON"

func _disable() -> void:
	enabled = false
	frame_step = false
	pending_step_once = false
	speed = 1
	_set_time_scale(1.0)
	snapshots.clear()
	_last_actions = []
	status_text = "TAS OFF"
	_resume_tree_from_frame_step()

func _reload_file() -> void:
	controller.reload_from_disk()
	controller.initialize_playback()
	snapshots.clear()
	_last_actions = []
	status_text = "Reloaded"

func get_action(action: int) -> bool:
	if not enabled or current_actions.is_empty():
		return false
	if action < 0 or action >= current_actions.size():
		return false
	return current_actions[action]

func get_pressed(action: int) -> bool:
	if not enabled or current_pressed.is_empty():
		return false
	if action < 0 or action >= current_pressed.size():
		return false
	return current_pressed[action]

func get_released(action: int) -> bool:
	if not enabled or current_released.is_empty():
		return false
	if action < 0 or action >= current_released.size():
		return false
	return current_released[action]

func get_axis(left_action: int, right_action: int) -> float:
	var axis := 0
	if get_action(left_action):
		axis -= 1
	if get_action(right_action):
		axis += 1
	return float(axis)

func _get_player() -> Node:
	var root = get_tree().current_scene
	if root == null:
		return null
	if root.has_node("player"):
		return root.get_node("player")
	var nodes = get_tree().get_nodes_in_group("player")
	if nodes.size() > 0:
		return nodes[0]
	return null

func _just_pressed(code: int) -> bool:
	var now := Input.is_physical_key_pressed(code)
	var was := _prev_keys.get(code, false)
	_prev_keys[code] = now
	return now and not was

func _update_hotkeys() -> void:
	if _just_pressed(KEY_F6):
		_toggle_enable()
	if _just_pressed(KEY_F7):
		frame_step = not frame_step
		if frame_step:
			speed = 1
			pending_step_once = false
			_pause_tree_for_frame_step()
		else:
			_resume_tree_from_frame_step()
	if _just_pressed(KEY_PERIOD):
		if frame_step:
			pending_step_once = true
	if _just_pressed(KEY_COMMA):
		_step_back()
	if _just_pressed(KEY_F5):
		_reload_file()
	if _just_pressed(KEY_EQUAL):
		speed = clampi(speed + 1, 1, MAX_SPEED)
	if _just_pressed(KEY_MINUS):
		speed = clampi(speed - 1, 1, MAX_SPEED)

func _create_overlay():
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	_overlay = Label.new()
	_overlay.name = "TASOverlay"
	_overlay.modulate = Color.WHITE
	_overlay.add_theme_color_override("font_color", Color.WHITE)
	_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	_overlay.add_theme_constant_override("outline_size", 2)
	_overlay.text = "TAS"
	_overlay.position = Vector2(16, 16)
	canvas.add_child(_overlay)
	add_child(canvas)

func _update_overlay():
	if _overlay == null:
		return
	var lines: PackedStringArray = []
	lines.append("TAS: ON" if enabled else "TAS: OFF")
	if enabled:
		lines.append("Mode: FrameStep" if frame_step else "Mode: Play")
		lines.append("Speed: x%d" % speed)
		if status_text != "":
			lines.append(status_text)
	_overlay.text = "\n".join(lines)

var _overlay: Label

func _apply_speed() -> void:
	if frame_step:
		_set_time_scale(1.0)
		return
	if controller.has_fast_forward():
		var ff := float(controller.fast_forward_speed())
		_set_time_scale(clampf(ff, 1.0, 100.0))
		return
	_set_time_scale(float(clampi(speed, 1, MAX_SPEED)))

func _set_time_scale(val: float) -> void:
	if abs(_last_time_scale - val) > 0.0001:
		Engine.time_scale = val
		_last_time_scale = val

func _pause_tree_for_frame_step() -> void:
	if _paused_by_tas:
		return
	var tree = get_tree()
	_prev_tree_paused = tree.paused
	tree.paused = true
	_paused_by_tas = true
	if GlobalTimer != null:
		_prev_timer_on = GlobalTimer.timer_on
		GlobalTimer.timer_on = false

func _resume_tree_from_frame_step() -> void:
	if not _paused_by_tas:
		return
	var tree = get_tree()
	tree.paused = _prev_tree_paused
	_paused_by_tas = false
	if GlobalTimer != null:
		GlobalTimer.timer_on = _prev_timer_on

func _calc_pressed(current: Array[bool], previous: Array[bool]) -> Array[bool]:
	if current.is_empty():
		return []
	var pressed: Array[bool] = []
	pressed.resize(TASInputRecord.Actions.size())
	for i in range(pressed.size()):
		var prev_val := false
		if i < previous.size():
			prev_val = previous[i]
		pressed[i] = (not prev_val) and current[i]
	return pressed

func _calc_released(current: Array[bool], previous: Array[bool]) -> Array[bool]:
	if previous.is_empty():
		var none: Array[bool] = []
		none.resize(TASInputRecord.Actions.size())
		return none
	var released: Array[bool] = []
	released.resize(TASInputRecord.Actions.size())
	for i in range(released.size()):
		var cur_val := false
		if i < current.size():
			cur_val = current[i]
		released[i] = previous[i] and (not cur_val)
	return released
