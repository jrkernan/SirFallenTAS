extends Node

const TAS_BASE_DIR := "res://tas"
const MAX_SPEED := 9
const HOLD_STEP_DELAY := 0.50
const HOLD_STEP_INTERVAL := 0.05
const NEW_MOVIE_LABEL := "[ New Movie ]"
const FADE_IN_DURATION := 0.25
const FADE_OUT_DURATION := 0.20

enum TASMode {
	IDLE,
	PLAYBACK,
	RECORD,
}

const SNAPSHOT_BUFFER_SIZE := 600
const AUTOSAVE_INTERVAL := 300

var controller := TASInputController.new()
var snapshots: Array[TASSnapshot] = []
var _snapshot_frames: Array[int] = []
var enabled := false
var frame_step := false
var speed := 1
var current_actions: Array[bool] = []
var current_pressed: Array[bool] = []
var current_released: Array[bool] = []
var status_text := ""

var _prev_keys := {}
var _last_time_scale := 1.0
var _base_physics_fps: int = 60
var _last_actions: Array[bool] = []
var _paused_by_tas := false
var _prev_tree_paused := false
var _step_unpause := false
var _prev_timer_on := false
var _pending_steps := 0
var _hold_step_timer := 0.0
var _step_back_cooldown := 0.0
var _autosave_counter := 0
var _backup_made := false

var mode: TASMode = TASMode.IDLE
var movie_base_name := "SirFallen"
var movie_path := ""
var current_frame := 0
var movie_length := 0
var record_frames: Array = []
var save_slots: Array = []

var _picker_active := false
var _picker_items: Array[String] = []
var _picker_index := 0
var _awaiting_scene_reset := false
var _reload_called := false 
var _post_reset_resume := false     
var _post_reset_idle := false       
var _record_confirm_pending := false  # true = waiting for second R press to confirm file overwrite
var _record_pending_trim := false     # true = first frame step after save state load must trim and invalidate
var _current_state_slot: int = -1    
var _camera_snap_pending := false   
var _camera_smooth_reenable := false
var _overlay: Label
var _picker_label: Label
var _black_overlay: ColorRect
var _speed_overlay: Label
var _fade_tween: Tween = null

func _ready():
	process_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_base_physics_fps = Engine.physics_ticks_per_second
	DirAccess.make_dir_recursive_absolute(TAS_BASE_DIR)
	movie_base_name = "SirFallen"
	movie_path = _movie_file_path()
	save_slots.resize(5)
	set_physics_process(true)
	_create_overlay()

# If the game quits, write to the movie file
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		if mode == TASMode.RECORD and record_frames.size() > 0:
			_write_movie_file()

# --- Movie Helper Functions ---

func _movie_folder() -> String:
	return "%s/%s" % [TAS_BASE_DIR, movie_base_name]

func _movie_file_path() -> String:
	return "%s/%s/%s.tas" % [TAS_BASE_DIR, movie_base_name, movie_base_name]

func _states_path() -> String:
	if movie_base_name == "":
		return ""
	return "%s/%s/states.json" % [TAS_BASE_DIR, movie_base_name]

func _backups_dir() -> String:
	return "%s/%s/backups" % [TAS_BASE_DIR, movie_base_name]

func _ensure_movie_dir() -> void:
	DirAccess.make_dir_recursive_absolute(_movie_folder())
	DirAccess.make_dir_recursive_absolute(_backups_dir())

func _list_movie_names() -> Array[String]:
	var names: Array[String] = []
	var dir = DirAccess.open(TAS_BASE_DIR)
	if dir == null:
		return names
	dir.list_dir_begin()
	while true:
		var entry = dir.get_next()
		if entry == "":
			break
		if dir.current_is_dir() and not entry.begins_with("."):
			if FileAccess.file_exists("%s/%s/%s.tas" % [TAS_BASE_DIR, entry, entry]):
				names.append(entry)
	dir.list_dir_end()
	names.sort()
	return names

func _select_movie(name: String) -> void:
	movie_base_name = name
	movie_path = _movie_file_path()

# --- Physics ---

func _physics_process(delta: float) -> void:
	_update_speed_overlay()
	if _awaiting_scene_reset:
		_check_scene_reset()
		_update_overlay()
		return
	_update_hotkeys()
	if not enabled:
		status_text = ""
		_set_time_scale(1.0)
		_update_overlay()
		return

	_update_hold_step(delta)

	if mode == TASMode.RECORD or mode == TASMode.PLAYBACK:
		if frame_step:
			_process_frame_step()
			return
		_resume_tree_from_frame_step() # To catch the tick immediately after you switch out of frame step
		_apply_speed()
		_tick()
		_update_overlay()
	else:
		current_actions = []
		current_pressed = []
		current_released = []
		_last_actions = []
		_update_overlay()

func _process_frame_step() -> void:
	if _step_unpause:
		_record_confirm_pending = false
		_tick()
		_step_unpause = false
		_pending_steps = max(0, _pending_steps - 1)
		_pause_tree_for_frame_step()
		_update_overlay()
		return
	if _pending_steps > 0:
		_step_unpause = true
		_resume_tree_from_frame_step()
		_update_overlay()
		return
	# Nothing queued. Re-pause in case something external unpaused the tree (e.g. respawn sequence) between the last tick+pause frame and now
	_pause_tree_for_frame_step()
	_set_time_scale(1.0)
	_update_overlay()

func _tick() -> void:
	if mode == TASMode.PLAYBACK:
		if not controller.can_playback() or current_frame >= movie_length:
			frame_step = true
			speed = 1
			_pending_steps = 0
			current_actions = []
			current_pressed = []
			current_released = []
			_last_actions = []
			_set_time_scale(1.0)
			_pause_tree_for_frame_step()
			status_text = "Playback done. Frame %d" % current_frame
			_update_overlay()
			return
		current_actions = controller.current_actions()
		current_pressed = _calc_pressed(current_actions, _last_actions)
		current_released = _calc_released(current_actions, _last_actions)
		_last_actions = current_actions.duplicate()
		_capture_snapshot()
		_fire_event_driven_actions()
		controller.playback_tick()
		current_frame = controller.current_frame
		if controller.current != null:
			status_text = "Line %d (%d)" % [controller.current.line_number, controller.current_frame]
		return

	if mode == TASMode.RECORD:
		var live_actions = _capture_live_actions()
		current_actions = live_actions
		current_pressed = _calc_pressed(current_actions, _last_actions)
		current_released = _calc_released(current_actions, _last_actions)
		_last_actions = current_actions.duplicate()
		_capture_snapshot()
		_fire_event_driven_actions()
		if _record_pending_trim:
			_record_pending_trim = false
			_current_state_slot = -1
			_trim_record_frames(current_frame)
			movie_length = record_frames.size()
			var slots_changed := false
			for i in range(save_slots.size()):
				if save_slots[i] != null and save_slots[i]["frame"] > current_frame:
					save_slots[i] = null
					slots_changed = true
			if slots_changed:
				_write_states_file()
				_update_overlay()
		_record_frame(live_actions)
		if _current_state_slot >= 0:
			status_text = "Rec Frame %d (State %d)" % [current_frame, _current_state_slot + 1]
		else:
			status_text = "Rec Frame %d" % current_frame
		current_frame += 1
		movie_length = max(movie_length, current_frame)
		_autosave_counter += 1
		if _autosave_counter >= AUTOSAVE_INTERVAL:
			_autosave_counter = 0
			_write_movie_file()

func _fire_event_driven_actions() -> void:
	# Some game systems (e.g. interactions) use _input(event) rather than polling.
	# Synthetic events ensure those handlers see the correct pressed state, which
	# _input() alone cannot because it fires before _physics_process sets current_pressed.
	# The paired release event resets Godot's internal action state so the next press
	# registers as a genuine new transition (without it Godot treats re-fires as echo)
	if current_pressed.size() > TASInputRecord.Actions.ACTION and current_pressed[TASInputRecord.Actions.ACTION]:
		var ev_on := InputEventAction.new()
		ev_on.action = "action"
		ev_on.pressed = true
		Input.parse_input_event(ev_on)
		var ev_off := InputEventAction.new()
		ev_off.action = "action"
		ev_off.pressed = false
		Input.parse_input_event(ev_off)
	if current_pressed.size() > TASInputRecord.Actions.PAUSE and current_pressed[TASInputRecord.Actions.PAUSE]:
		var ev_on := InputEventAction.new()
		ev_on.action = "pause"
		ev_on.pressed = true
		Input.parse_input_event(ev_on)
		var ev_off := InputEventAction.new()
		ev_off.action = "pause"
		ev_off.pressed = false
		Input.parse_input_event(ev_off)
	if current_pressed.size() > TASInputRecord.Actions.RESET_PLATFORMS and current_pressed[TASInputRecord.Actions.RESET_PLATFORMS]:
		var ev_on := InputEventAction.new()
		ev_on.action = "reset_platforms"
		ev_on.pressed = true
		Input.parse_input_event(ev_on)
		var ev_off := InputEventAction.new()
		ev_off.action = "reset_platforms"
		ev_off.pressed = false
		Input.parse_input_event(ev_off)

func _capture_snapshot() -> void:
	var p = _get_player()
	if p == null:
		return
	var snap := TASSnapshot.new()
	snap.capture(p)
	_capture_platforms(snap)
	_capture_level(snap)
	if snapshots.size() >= SNAPSHOT_BUFFER_SIZE:
		snapshots.pop_front()
		_snapshot_frames.pop_front()
	snapshots.append(snap)
	_snapshot_frames.append(current_frame)

func _step_back() -> void:
	if snapshots.size() < 2:
		return
	snapshots.pop_back()
	_snapshot_frames.pop_back()
	var snap: TASSnapshot = snapshots.pop_back()
	var frame_number: int = _snapshot_frames.pop_back()
	var p = _get_player()
	if p != null:
		snap.apply(p)
	_apply_platforms(snap)
	_apply_level(snap)
	if _paused_by_tas and GlobalTimer != null:
		_prev_timer_on = snap.global_timer_on
		GlobalTimer.timer_on = false

	if mode == TASMode.PLAYBACK:
		controller.reload_playback_at(frame_number)
		current_frame = controller.current_frame
		if controller.current != null:
			status_text = "Line %d (%d)" % [controller.current.line_number, controller.current_frame]
	elif mode == TASMode.RECORD:
		current_frame = frame_number
		_trim_record_frames(current_frame)
		movie_length = record_frames.size()
		status_text = "Rec Frame %d" % current_frame
	else:
		current_frame = frame_number
		status_text = "Frame %d" % current_frame

	_update_overlay()
	snapshots.append(snap)
	_snapshot_frames.append(frame_number)
	frame_step = true
	speed = 1
	_pending_steps = 0
	_set_time_scale(1.0)
	_last_actions = []
	_pause_tree_for_frame_step()

# --- Enable, Disable and Movie Picker ---

func _show_picker(names: Array[String]) -> void:
	_picker_active = true
	_picker_items = names.duplicate()
	_picker_items.append(NEW_MOVIE_LABEL)
	var idx = _picker_items.find(movie_base_name)
	_picker_index = max(0, idx)
	_snapshot_key_states()
	_update_picker_overlay()

func _hide_picker() -> void:
	_picker_active = false
	_update_picker_overlay()

func _confirm_picker() -> void:
	var selected = _picker_items[_picker_index]
	_hide_picker()
	if selected == NEW_MOVIE_LABEL:
		_create_new_movie()
	else:
		_select_movie(selected)
		_enable()

func _create_new_movie() -> void:
	var now = Time.get_datetime_dict_from_system()
	var base = "Run_%04d%02d%02d" % [now.year, now.month, now.day]
	var name = base
	var existing = _list_movie_names()
	var counter := 2
	while existing.has(name):
		name = "%s_%d" % [base, counter]
		counter += 1
	_select_movie(name)
	_ensure_movie_dir()
	_enable()

func _enable() -> void:
	Engine.max_physics_steps_per_frame = MAX_SPEED * 4
	_snapshot_key_states()
	enabled = true
	_backup_made = false
	speed = 1
	snapshots.clear()
	_snapshot_frames.clear()
	_last_actions = []
	_pending_steps = 0
	_post_reset_resume = true  # after reset: initialize movie at frame 0
	_reset_scene()

func _reset_scene() -> void:
	if mode == TASMode.RECORD and record_frames.size() > 0:
		_write_movie_file()
	if _paused_by_tas:
		_resume_tree_from_frame_step()
	_paused_by_tas = false
	_set_time_scale(1.0)
	_awaiting_scene_reset = true
	_reload_called = false
	status_text = "Resetting..."
	_start_fade_in()
	# Freeze physics and timer for the duration of the fade
	get_tree().paused = true
	if GlobalTimer != null:
		GlobalTimer.timer_on = false

func _start_fade_in() -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	if _black_overlay == null:
		# No overlay: reset and reload immediately
		Stats.reset_run()
		_reload_called = true
		get_tree().reload_current_scene()
		return
	_black_overlay.modulate.a = 0.0
	_black_overlay.visible = true
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_black_overlay, "modulate:a", 1.0, FADE_IN_DURATION)
	# Stats.reset_run() and reload happen here in the idle frame after physics, so the level's save_current_run() cannot overwrite the reset before reload fires
	_fade_tween.tween_callback(func():
		Stats.reset_run()
		_reload_called = true
		get_tree().reload_current_scene()
	)

func _start_fade_out() -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	if _black_overlay == null:
		return
	_black_overlay.modulate.a = 1.0
	_black_overlay.visible = true
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_black_overlay, "modulate:a", 0.0, FADE_OUT_DURATION)
	_fade_tween.tween_callback(func(): _black_overlay.visible = false)

func _check_scene_reset() -> void:
	if not _reload_called:
		return  # Fade still in progress; reload not triggered yet
	if _get_player() == null:
		return  # New scene not ready yet
	_reload_called = false
	_awaiting_scene_reset = false
	get_tree().paused = false
	_paused_by_tas = false
	if not enabled:
		_start_fade_out()
		return
	if _post_reset_idle:
		_post_reset_idle = false
		_start_fade_out()
		_complete_idle_reset()
	elif _post_reset_resume:
		_post_reset_resume = false
		_complete_enable()  # decides whether/when to fade out
	else:
		_start_fade_out()
		_start_playback()

func _complete_enable() -> void:
	_load_states_file()
	_start_fade_out()
	frame_step = true
	current_frame = 0
	movie_length = 0
	controller.file_path = _movie_file_path()
	if controller.reload_from_disk():
		movie_length = _calculate_movie_length(controller.records)
	else:
		# Create empty .tas so this movie appears in future picker listings
		_ensure_movie_dir()
		var fh = FileAccess.open(_movie_file_path(), FileAccess.WRITE)
		if fh != null:
			fh.close()
	_pause_tree_for_frame_step()
	status_text = "Press R to record" if movie_length == 0 else "Ready. Press O to play"
	_update_overlay()

func _complete_idle_reset() -> void:
	_record_confirm_pending = false
	mode = TASMode.IDLE
	frame_step = true
	current_frame = 0
	movie_length = 0
	record_frames.clear()
	snapshots.clear()
	_snapshot_frames.clear()
	_last_actions = []
	controller.file_path = _movie_file_path()
	if controller.reload_from_disk():
		movie_length = _calculate_movie_length(controller.records)
	_load_states_file()
	_pause_tree_for_frame_step()
	status_text = "Press R to record" if movie_length == 0 else "Ready. Press O to play"
	_update_overlay()

func _disable() -> void:
	if mode == TASMode.RECORD and record_frames.size() > 0:
		_write_movie_file()
	enabled = false
	frame_step = false
	speed = 1
	_awaiting_scene_reset = false
	_reload_called = false
	_post_reset_idle = false
	_record_confirm_pending = false
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
	if _black_overlay != null:
		_black_overlay.visible = false
		_black_overlay.modulate.a = 1.0
	_set_time_scale(1.0)
	snapshots.clear()
	_snapshot_frames.clear()
	_last_actions = []
	_pending_steps = 0
	Engine.max_physics_steps_per_frame = 8
	mode = TASMode.IDLE
	status_text = "TAS OFF"
	_resume_tree_from_frame_step()
	# If the tree ended up paused by an outside system (e.g. pause triggered by a conflicting key) and TAS isn't tracking it, force unpause
	if not _paused_by_tas and get_tree().paused:
		get_tree().paused = false
		if GlobalTimer != null:
			GlobalTimer.timer_on = true

# --- Playback ---

func _start_playback() -> void:
	_record_confirm_pending = false
	controller.file_path = _movie_file_path()
	if not controller.reload_from_disk():
		status_text = "No movie to play"
		mode = TASMode.IDLE
		return
	controller.initialize_playback()
	_load_states_file()
	movie_length = _calculate_movie_length(controller.records)
	current_frame = 0
	snapshots.clear()
	_snapshot_frames.clear()
	_last_actions = []
	frame_step = false
	_pending_steps = 0
	mode = TASMode.PLAYBACK
	status_text = "Playback"

# --- Recording ---

func _start_record() -> void:
	_record_confirm_pending = false
	_record_pending_trim = false
	_autosave_counter = 0
	_ensure_movie_dir()
	movie_path = _movie_file_path()

	if FileAccess.file_exists(movie_path):
		if not _backup_made:
			_make_backup()
			_backup_made = true
		var frames = _load_movie_frames(movie_path)
		var start_frame := current_frame
		if mode == TASMode.PLAYBACK:
			start_frame = controller.current_frame
		start_frame = clampi(start_frame, 0, frames.size())
		record_frames = frames
		_trim_record_frames(start_frame)
		current_frame = start_frame
		movie_length = record_frames.size()
		_write_movie_file()
	else:
		record_frames.clear()
		current_frame = 0
		movie_length = 0
		_write_movie_file()

	mode = TASMode.RECORD
	frame_step = true
	_pending_steps = 0
	snapshots.clear()
	_snapshot_frames.clear()
	_last_actions = []
	_pause_tree_for_frame_step()
	status_text = "Recording"
	# Only invalidate save state slots past the updated start frame
	var slots_changed := false
	for i in range(save_slots.size()):
		if save_slots[i] != null and save_slots[i]["frame"] > current_frame:
			save_slots[i] = null
			slots_changed = true
	if slots_changed:
		_write_states_file()

func _stop_record() -> void:
	_record_pending_trim = false
	_autosave_counter = 0
	_write_movie_file()
	mode = TASMode.IDLE
	frame_step = true
	current_actions = []
	current_pressed = []
	current_released = []
	_last_actions = []
	_pending_steps = 0
	_set_time_scale(1.0)
	_pause_tree_for_frame_step()
	status_text = "Recording stopped. Frame %d" % current_frame

func _stop_record_and_start_playback() -> void:
	_record_confirm_pending = false
	_record_pending_trim = false
	_autosave_counter = 0
	_write_movie_file()
	controller.file_path = _movie_file_path()
	if not controller.reload_from_disk():
		status_text = "Nothing recorded yet"
		_update_overlay()
		return  # Stay in RECORD mode
	movie_length = _calculate_movie_length(controller.records)
	var target_frame := current_frame
	controller.reload_playback_at(target_frame)
	current_frame = controller.current_frame
	record_frames.clear()
	snapshots.clear()
	_snapshot_frames.clear()
	_last_actions = []
	frame_step = true
	speed = 1
	_pending_steps = 0
	_pause_tree_for_frame_step()
	mode = TASMode.PLAYBACK
	if current_frame >= movie_length:
		status_text = "Playback done. Press Shift+O to restart."
	else:
		status_text = "Playback @ frame %d" % current_frame
	_update_overlay()

# --- Backup ---

func _make_backup() -> void:
	var src = _movie_file_path()
	if not FileAccess.file_exists(src):
		return
	var now = Time.get_datetime_dict_from_system()
	var stamp = "%04d%02d%02d_%02d%02d%02d" % [now.year, now.month, now.day, now.hour, now.minute, now.second]
	var dst = "%s/%s.tas" % [_backups_dir(), stamp]
	var content = FileAccess.get_file_as_string(src)
	var fh = FileAccess.open(dst, FileAccess.WRITE)
	if fh != null:
		fh.store_string(content)
		fh.close()

# --- Save states ---

func _save_state(slot: int) -> void:
	if slot < 0 or slot >= save_slots.size():
		return
	if mode == TASMode.IDLE:
		return
	var p = _get_player()
	if p == null:
		return
	var snap := TASSnapshot.new()
	snap.capture(p)
	_capture_platforms(snap)
	_capture_level(snap)
	save_slots[slot] = {"frame": current_frame, "snap": snap}
	status_text = "Saved S%d @ %d" % [slot + 1, current_frame]
	_write_states_file()
	_update_overlay()

func _load_state(slot: int) -> void:
	if slot < 0 or slot >= save_slots.size():
		return
	if mode == TASMode.IDLE:
		return
	var data = save_slots[slot]
	if data == null:
		status_text = "Empty S%d" % [slot + 1]
		_update_overlay()
		return
	var snap: TASSnapshot = data["snap"]
	var frame: int = data["frame"]
	var p = _get_player()
	if p != null:
		snap.apply(p)
		_camera_snap_pending = true
	_apply_platforms(snap)
	_apply_level(snap)
	if _paused_by_tas and GlobalTimer != null:
		_prev_timer_on = snap.global_timer_on
		GlobalTimer.timer_on = false
	snapshots.clear()
	_snapshot_frames.clear()
	_record_confirm_pending = false
	current_frame = frame

	if mode == TASMode.PLAYBACK:
		# Get the controller to the save state frame and pause so you can decide to keep playing or switch to record
		controller.reload_playback_at(frame)
		frame_step = true
		speed = 1
		_pending_steps = 0
		_pause_tree_for_frame_step()
		_last_actions = []
		status_text = "State %d @ frame %d" % [slot + 1, frame]
	else:
		# RECORD: write recording, then switch to PLAYBACK at the save state frame.
		# To record from here the user must press R, which requires a second confirmation
		# if it would erase existing frames — that's the intentional gate.
		_write_movie_file()
		controller.file_path = _movie_file_path()
		if controller.reload_from_disk():
			movie_length = _calculate_movie_length(controller.records)
		controller.reload_playback_at(frame)
		current_frame = controller.current_frame
		record_frames.clear()
		_record_pending_trim = false
		_record_confirm_pending = false
		_current_state_slot = slot
		frame_step = true
		speed = 1
		_pending_steps = 0
		_pause_tree_for_frame_step()
		_last_actions = []
		mode = TASMode.PLAYBACK
		status_text = "State %d @ frame %d — Playback (R to record from here)" % [slot + 1, frame]
	_update_overlay()

# --- Public input helpers ---

# Used internally but they're also the bridge in player.gd

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

# --- Player / platform lookup ---

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

func _capture_platforms(snap: TASSnapshot) -> void:
	snap.platform_times.clear()
	for platform in get_tree().get_nodes_in_group("tas_moving_platform"):
		snap.platform_times[str(platform.get_path())] = platform.time

func _apply_platforms(snap: TASSnapshot) -> void:
	for path_str in snap.platform_times:
		var platform = get_node_or_null(path_str)
		if platform != null:
			platform.time = snap.platform_times[path_str]

func _capture_level(snap: TASSnapshot) -> void:
	var level = get_tree().current_scene
	if level == null:
		return
	if "spawn_point" in level:
		snap.spawn_point = level.spawn_point
	snap.active_checkpoint = str(level.active_checkpoint) if "active_checkpoint" in level and level.active_checkpoint != null else ""

func _apply_level(snap: TASSnapshot) -> void:
	var level = get_tree().current_scene
	if level == null:
		return
	if "spawn_point" in level:
		level.spawn_point = snap.spawn_point
	if "active_checkpoint" in level:
		level.active_checkpoint = snap.active_checkpoint if snap.active_checkpoint != "" else null

# --- Hotkeys ---

func _just_pressed(code: int) -> bool:
	var now := Input.is_physical_key_pressed(code)
	var was := _prev_keys.get(code, false)
	_prev_keys[code] = now
	return now and not was

func _snapshot_key_states() -> void:
	# Populate _prev_keys with current physical state so no held key appears as "just pressed" on the next frame after a state transition
	for code in [KEY_T, KEY_O, KEY_R, KEY_K, KEY_PERIOD,
			KEY_COMMA, KEY_EQUAL, KEY_MINUS,
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5,
			KEY_UP, KEY_DOWN, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		_prev_keys[code] = Input.is_physical_key_pressed(code)

func _update_hotkeys() -> void:
	var shift_down = Input.is_physical_key_pressed(KEY_SHIFT)

	if _just_pressed(KEY_T):
		if enabled:
			_disable()
		elif _picker_active:
			_hide_picker()
		else:
			_show_picker(_list_movie_names())
		return

	if _picker_active:
		if _just_pressed(KEY_UP):
			_picker_index = (_picker_index - 1 + _picker_items.size()) % _picker_items.size()
			_update_picker_overlay()
		if _just_pressed(KEY_DOWN):
			_picker_index = (_picker_index + 1) % _picker_items.size()
			_update_picker_overlay()
		if _just_pressed(KEY_ENTER):
			_confirm_picker()
		if _just_pressed(KEY_KP_ENTER):
			_confirm_picker()
		if _just_pressed(KEY_ESCAPE):
			_hide_picker()
		return

	if not enabled:
		return

	if _just_pressed(KEY_O):
		_record_confirm_pending = false
		if shift_down:
			_post_reset_idle = true
			_reset_scene()
		elif mode == TASMode.PLAYBACK:
			if not controller.can_playback() or current_frame >= movie_length:
				status_text = "Playback done. Press Shift+O to restart."
				_update_overlay()
				return
			# Toggle play/pause
			frame_step = not frame_step
			if frame_step:
				speed = 1
				_pending_steps = 0
				_pause_tree_for_frame_step()
			else:
				_resume_tree_from_frame_step()
		elif mode == TASMode.RECORD:
			_stop_record_and_start_playback()
		elif mode == TASMode.IDLE:
			if current_frame == 0 and snapshots.is_empty():
				# Already reset. Skip the reload and just play 
				_start_playback()
			else:
				# Not at a clean state. Reset to frame 0 and freeze
				_post_reset_idle = true
				_reset_scene()
	if _just_pressed(KEY_R):
		if mode == TASMode.RECORD:
			_record_confirm_pending = false
			_stop_record()
		elif _record_confirm_pending:
			_record_confirm_pending = false
			_start_record()
		elif current_frame < movie_length:
			# Would erase frames, get confirmation
			_record_confirm_pending = true
			if mode == TASMode.PLAYBACK:
				frame_step = true
				speed = 1
				_pending_steps = 0
				_pause_tree_for_frame_step()
			_update_overlay()
		else:
			_start_record()
	if _just_pressed(KEY_K):
		frame_step = not frame_step
		if frame_step:
			speed = 1
			_pending_steps = 0
			_pause_tree_for_frame_step()
		else:
			_resume_tree_from_frame_step()
	if _just_pressed(KEY_PERIOD):
		if frame_step and (mode != TASMode.PLAYBACK or (controller.can_playback() and current_frame < movie_length)):
			_queue_step(1)
	if _just_pressed(KEY_COMMA):
		if _step_back_cooldown <= 0:
			_step_back()
			_step_back_cooldown = 0.08
	if _just_pressed(KEY_EQUAL):
		speed = clampi(speed + 1, 1, MAX_SPEED)
	if _just_pressed(KEY_MINUS):
		speed = clampi(speed - 1, 1, MAX_SPEED)

	if _just_pressed(KEY_1):
		if shift_down: _save_state(0)
		else: _load_state(0)
	if _just_pressed(KEY_2):
		if shift_down: _save_state(1)
		else: _load_state(1)
	if _just_pressed(KEY_3):
		if shift_down: _save_state(2)
		else: _load_state(2)
	if _just_pressed(KEY_4):
		if shift_down: _save_state(3)
		else: _load_state(3)
	if _just_pressed(KEY_5):
		if shift_down: _save_state(4)
		else: _load_state(4)

func _update_hold_step(delta: float) -> void:
	if _step_back_cooldown > 0:
		_step_back_cooldown = maxf(0.0, _step_back_cooldown - delta)
	if not enabled or not frame_step or (mode == TASMode.PLAYBACK and (not controller.can_playback() or current_frame >= movie_length)):
		_hold_step_timer = 0.0
		return
	if Input.is_physical_key_pressed(KEY_PERIOD):
		_hold_step_timer += delta
		if _hold_step_timer >= HOLD_STEP_DELAY:
			var over := _hold_step_timer - HOLD_STEP_DELAY
			var steps := 1 + int(over / HOLD_STEP_INTERVAL)
			_hold_step_timer = HOLD_STEP_DELAY + fmod(over, HOLD_STEP_INTERVAL)
			_queue_step(steps)
	else:
		if _hold_step_timer >= HOLD_STEP_DELAY:
			_pending_steps = 0
		_hold_step_timer = 0.0

func _queue_step(count: int) -> void:
	if not frame_step:
		return
	_pending_steps += count

# --- Overlay ---

func _create_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100

	_overlay = Label.new()
	_overlay.name = "TASOverlay"
	_overlay.add_theme_color_override("font_color", Color.WHITE)
	_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	_overlay.add_theme_constant_override("outline_size", 2)
	_overlay.position = Vector2(16, 16)
	canvas.add_child(_overlay)

	_picker_label = Label.new()
	_picker_label.name = "TASPicker"
	_picker_label.add_theme_color_override("font_color", Color.YELLOW)
	_picker_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_picker_label.add_theme_constant_override("outline_size", 3)
	_picker_label.visible = false
	_picker_label.position = Vector2(120, 80)
	canvas.add_child(_picker_label)

	_black_overlay = ColorRect.new()
	_black_overlay.name = "TASBlackOverlay"
	_black_overlay.color = Color.BLACK
	_black_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black_overlay.visible = false
	_black_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_black_overlay)

	_speed_overlay = Label.new()
	_speed_overlay.name = "SpeedOverlay"
	_speed_overlay.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	_speed_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	_speed_overlay.add_theme_constant_override("outline_size", 2)
	_speed_overlay.anchor_left = 1.0
	_speed_overlay.anchor_right = 1.0
	_speed_overlay.anchor_top = 0.0
	_speed_overlay.anchor_bottom = 0.0
	_speed_overlay.offset_left = -200
	_speed_overlay.offset_right = -16
	_speed_overlay.offset_top = 75
	_speed_overlay.offset_bottom = 100
	_speed_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_speed_overlay)

	add_child(canvas)

func _update_overlay() -> void:
	if _overlay == null:
		return
	if _picker_active:
		_overlay.text = ""
		return
	var lines: PackedStringArray = []
	lines.append("TAS: ON" if enabled else "TAS: OFF")
	if enabled:
		if _awaiting_scene_reset:
			lines.append("Mode: Resetting")
		else:
			lines.append(_mode_label())
		lines.append("Movie: %s" % movie_base_name)
		lines.append("Frame: %d / %d" % [current_frame, movie_length])
		if mode == TASMode.RECORD or mode == TASMode.PLAYBACK:
			lines.append("Frame Step: %s" % ("ON" if frame_step else "OFF"))
		if speed > 1:
			lines.append("Speed: %dx" % speed)
		if mode == TASMode.RECORD or mode == TASMode.PLAYBACK:
			var slot_str := ""
			for i in range(save_slots.size()):
				slot_str += str(i + 1) if save_slots[i] != null else "·"
			lines.append("Save States: %s" % slot_str)
		if _record_confirm_pending:
			var erase_count := movie_length - current_frame
			lines.append(">> Press R again to record from here (%d frames will be erased) <<" % erase_count)
		elif status_text != "":
			lines.append(status_text)
	_overlay.text = "\n".join(lines)

func _update_picker_overlay() -> void:
	if _picker_label == null:
		return
	_picker_label.visible = _picker_active
	_update_overlay()
	if not _picker_active:
		return
	var lines: PackedStringArray = []
	lines.append("=== SELECT MOVIE ===")
	lines.append("")
	for i in range(_picker_items.size()):
		if i == _picker_index:
			lines.append("> " + _picker_items[i])
		else:
			lines.append("  " + _picker_items[i])
	lines.append("")
	lines.append("Up/Down: Navigate    Enter: Select    T/Esc: Cancel")
	_picker_label.text = "\n".join(lines)

func _update_speed_overlay() -> void:
	if _speed_overlay == null:
		return
	var p = _get_player()
	if p == null or not ("max_velocity" in p):
		_speed_overlay.text = ""
		return
	_speed_overlay.text = "%.2f" % p.max_velocity

func _mode_label() -> String:
	match mode:
		TASMode.PLAYBACK:
			return "Mode: Playback"
		TASMode.RECORD:
			return "Mode: Record"
		_:
			return "Mode: Idle"

# --- Speed / time scale ---

func _apply_speed() -> void:
	if frame_step:
		_set_time_scale(1.0)
		return
	# Speed-up is playback-only; recording always runs at 1x
	if mode != TASMode.PLAYBACK:
		_set_time_scale(1.0)
		return
	_set_time_scale(float(clampi(speed, 1, MAX_SPEED)))

func _set_time_scale(val: float) -> void:
	# Compensates physics_ticks_per_second so delta stays 1/base_fps.
	# In Godot, time_scale multiplies the delta passed to _physics_process without
	# changing the iteration count. Scaling physics_fps by the same factor cancels this:
	#   delta = time_scale / (base_fps * time_scale) = 1/base_fps
	if abs(_last_time_scale - val) > 0.0001:
		Engine.time_scale = val
		Engine.physics_ticks_per_second = roundi(_base_physics_fps * val)
		# Only raise the catchup cap during actual fast-forward; restore to default otherwise
		Engine.max_physics_steps_per_frame = max(8, roundi(val) * 4)
		_last_time_scale = val

# --- Tree pause ---

func _process(_delta: float) -> void:
	if _camera_snap_pending:
		_camera_snap_pending = false
		var p = _get_player()
		var cam = get_viewport().get_camera_2d()
		if p != null and cam != null:
			cam.position_smoothing_enabled = false
			cam.global_position = p.global_position
			_camera_smooth_reenable = true
	elif _camera_smooth_reenable:
		_camera_smooth_reenable = false
		var cam = get_viewport().get_camera_2d()
		if cam != null:
			cam.position_smoothing_enabled = true

func _pause_tree_for_frame_step() -> void:
	var tree = get_tree()
	tree.paused = true  # Always enforce. Re-closes if something external (e.g. respawn) unpaused
	if _paused_by_tas:
		return  # Already did setup, just re-enforcing the pause
	_prev_tree_paused = false
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

# --- Calc pressed and released inputs ---

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

func _capture_live_actions() -> Array[bool]:
	var actions: Array[bool] = []
	actions.resize(TASInputRecord.Actions.size())
	actions[TASInputRecord.Actions.LEFT] = Input.is_action_pressed("left") or Input.is_action_pressed("controller_left")
	actions[TASInputRecord.Actions.RIGHT] = Input.is_action_pressed("right") or Input.is_action_pressed("controller_right")
	actions[TASInputRecord.Actions.DOWN] = Input.is_action_pressed("down") or Input.is_action_pressed("controller_down")
	actions[TASInputRecord.Actions.JUMP] = Input.is_action_pressed("jump") or Input.is_action_pressed("controller_jump")
	actions[TASInputRecord.Actions.PAUSE] = Input.is_action_pressed("pause")
	actions[TASInputRecord.Actions.ACTION] = Input.is_action_pressed("action") or Input.is_action_pressed("controller_action")
	actions[TASInputRecord.Actions.RESET_LEVEL] = Input.is_action_pressed("reset_level")
	actions[TASInputRecord.Actions.RESET_PLATFORMS] = Input.is_action_pressed("reset_platforms")
	return actions

# --- Movie file encoding / decoding ---

func _record_frame(actions: Array[bool]) -> void:
	if current_frame < record_frames.size():
		record_frames[current_frame] = actions.duplicate()
		record_frames.resize(current_frame + 1)
	else:
		record_frames.append(actions.duplicate())

func _trim_record_frames(frame_index: int) -> void:
	if frame_index < record_frames.size():
		record_frames.resize(frame_index)

func _write_movie_file() -> void:
	if movie_path == "":
		return
	var fh = FileAccess.open(movie_path, FileAccess.WRITE)
	if fh == null:
		return
	for line in _encode_movie(record_frames):
		fh.store_line(line)
	fh.close()

func _encode_movie(frames: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	if frames.is_empty():
		return out
	var last_actions: Array = frames[0]
	var run := 1
	for i in range(1, frames.size()):
		if _actions_equal(last_actions, frames[i]):
			run += 1
		else:
			out.append(_line_for_actions(run, last_actions))
			last_actions = frames[i]
			run = 1
	out.append(_line_for_actions(run, last_actions))
	return out

func _actions_equal(a: Array[bool], b: Array[bool]) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true

func _line_for_actions(frames: int, actions: Array[bool]) -> String:
	var sb: PackedStringArray = []
	if actions[TASInputRecord.Actions.LEFT]: sb.append("L")
	if actions[TASInputRecord.Actions.RIGHT]: sb.append("R")
	if actions[TASInputRecord.Actions.DOWN]: sb.append("D")
	if actions[TASInputRecord.Actions.JUMP]: sb.append("J")
	if actions[TASInputRecord.Actions.PAUSE]: sb.append("P")
	if actions[TASInputRecord.Actions.ACTION]: sb.append("E")
	if actions[TASInputRecord.Actions.RESET_LEVEL]: sb.append("X")
	if actions[TASInputRecord.Actions.RESET_PLATFORMS]: sb.append("S")
	return "%d,%s" % [frames, ",".join(sb)]

func _load_movie_frames(path: String) -> Array:
	var temp := TASInputController.new()
	temp.file_path = path
	if not temp.reload_from_disk():
		return []
	var frames: Array = []
	for rec in temp.records:
		for i in range(rec.frames):
			frames.append(rec.actions.duplicate())
	return frames

func _calculate_movie_length(records: Array[TASInputRecord]) -> int:
	var total := 0
	for rec in records:
		total += rec.frames
	return total

# --- Save state file handling ---

func _clear_save_slots() -> void:
	save_slots.clear()
	save_slots.resize(5)

func _load_states_file() -> void:
	var path = _states_path()
	if path == "":
		return
	if not FileAccess.file_exists(path):
		_clear_save_slots()
		return
	var fh = FileAccess.open(path, FileAccess.READ)
	if fh == null:
		return
	var text = fh.get_as_text()
	fh.close()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	if not data.has("slots"):
		return
	_clear_save_slots()
	var slots = data["slots"]
	if typeof(slots) != TYPE_ARRAY:
		return
	for i in range(min(slots.size(), save_slots.size())):
		var entry = slots[i]
		if entry == null:
			continue
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not entry.has("frame") or not entry.has("snap"):
			continue
		var snap_data = entry["snap"]
		if typeof(snap_data) != TYPE_DICTIONARY:
			continue
		var snap = TASSnapshot.from_dict(snap_data)
		save_slots[i] = {"frame": int(entry["frame"]), "snap": snap}

func _write_states_file() -> void:
	var path = _states_path()
	if path == "":
		return
	var slots: Array = []
	slots.resize(save_slots.size())
	for i in range(save_slots.size()):
		var entry = save_slots[i]
		if entry == null:
			slots[i] = null
			continue
		var snap: TASSnapshot = entry["snap"]
		slots[i] = {"frame": entry["frame"], "snap": snap.to_dict()}
	var payload = {"slots": slots}
	var fh = FileAccess.open(path, FileAccess.WRITE)
	if fh == null:
		return
	fh.store_string(JSON.stringify(payload))
	fh.close()
