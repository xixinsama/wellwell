# Project Structure

See `docs/architecture.md` for the template / mechanics / worlds dependency
rules and the branch/worktree policy.

## Runtime

- `scenes/app/main.tscn`: application entry scene.
- `scenes/runtime/world_root.tscn`: streamed world, player, room camera, fog,
  crumble runtime, and UI bindings.
- `addons/platformer_kit/`: reusable core, character, platform, camera, world, and save runtime.
- `addons/platformer_abilities/` and `addons/platformer_combat/`: optional gameplay modules.
- `addons/metroidvania_kit/`: optional progression, map discovery, fog, and fast travel.
- `scripts/world/fog_zone.gd` + `scenes/world/fog_zone.tscn`: authored dark/light
  fog rectangles placed under `RoomContent/Entities`.
- `scripts/world/fog_door.gd` + `scenes/world/fog_door.tscn`: a door that blocks
  movement and sight while closed.
- `scripts/world/crumble_runtime.gd`: drives the crumble tiles painted in
  `SolidTiles` for the active room.
- `scripts/world/water/`: `WaterField` room extension, the `WaterSimulation`
  column fluid, authored `WaterBasin` / `WaterGate` markers and the surface /
  waterfall shaders.
- `scripts/world/atmosphere/`: `Atmosphere` room extension and `FogGrid` mist
  field, authored `FogLight` markers and the mist shader.
- `game/player/player_water_motion.gd` + `game/water/effects/water_splash.gd`:
  buoyancy/swimming composition and the PixelFX splash.
- `game/`: project-specific composition and authored map data.
- `resources/worlds/test_world.tres`: exploration test world (water hall with two
  pools and drifting mist, fog zones, glass, crumble platforms, two-screen room)
  selectable from the world menu; it starts in `water_hall`.

## Authoring

- `scenes/rooms/template/level_template.tscn`: empty room authoring template.
- `scenes/puzzle/puzzle_tile_piece.tscn`: reusable tile-authored sliding region (background, walls, one-way platforms, and `VoidTiles` for movable void sliders).
- `scenes/puzzle/puzzle_void_zone.tscn`: legacy static player-only void region for puzzle boards (sliders may cross; the player cannot enter in jump mode).
- `scenes/rooms/source/`: editable room source scenes. Do not hand-edit generated files.
- `scenes/levels/test/`: editable source rooms for the exploration test world and
  `test_world_runner.tscn`, which starts that world without the main menu.
- `scenes/rooms/generated/<room_id>/`: baked runtime and terrain scenes.
- `resources/rooms/generated/<room_id>.tres`: baked local `RoomData`.
- `addons/world_editor/`: optional main-screen World Editor and its authoring helpers.
- `addons/world_editor/world_editor_main.tscn`: three-column world workbench (room list, canvas, inspector, status bar).
- `addons/world_editor/authoring/world/room_status_service.gd`: fresh / stale / error / unknown room status.
- `scenes/ui/world_select.tscn`: map selection screen shown after a save slot.
- `resources/worlds/world_catalog.tres`: ordered list of worlds offered by the map screen; edit its `WorldData` entries in the inspector.
- `resources/worlds/main_world.tres`: shipped `WorldData`, including room placements and connections.

## Conventions

One chunk is `320x180` pixels. Room geometry is local to its source scene. `WorldRoomPlacementData` stores an integer chunk origin; `RoomConnectionData` stores an entrance-to-spawn transition. A generated room is stale when its source fingerprint differs, so bake the room before baking its world.

## Verification

Run `godot --headless --path . -s res://tests/run_runtime_suite.gd` for automated coverage. Run `godot --headless --editor --path . --quit` after scene or plugin changes, and `godot --headless --path . -s res://tools/validate_project.gd` to validate the shipped terrain contract.
