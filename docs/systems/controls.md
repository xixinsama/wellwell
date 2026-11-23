# Controls

## Keyboard

- A / Left: move left
- D / Right: move right
- W / Up: up input
- S / Down: down input, fast fall, and ducking on the ground
- Space / Z: jump
- X: dash (after collecting the Dash reward)

## Gamepad

- Left stick / D-Pad: movement
- South button: jump
- East button: dash

## Dash

The Dash follows the current input: left, right, up, down, and the four
diagonals. Stick input snaps to the nearest 45 degrees, so a diagonal dash
moves at the same speed as a straight one, and releasing the stick dashes
toward the facing direction.

The dash starts with a 0.05 s global freeze, lasts 0.15 s, then keeps a
160 px/s exit speed. Its attack window lasts 0.3 s and is used by super, hyper,
wavedash, and wallbounce; it does not deal damage yet.

A straight dash also crosses a one-way platform when it travels in the
direction that platform blocks:

- a floor platform (blocks downward) is crossed by a **down** dash,
- a ceiling platform (blocks upward) is crossed by an **up** dash,
- a vertical platform is crossed by a **left** or **right** dash that matches
  the side it blocks.

Diagonal dashes never cross one-way platforms. Solid ground always stops the
dash.

## Dash charges

The Dash works like a jump count: one dash is stored, and it refills when the
player touches the ground after a 0.1 s delay. In the air the second press does
nothing until the player lands, so a dash cannot be chained in mid-air.

Swimming refills the dash while the normal cooldown applies.

## Wall movement (no grab button)

Wall movement is an **unlockable Climb ability**. Until it is granted, holding
toward a wall does nothing: no grab, wall slide, wall jump or wallbounce.

Hold the direction toward a wall to attach. There is no separate grab input.
Attaching pulls the body flush against the wall, and a moving platform keeps
carrying the player while attached.

The Climb ability is authored as
`addons/platformer_kit/abilities/climb/default_climb.tres`. Grant it with
an `ability_pickup.tscn` instance (same pattern as the Dash pickup) or the
ready-made `addons/platformer_kit/abilities/entities/climb_pickup.tscn`, or directly
through `player.grant_ability_definition()`. Standalone lab/gallery scenes
auto-install authored abilities; the main game removes Climb until progression
has unlocked it.

- Hold toward the wall: grab and hold position; stamina drains at 10/s.
- Toward + up: climb up; stamina drains at 45.45/s.
- Toward + down: climb down; no stamina cost.
- Toward + jump: **wall jump away**; costs no stamina. This is the normal way
  to alternate between two walls.
- Toward + up + jump: climb jump straight up; costs 27.5 stamina.
- Away or neutral + jump: wall jump away; costs no stamina.
- Climb jump, then press away within 0.2 s: converts to a wall jump and refunds
  the 27.5 stamina.
- Stamina at 20 or below: cannot start a new grab.
- Stamina at 0 while holding toward the wall: wall slide (fall cap 20 -> 160
  over 1.2 s).
- A wall jump locks auto-grab only on the wall that was just left (0.16 s), so
  the opposite wall can be grabbed immediately and left/right chains stay
  smooth.

## Advanced jumps

- Horizontal dash on the ground, then jump: **super** (260 horizontal).
- Ducking (`S` on the ground) or a down-diagonal dash into the ground, then
  jump: **hyper / wavedash** (325 horizontal, -60 vertical).
- Up-dash beside a wall, then jump during the dash attack window:
  **wallbounce** (170 away, -160 up).

## Stamina

Stamina is 110. It refills on landing, entering water, and respawning/loading a
save. There is no stamina bar yet; the hero animation can expose the state.

## Settings: Celeste Momentum

Game → **Celeste Momentum** is off by default. When enabled:

- a dash keeps a higher pre-dash horizontal speed instead of resetting to 240;
- a down-diagonal dash that touches the ground applies the Ultra `x1.2`
  multiplier and ends, letting chained ultras exceed 325 px/s.

The toggle applies immediately to the player.

## Settings: Realtime Save

Game → **Realtime Save** is off by default. When enabled, the game records the
player's position and velocity every two seconds and flushes the save when the
window closes. Continuing that slot resumes at the exact room and spot where
the session ended.

Death is unchanged: kill zones and hazards still return the player to the last
checkpoint, not the live position. Disabling the setting returns the next start
to the normal checkpoint behavior. If the process is killed before the final
flush, at most about two seconds of movement are lost.

## Debug

- F1: cycle grid overlay between hidden, 8px, and 16px.
- F3: toggle the runtime debug overlay.
- `[` / `]`: select a tuning field.
- `-` / `=`: adjust the selected field while the game is running.

## TAS (debug overlay)

The debug overlay includes an input TAS. It records one `CharacterIntent` per
physics tick and replays it through the player's input source. Its status panel
is part of the HUD-space debug overlay, outside the 320 × 180 gameplay
SubViewport, so the text stays crisp at the window's native resolution.

- Ctrl+R: start recording from the current spot, or stop the active recording.
- Ctrl+P: play the recording from its start, or stop playback.
- Ctrl+S: stop recording if needed, then save the clip to
  `user://tas_recording.json`.
- F5: show/hide the TAS panel.
- F6: start/stop recording (same as Ctrl+R).
- F7: play/stop the recorded input (same as Ctrl+P).
- F8: clear the recording.
- F9: toggle 0.25x slow motion.
- F10: save the recording (same as Ctrl+S).
- F11: load that recording.
- F12: reset the player to the recording start.

A clip remembers the world and room where recording began. Playback refuses to
start in a different room so the player is never teleported into a room that is
not loaded. The payload also keeps the old fields, so recordings made before
this guard still load.

The demo scene `examples/tas_demo/tas_demo.tscn` replays two recorded clips and
shows the speed caps. Regenerate the clips with:

```bash
godot --headless --path . -s res://tools/build_tas_demo_recordings.gd
```
