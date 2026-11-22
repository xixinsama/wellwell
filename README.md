# wellwell

`wellwell` is a Godot 4 pixel-platformer foundation with room authoring, a world layout editor, streamed room runtime, persistent entities, and room-scoped fog of war.

The current reusable framework baseline is **Platformer Kit 0.1.0**. See the
[framework README](addons/platformer_kit/README.md), [changelog](CHANGELOG.md),
and [migration guide](MIGRATION.md) before copying or upgrading the addon.

Reusable runtime code lives in `addons/platformer_kit/`; optional abilities,
combat, diagnostics, Metroidvania systems, and the editor are separate addons.
The main-screen World Editor is provided by `addons/world_editor/` and only
depends on Platformer Kit world contracts.

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
- 120 TPS physics by default; movement timers are expressed in seconds and also work at 60 TPS.
- Tunable `CharacterBody2D` player.
- 8x8 block player visual.
- Jump buffer, coyote time, variable jump height, apex half gravity, air control, and fast fall.
- Celeste-style dash (freeze, end speed, dash-attack window), super/hyper/wavedash, and wallbounce.
- No-grab wall grab, climb, wall slide, stamina, wall jump, and climb-jump conversion.
- Global hit-stop and moving-platform lift caps.
- Pixel-quantized camera.
- Debug HUD and grid overlay.
- Source rooms under `scenes/rooms/source/`, baked runtime/terrain outputs, and `WorldData` placement resources.
- A main-screen `addons/world_editor/` plugin for room placement, connection authoring, terrain previews, grid snapping, zoom, and focus.
- Per-room flood-fill fog visibility and a post-process-ready mask texture.

## What Is Not Included

This template intentionally excludes dialogue, concrete enemies, story content, and Dash2Home-specific mechanics. Combat, abilities, diagnostics, and Metroidvania progression are optional framework modules rather than game content.

## Room Workflow

Create or edit a room in `scenes/rooms/source/` from `scenes/rooms/template/level_template.tscn`. Bake the room from the World Editor to generate `scenes/rooms/generated/<room_id>/` and `resources/rooms/generated/<room_id>.tres`. Add the generated room resource to a world such as `resources/worlds/main_world.tres`; world placement belongs to that world, not to `RoomData`.

`world_editor/room_template_scene` in `project.godot` selects the scene opened
by **New Room**, so forked games can provide their own authoring template
without modifying the plugin.

See [project structure](docs/project-structure.md) for ownership boundaries and verification commands.

See the [components tutorial](docs/components-tutorial.md) for how to assemble
platforms, fog occluders, doors and phantom walls, including the authoring
gotchas.

See [art layers](docs/art-layers.md) for the render stack from the backdrop plate upwards:
what each layer draws, who owns it, why the systems live in `world_root.tscn` instead of
the room template, and which "assets" (the normal atlas, the dither tile) are baked
instead of hand-drawn.

## Controls

- A / Left: move left
- D / Right: move right
- W / Up: up input
- S / Down: down input, fast fall, and duck
- Space / Z: jump
- X: dash
- Hold toward a wall to grab/climb; hold away or neutral and press jump to wall jump
- F1: cycle grid overlay
- `[` / `]`: choose a tuning field during play
- `-` / `=`: decrease or increase the selected tuning field during play
