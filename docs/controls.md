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

Hold the direction toward a wall to attach. There is no separate grab input.
Attaching pulls the body flush against the wall, and a moving platform keeps
carrying the player while attached.

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

## Debug

- F1: cycle grid overlay between hidden, 8px, and 16px.
- F3: toggle the runtime debug overlay.
- `[` / `]`: select a tuning field.
- `-` / `=`: adjust the selected field while the game is running.
