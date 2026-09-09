# Project Structure

## Runtime

- `scenes/app/main.tscn`: application entry scene.
- `scenes/runtime/world_root.tscn`: streamed world, player, room camera, fog, and UI bindings.
- `addons/platformer_kit/`: reusable core, character, platform, camera, world, and save runtime.
- `addons/platformer_abilities/` and `addons/platformer_combat/`: optional gameplay modules.
- `addons/metroidvania_kit/`: optional progression, map discovery, fog, and fast travel.
- `game/`: project-specific composition and authored map data.

## Authoring

- `scenes/rooms/template/level_template.tscn`: empty room authoring template.
- `scenes/rooms/source/`: editable room source scenes. Do not hand-edit generated files.
- `scenes/rooms/generated/<room_id>/`: baked runtime and terrain scenes.
- `resources/rooms/generated/<room_id>.tres`: baked local `RoomData`.
- `addons/world_editor/`: optional main-screen editor plugin and its authoring helpers.
- `resources/worlds/main_world.tres`: shipped `WorldData`, including room placements and connections.
- `addons/world_editor/`: Godot main-screen World Editor.

## Conventions

One chunk is `320x180` pixels. Room geometry is local to its source scene. `WorldRoomPlacementData` stores an integer chunk origin; `RoomConnectionData` stores an entrance-to-spawn transition. A generated room is stale when its source fingerprint differs, so bake the room before baking its world.

## Verification

Run `godot --headless --path . -s res://tests/run_runtime_suite.gd` for automated coverage. Run `godot --headless --editor --path . --quit` after scene or plugin changes, and `godot --headless --path . -s res://tools/validate_project.gd` to validate the shipped terrain contract.
