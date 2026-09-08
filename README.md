# wellwell

`wellwell` is a Godot 4 pixel-platformer foundation with room authoring, a world layout editor, streamed room runtime, persistent entities, and room-scoped fog of war.

Open `project.godot` in Godot and run `res://scenes/app/main.tscn`.

Run the reusable movement fixtures directly with:

```powershell
godot --path . res://examples/movement_lab/movement_lab.tscn
```

Use the optional diagnostics variant with:

```powershell
godot --path . res://examples/movement_lab/movement_lab_debug.tscn
```

## What Is Included

- 1280x720 outer window.
- 322x182 `SubViewport`, with 320x180 used as the safe gameplay frame.
- 120 TPS physics.
- Tunable `CharacterBody2D` player.
- 8x8 block player visual.
- Jump buffer, coyote time, variable jump height, air control, and fast fall.
- Pixel-quantized camera.
- Debug HUD and grid overlay.
- Source rooms under `scenes/rooms/source/`, baked runtime/terrain outputs, and `WorldData` placement resources.
- A main-screen World Editor plugin for room placement, connection authoring, terrain previews, grid snapping, zoom, and focus.
- Per-room flood-fill fog visibility and a post-process-ready mask texture.

## What Is Not Included

This template intentionally excludes combat, dialogue, progression, and Dash2Home-specific mechanics. It includes a focused save system and foundational room streaming, but not a full game-specific content framework.

## Room Workflow

Create or edit a room in `scenes/rooms/source/` from `scenes/rooms/template/level_template.tscn`. Bake the room from the World Editor to generate `scenes/rooms/generated/<room_id>/` and `resources/rooms/generated/<room_id>.tres`. Add the generated room resource to a world such as `resources/worlds/main_world.tres`; world placement belongs to that world, not to `RoomData`.

See [project structure](docs/project-structure.md) for ownership boundaries and verification commands.

## Controls

- A / Left: move left
- D / Right: move right
- W / Up: up input
- S / Down: down input and fast fall
- Space / Z: jump
- F1: cycle grid overlay
- `[` / `]`: choose a tuning field during play
- `-` / `=`: decrease or increase the selected tuning field during play
