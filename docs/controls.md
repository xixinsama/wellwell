# Controls

## Keyboard

- A / Left: move left
- D / Right: move right
- W / Up: up input
- S / Down: down input and fast fall
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
player touches the ground. In the air the second press does nothing until the
player lands, so a dash cannot be chained in mid-air.

Swimming refills the dash every frame, so dashes are unlimited in water (the
normal dash cooldown still applies).

## Debug

- F1: cycle grid overlay between hidden, 8px, and 16px.
- F3: toggle the runtime debug overlay.
- `[` / `]`: select a tuning field.
- `-` / `=`: adjust the selected field while the game is running.
