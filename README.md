# TAS Addon (Sir Fallen)

A minimal TAS playback addon for Godot 4.x. Drop this `addons/tas` folder into the project, add `res://addons/tas/src/tas_manager.gd` as an Autoload singleton, and place a `SirFallen.tas` file in `res://tas/` or `user://tas/` (preferred).

## Controls (default, physical keys)
- F6: toggle TAS on/off
- F7: toggle frame-step mode
- `.` (period): advance one frame when in frame-step
- `,` (comma): step back one frame (restores last snapshot)
- `=` / `-`: speed up / slow down playback (integer multiplier)
- F5: reload `.tas`

## File format
`FRAMES,Actions` where Actions use:
- L = Left
- R = Right
- D = Down
- J = Jump
- P = Pause
- E = Action/Interact
- X = Reset Level
- S = Reset Platforms
- Fast forward: a line of `***` (optionally followed by speed; default 400). Add `!` to force a break into frame-step.

Example:
```
 35,R,J
 10,R
***400
 60,L
```

## Integration points
1) Autoload: add `res://addons/tas/src/tas_manager.gd`.
2) Player input shim: change the player to read from `TASManager` when `enabled` instead of `Input`. Example:
```gdscript
var tas := TASManager
func get_input_axis():
    if tas.enabled:
        return tas.get_axis(TASInputRecord.Actions.LEFT, TASInputRecord.Actions.RIGHT)
    return Input.get_axis("left", "right")
```
3) Snapshots: `tas_snapshot.gd` captures position/velocity/timers from `player.gd`. Extend it if more state is needed for deterministic rewind.

## Known limitations
- Speedup uses multiple physics ticks per frame but does not change Engine time scale; heavy scenes may still be bound by performance.
- Snapshot fields are minimal; if you see divergence after step-back, add missing fields/timers in `tas_snapshot.gd`.

