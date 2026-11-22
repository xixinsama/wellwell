# Project Structure

See `docs/architecture.md` for the template / mechanics / worlds dependency
rules and the branch/worktree policy.

See `docs/art-layers.md` for the rendering stack, bottom to top: what each layer
draws, who owns it, why the systems live in `world_root.tscn` rather than in the
room template, and which "assets" are baked or generated instead of hand-drawn.

## Runtime

- `scenes/app/main.tscn`: application entry scene.
- `scenes/runtime/world_root.tscn`: streamed world, player, room camera, fog,
  crumble runtime, and UI bindings.
- `addons/platformer_kit/`: reusable core, character, platform, camera, world, and save runtime.
- `addons/platformer_abilities/` and `addons/platformer_combat/`: optional gameplay modules.
- `addons/metroidvania_kit/`: optional progression, map discovery, fog, and fast travel.
- `scripts/world/fog_zone.gd` + `scenes/world/fog_zone.tscn`: authored dark/light
  fog rectangles placed under `RoomContent/Entities`.
- `scenes/world/fog_door.tscn`: a door assembled from `DoorComponent2D`
  (`addons/platformer_kit/world/components/`) and `FogOccluderComponent2D`
  (`addons/platformer_kit/platforms/components/`). The occluder component also
  gives any platform or solid body a sight shadow.
- `scenes/world/phantom_wall.tscn`: a `TileMapLayer` with collision disabled and
  `PhantomWallComponent2D` attached — a secret wall that looks like terrain, can
  be walked through, hides what is behind it until touched, then fades out.
- `scripts/world/crumble_runtime.gd`: drives the crumble tiles painted in
  `SolidTiles` for the active room.
- `scripts/world/backdrop_field.gd` + `scripts/shaders/backdrop_drift.gdshader`:
  the room backdrop plate. One 320x180 `assets/images/backdrop_well.png` plate is
  dropped into every room's `Background` container (which draws before
  `Terrain`), so it sits behind the background tilemap layer and scrolls with
  the camera. Every tilemap layer stays crisp and untouched; the shader only
  softens the plate and slides each scanline sideways on a short wavelength, so
  the plate reads as moving air. `background_tilemap_alpha` (default 1.0) is the
  escape hatch for a room whose background layer is a flat fill that would hide
  the plate. Regenerate the art with `art-src/gen_backdrop.lua` (Aseprite batch).
- `scripts/ui/crt_overlay.gd` + `scripts/shaders/crt_screen.gdshader`: the
  topmost canvas layer, a screen-space CRT finish (scanlines, slot mask, edge
  colour split, phosphor glow). Shading is only multiplied into non-bright
  pixels and glow is added, so highlights keep their brightness. Switched by the
  `crt_enabled` video setting.
- `addons/metroidvania_kit/map/`: generated map model, terrain snapshots,
  exploration conversion, and the precise/grid renderers, full map and minimap.
- `game/map/map_host.gd`: HUD host that builds the map for the running world and
  binds the minimap and full map.
- `addons/fluid_kit/runtime/water/`: `WaterField` room extension, the `WaterSimulation`
  column fluid, authored `WaterBasin` / `WaterGate` markers and the surface /
  waterfall shaders.
- `addons/fluid_kit/runtime/gas/`: `Atmosphere` room extension (2D Navier-Stokes
  gas), the GPU pass shaders, `GasVent` / `GasField` / `GasInteractor` /
  `GasTrailWalker` / `FogLight` nodes and the CPU `FogGrid` fallback.
- `addons/fluid_kit/demos/`: runnable fluid demos (water hall, gas plumes, gas
  effects, gas trail).
- `game/player/player_water_motion.gd` + `game/water/effects/water_splash.gd`:
  buoyancy/swimming composition and the PixelFX splash.
- `game/player/one_way_dash_piercer.gd`: player component that lets a cardinal
  dash cross a one-way surface travelling in the direction it blocks (tile
  one-ways on the `one_way` layer, node one-ways by collision exception).
- `scripts/player/player_controller.gd`: NORMAL/DASH/WALL_GRAB/WALL_SLIDE
  orchestration, super/hyper/wavedash and wallbounce resolution.
- `scripts/player/player_stamina.gd` and `player_motion_rules.gd`: stamina
  economy and pure Celeste rule math.
- `scripts/globals/game_freeze.gd`: global hit-stop autoload used by dash start.
- `addons/platformer_debug/runtime/tas_tool.gd`: record/replay input TAS shown
  in the debug overlay; `examples/tas_demo/` replays recorded movement clips.
- `scripts/save/realtime_save_service.gd`: game-layer live-save recorder under
  `WorldRoot`; captures the player transform while the Realtime Save Game
  setting is on.
- `game/`: project-specific composition and authored map data.
- `resources/worlds/test_world.tres`: exploration test world (water hall with two
  pools, gas lab, gas trail room, fog zones, glass, crumble platforms, two-screen
  room) selectable from the world menu; it starts in `water_hall`.

## Authoring

- `scenes/rooms/template/level_template.tscn`: empty room authoring template.
- `scenes/worlds/<world_id>/terrain.tscn`: the world's single authored terrain scene (terrain layers only, world cell coordinates). Edit it with **Edit Terrain**, then **Sync Terrain** slices it into every room.
- `scenes/levels/generated/<world_id>/`: room source scenes created by **Draw Room**, Merge or Split.
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

One chunk is `320x180` pixels, which is 40x22.5 cells at 8 px, so a room's world cell rectangle is snapped to the global cell grid: each chunk row is 23 or 22 cells tall and a two-row room is 45 cells (see `docs/world-alignment.md` and `RoomGrid`). Room geometry is local to its source scene. `WorldRoomPlacementData` stores an integer chunk origin; `RoomConnectionData` stores an entrance-to-spawn transition. A generated room is stale when its source fingerprint differs, so bake the room before baking its world. Baking takes the room's live chunk origin and crops terrain cells outside its cell frame.

## Verification

Run `godot --headless --path . -s res://tests/run_runtime_suite.gd` for automated coverage. Run `godot --headless --editor --path . --quit` after scene or plugin changes, and `godot --headless --path . -s res://tools/validate_project.gd` to validate the shipped terrain contract.
