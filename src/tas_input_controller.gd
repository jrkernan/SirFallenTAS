extends RefCounted
class_name TASInputController

## Reads .tas file and stores input records
var file_path: String = "user://tas/SirFallen.tas"
var records: Array[TASInputRecord] = []
var index: int = 0
var frame_to_next: int = 0
var current_frame: int = 0
var current: TASInputRecord
var previous: TASInputRecord

func reload_from_disk() -> bool:
	records.clear()
	index = 0
	frame_to_next = 0
	current_frame = 0
	current = null
	previous = null

	if not FileAccess.file_exists(file_path):
		return false

	var fh = FileAccess.open(file_path, FileAccess.READ)
	if fh == null:
		return false

	var line_no := 0
	while not fh.eof_reached():
		line_no += 1
		var line = fh.get_line()
		var rec = TASInputRecord.new(line_no, line)
		if rec.frames != 0:
			records.append(rec)
	fh.close()

	if records.size() > 0:
		current = records[0]
		frame_to_next = current.frames
	return records.size() > 0

func initialize_playback() -> void:
	current_frame = 0
	index = 0
	if records.size() == 0:
		return
	current = records[0]
	frame_to_next = current.frames
	previous = null

func can_playback() -> bool:
	return index < records.size()

func playback_tick() -> void:
	if not can_playback():
		return
	if current_frame >= frame_to_next:
		if index + 1 >= records.size():
			index += 1
			return
		previous = current
		index += 1
		current = records[index]
		frame_to_next += current.frames
	current_frame += 1

func reload_playback_at(frame_number: int) -> void:
	initialize_playback()
	current_frame = frame_number
	while current_frame > 0 and current_frame >= frame_to_next and index + 1 < records.size():
		previous = current
		index += 1
		current = records[index]
		frame_to_next += current.frames

func current_actions() -> Array[bool]:
	if current == null:
		return []
	return current.actions.duplicate()

func current_pressed_actions() -> Array[bool]:
	if current == null:
		return []
	var prev := previous
	if prev == null:
		return current.actions.duplicate()
	var pressed: Array[bool] = []
	pressed.resize(TASInputRecord.Actions.size())
	for i in range(pressed.size()):
		pressed[i] = (not prev.actions[i]) and current.actions[i]
	return pressed

func current_released_actions() -> Array[bool]:
	if current == null:
		return []
	var prev := previous
	if prev == null:
		var none: Array[bool] = []
		none.resize(TASInputRecord.Actions.size())
		return none
	var released: Array[bool] = []
	released.resize(TASInputRecord.Actions.size())
	for i in range(released.size()):
		released[i] = prev.actions[i] and (not current.actions[i])
	return released
