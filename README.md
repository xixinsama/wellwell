# wellwell

`wellwell` is a compact Godot 4.6 template for pixel-precise 2D platformer experiments.

Open `project.godot` in Godot and run `res://scenes/main.tscn`.

## What Is Included

- 1280x720 outer window.
- 322x182 `SubViewport`, with 320x180 used as the safe gameplay frame.
- 120 TPS physics.
- Tunable `CharacterBody2D` player.
- 8x8 block player visual.
- Jump buffer, coyote time, variable jump height, air control, and fast fall.
- Pixel-quantized camera.
- Debug HUD and grid overlay.
- Graybox movement test scene.

## What Is Not Included

This template intentionally excludes combat, saving, dialogue, room streaming, rope physics, metroidvania progression, and Dash2Home-specific spatial traction systems.

## Controls

- A / Left: move left
- D / Right: move right
- W / Up: up input
- S / Down: down input and fast fall
- Space / Z: jump
- F1: cycle grid overlay
- `[` / `]`: choose a tuning field during play
- `-` / `=`: decrease or increase the selected tuning field during play
