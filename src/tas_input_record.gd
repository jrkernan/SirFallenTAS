extends RefCounted

## Represents a single line in a .tas file: frame count + actions
class_name TASInputRecord

enum Actions {
	LEFT,
	RIGHT,
	DOWN,
	JUMP,
	PAUSE,
	ACTION,
	RESET_LEVEL,
	RESET_PLATFORMS,
}

var line_number: int = 0
var frames: int = 0
var actions: Array[bool] = []

func _init(p_line_number: int = 0, line: String = ""):
	line_number = p_line_number
	actions.resize(Actions.size())
	if line == "":
		return
	_parse_line(line.strip_edges())

func _parse_line(line: String) -> void:
	frames = _read_int(line)
	if frames <= 0:
		frames = 0
		return

	# Remaining chars are actions
	for char in line:
		match char.to_upper():
			"L": _set_action(Actions.LEFT)
			"R": _set_action(Actions.RIGHT)
			"D": _set_action(Actions.DOWN)
			"J": _set_action(Actions.JUMP)
			"P": _set_action(Actions.PAUSE)
			"E": _set_action(Actions.ACTION)
			"X": _set_action(Actions.RESET_LEVEL)
			"S": _set_action(Actions.RESET_PLATFORMS)
			_ : pass

func _set_action(idx: int) -> void:
	if idx >= 0 and idx < actions.size():
		actions[idx] = true

func has_action(idx: int) -> bool:
	return idx >= 0 and idx < actions.size() and actions[idx]

func _read_int(text: String) -> int:
	var num := ""
	for char in text:
		if char == "-" or char.is_valid_int():
			num += char
		elif num != "":
			break
	if num == "":
		return 0
	return num.to_int()

func to_string() -> String:
	if frames == 0:
		return ""
	var sb: PackedStringArray = []
	if has_action(Actions.LEFT): sb.append("L")
	if has_action(Actions.RIGHT): sb.append("R")
	if has_action(Actions.DOWN): sb.append("D")
	if has_action(Actions.JUMP): sb.append("J")
	if has_action(Actions.PAUSE): sb.append("P")
	if has_action(Actions.ACTION): sb.append("E")
	if has_action(Actions.RESET_LEVEL): sb.append("X")
	if has_action(Actions.RESET_PLATFORMS): sb.append("S")
	return "%4d,%s" % [frames, ",".join(sb)]
