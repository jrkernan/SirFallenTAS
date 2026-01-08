extends RefCounted

## Represents a single line in a .tas file: frame count + action flags or a fast-forward marker.
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
var fast_forward: bool = false
var force_break: bool = false

func _init(p_line_number: int = 0, line: String = ""):
    line_number = p_line_number
    actions.resize(Actions.size())
    if line == "":
        return
    _parse_line(line.strip_edges())

func _parse_line(line: String) -> void:
    # Fast-forward marker: "***" optionally followed by a speed number, optional "!" to force a break.
    if line.begins_with("***"):
        fast_forward = true
        line = line.substr(3, line.length())
        if line.begins_with("!"):
            force_break = true
            line = line.substr(1, line.length())
        frames = _read_int(line.strip_edges())
        if frames == 0:
            frames = 400 # default fast speed similar to JumpKingTAS
        return

    frames = _read_int(line)
    if frames <= 0:
        frames = 0
        return

    # Remaining chars are actions separated by commas or whitespace.
    for ch in line:
        match ch.to_upper():
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
    for ch in text:
        if ch == "-" or ch.is_valid_int():
            num += ch
        elif num != "":
            break
    if num == "":
        return 0
    return num.to_int()

func to_string() -> String:
    if frames == 0 and not fast_forward:
        return ""
    if fast_forward:
        var ff := "***"
        if force_break:
            ff += "!"
        if frames != 400:
            ff += str(frames)
        return ff
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
