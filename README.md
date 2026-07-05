# Sir Fallen TAS

A Tool Assisted Speedrun (TAS) playback/recording addon for [Sir Fallen](https://store.steampowered.com/app/2880990/Sir_Fallen/).

![Sir Fallen](SirFallen.png)

## Integration

1. Create a folder in `res://addons` called `tas`. Copy the `src/` folder here.

```
res://addons/tas/
  src/                 
    tas_input_controller.gd       
    tas_input_record.gd            
    tas_manager.gd
    tas_snapshot.gd
  README.md
  .gitignore
```

2. Add the TASManager as an autoload singleton. In Project -> Project Settings -> Globals -> Autoload set the path to: `res://addons/tas/src/tas_manager.gd` and the name to: `TASManager`.


3. Four of the original Sir Fallen source files were modified. Download the modified versions [here](https://drive.google.com/file/d/1FU3-pXjoDws_D8qfmLkovz8TExvqXzAj/view?usp=sharing) and replace them inside the project. 


## Controls (default keyboard keys)

| Key | Action |
|-----|--------|
| **T** | Toggle TAS. When off: opens the TAS menu to select/create a movie (also available in the pause menu). When on: disables TAS. |
| **O** | Play / pause playback |
| **Shift+O** | Reset playback to frame 0|
| **=** / **-** | Speed up / slow down playback |
| **R** | Start / stop recording |
| **K** | Toggle frame-step mode |
| **.** (period) | Advance one frame in frame-step (hold to auto-advance) |
| **,** (comma) | Step back one frame |
| **1–5** | Load save state slot |
| **Shift+1–5** | Save state slot |


## Usage

### Enable TAS
Press **T** (or open the pause menu and click **TAS**) to open the TAS menu. Movies are shown in a vertical list and can be selected using Up/Down + Enter or by clicking. Choose **[ New Movie ]** to create a new one: type a name and press Enter, or leave the field blank for a default name (`Run_YYYYMMDD`). Once a movie is selected, the level resets and you are placed at Frame 0.

### Recording
Press **R** to start recording from the current position. Frame-step is on by default when the TAS gets enabled, press **K** to toggle it off for real-time recording. Before any new recording session starts, the existing movie is backed up to `backups/` with a timestamp. Press **R** again to stop and save progress.

### Playback
Press **O** to toggle play/pause for the recording. When the TAS is initially enabled, starts playback from frame 0. When already in playback, pauses or resumes at the current frame. **Shift+O** always restarts playback from frame 0 regardless of current state.

### Resuming a session
To continue from where you left off: press **O** to play through the existing run (use **=** to increase speed if necessary) or use save states to jump around, then press **R** when you reach the point you want to record from. If you begin the recording before the end of the file, you will erase all of the frames that have been written beyond the current frame.

## File structure

Movies live in `res://tas/` (i.e. `SirFallen/tas/` inside the project folder):

```
res://tas/
  movie1/                    - movie name that appears in the movie picker
    movie1.tas               - movie file (list of frame by frame inputs)
    states.json              - save state slots 1–5
    backups/
      20260410_143022.tas    - backup before each recording
  Run_20260410/
    Run_20260410.tas
    ...
```

## Movie file format

`NUM FRAMES,Actions`. One line per sequence of identical inputs:

| Code | Input |
|------|-------|
| `L` | Left |
| `R` | Right |
| `D` | Down |
| `J` | Jump |
| `P` | Pause |
| `E` | Action / Interact |
| `X` | Reset Level |
| `S` | Reset Platforms |

Example:
```
 35,R,J
 10,R
 60,L
```

This example would input Right and Jump for 35 frames, then Right for 10 frames and then Left for 60 frames.

TAS files can be edited manually but they are automatically created and edited when in record mode. I would recommend disabling the TAS before making manual edits to avoid de-sync. 


## Implementation notes

- In addition to the TAS overlay, the TAS manager also displays a constant overlay for the current max horizontal velocity. This is because bhops and ground coyote jumps increase the max horizontal velocity by different amounts depending on which frame you jump. This overlay allows the user to get visual feedback for frame-perfect inputs.

- The `,` key can only step back up to 600 frames. Snapshots older than that are dropped to save on memory. Loading a save state clears the buffer completely, so you can't step back past a save state.

- The `.tas` file is written to disk when you switch to playback, stop recording (**R**), disable TAS (**T**) or quit the game. It is not written every frame.

## Known limitations

- Coyote jumps off of moving platforms are prone to desync between recording and playback (specifically when using them to gain large amounts of speed). There isn't a known fix yet.
- Deaths, respawns, and interacting with objects use real-time timers in the game code (they keep counting while frame-stepping), so the number of physics frames used is not deterministic. Try to avoid deaths and interactions to prevent desync

## License

MIT License. See LICENSE for details.
