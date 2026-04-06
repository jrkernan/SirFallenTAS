# Sir Fallen TAS

A TAS playback addon for Sir Fallen in Godot 4.4. Drop an `addons/tas` folder into the project, add `res://addons/tas/src/tas_manager.gd` as an Autoload singleton, and place a `SirFallen.tas` file in `user://tas/`. The tool will read inputs line by line from the `.tas` file (text file) and execute them in game.

## Controls
- F6: toggle TAS on/off
- F7: toggle frame-step mode
- `.` (period): advance one frame when in frame-step
- `,` (comma): step back one frame
- `=` / `-`: speed up / slow down playback
- F5: reload `.tas`

## `.tas` File format
`NUM_FRAMES,Actions` where Actions are:
- L = Left
- R = Right
- D = Down
- J = Jump
- P = Pause
- E = Interact
- X = Reset Level
- S = Reset Platforms
- Fast forward: a line of `***` (optionally followed by speed; default 400). Add `!` to force a break into frame-step.

Example:
```
 35,R,J
 10,R
 60,L
```
This would input Right and Jump for 35 frames, then just Right for 10 frames, then Left for 60 frames

## Integration
1) Autoload: add `res://addons/tas/src/tas_manager.gd`.
2) Player input modifications: change the player to read from `TASManager` when `enabled` instead of `Input`. Example:
```gdscript
var tas := TASManager
func get_input_axis():
    if tas.enabled:
        return tas.get_axis(TASInputRecord.Actions.LEFT, TASInputRecord.Actions.RIGHT)
    return Input.get_axis("left", "right")
```
(Eventually I plan to attach a 'Player.gd' file to this repo that can be dropped in instead of requiring manual edits)
3) Snapshots: `tas_snapshot.gd` captures position/velocity/timers from `player.gd`.

## License
MIT License. See LICENSE for details.

