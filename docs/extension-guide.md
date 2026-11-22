# Extension Guide

`wellwell` is meant to branch easily. Add mechanics by composing around the player controller instead of expanding it into a large game-specific coordinator.

## Versioning Discipline

Treat `addons/platformer_kit/` as a versioned dependency. The framework version
is declared in its `plugin.cfg` and mirrored by `application/config/version` in
`project.godot`. Read `CHANGELOG.md` and `MIGRATION.md` before importing a newer
version into an existing game. Keep game-specific resources and scripts under
`game/` so framework upgrades do not overwrite content.

Dependencies flow from game content to optional addons to Platformer Kit to
Godot. Platformer Kit must never preload game code, examples, or optional
modules.

## Recommended Boundaries

- Keep reusable character motion in `addons/platformer_kit/character/`; concrete player composition may remain in `scripts/player/` or move under `game/player/`.
- Keep generic room data, streaming, and entities in `addons/platformer_kit/world/`.
- Keep map discovery and fog policy in `addons/metroidvania_kit/map/discovery/`.
- Put authoring code in `addons/world_editor/authoring/room/` or `addons/world_editor/authoring/world/`.
- Put reusable debug-only tools in `addons/platformer_debug/`.
- Use Resource files for tuning values.
- Keep visual feedback free to scale, flash, or animate, but do not move `SpriteRoot.position` away from `Vector2.ZERO`.

## SubViewport Safety Border

The game uses a 322x182 `SubViewport` while treating 320x180 as the safe design frame. The extra 1 pixel on each side prevents edge artifacts during camera smoothing and small screen shakes.

The integer scale is calculated from the 320x180 safe frame, not the larger 322x182 viewport. At 1280x720 this gives 4x scale, so the displayed viewport is 1288x728 and is centered at `(-4, -4)`. The outer window clips the hidden safety border.

If you change the viewport size, preserve the same idea:

- Decide the safe gameplay size first.
- Add a small hidden border.
- Integer-scale the larger viewport.
- Round the final camera position to source pixels.

## Runtime Debug Overlay

`addons/platformer_debug/runtime/debug_overlay_2d.tscn` adds the read-only
velocity, collision, and sensor overlay to a scene. It is already instanced in
`scenes/runtime/world_root.tscn` (gameplay) and
`scenes/rooms/template/level_template.tscn` (room preview). Press **F3** to
toggle the vectors, the sensor lines, and the debug HUD together.

Point `subject_path` at the debug subject and `hud_path` at a `DebugHud` when
reusing the overlay elsewhere. Set `toggle_keycode` to change the key, or
`start_enabled` to control the initial state. The overlay only reads
`get_debug_state()`; it never mutates gameplay state.

## Adding Mechanics

Platform behavior is composed under `PlatformBody2D`: use
`WaypointMotionComponent2D`, `FallMotionComponent2D`, `ElevatorMotionComponent2D`,
`RiderTriggerComponent2D`, and `ConveyorSurfaceComponent2D` independently or
together. Native one-way platforms only require
`CollisionShape2D.one_way_collision`; set `one_way_collision_direction` when the
platform must block a side other than down.

Add `FogOccluderComponent2D` under the body when the platform should hide the
space behind it from the fog. It publishes the body's collision footprint to the
`fog_occluder` group and asks the fog to rebuild only when the footprint crosses
an 8 px cell, so a sliding platform keeps its shadow without repainting the mask
every frame. The same component serves doors and crates.

Author a door from a `StaticBody2D` plus `DoorComponent2D` (state, collision,
interaction and panel) and a `FogOccluderComponent2D`; `scenes/world/fog_door.tscn`
is the shipped recipe. Both components live in the kit and reach the fog through
group names only, so a project without `metroidvania_kit` can still use them.

A step-by-step authoring walkthrough (Chinese) with the scene trees, export
tables and a symptom table lives in `docs/components-tutorial.md`.

## Dash and One-Way Platforms

- The supplied Dash lives in `addons/platformer_abilities/abilities/dash/`.
  `DashAbilityDefinition.eight_directional` reads the vertical input too, and
  `direction_deadzone` / `direction_snap_degrees` keep the eight directions
  crisp. All Dash tuning stays in `default_dash.tres`.
- The Dash also exposes `freeze_seconds`, `end_speed`, `dash_attack_seconds`
  and `refill_cooldown_seconds`. `PlayerController` owns the global freeze and
  uses the dash-attack window for super, hyper, wavedash and wallbounce.
- `DashAbilityDefinition.max_charges` stores dashes like a jump count (0 =
  unlimited). The ability runtime owns the count and exposes `refill()`; the
  reference player calls `PlayerAbilityLoadout.update_dash_recharge()` from its
  controller while grounded or swimming, which is what makes water unlimited.
- Piercing is a game mechanic, not an addon feature:
  `game/player/one_way_dash_piercer.gd` is a child of the player scene and owns
  the rule. A dash crosses a one-way surface only when it travels in the
  direction that surface blocks; diagonal dashes never cross.
- Tile one-way platforms are painted in `SolidTiles` and live on physics layer 5
  (`one_way`). Godot tile collision has no per-tile one-way direction, so every
  tile one-way blocks downward; a downward dash drops the layer mask bit and the
  piercer restores it when the dash ends or the body leaves the platform.
  Because the mask is per layer, keep solid tiles on the `world` layer.
- A vertical or upward-facing one-way platform must be a body (for example a
  `StaticBody2D`) with `CollisionShape2D.one_way_collision` and
  `one_way_collision_direction` set to the direction it blocks (Godot 4.7+).
  Matching cardinal dashes add a temporary collision exception for that body, so
  never mix a solid shape and a pierceable one-way shape on the same body.
- The fog and map scanners classify one-way tiles by walking every TileSet
  physics layer, so new one-way layers stay supported without scanner changes.

## Celeste Movement Rules

- `MovementProfile` carries the rule layer: run acceleration, over-speed
  `run_reduce`, `air_multiplier`, variable jump, apex half gravity, fall caps,
  wall probes, stamina, super/hyper/wallbounce speeds and lift caps. Values are
  per second and work at 60 or 120 physics ticks.
- `PlayerController` is the state orchestrator. `NORMAL` uses
  `CharacterMotor2D`; `DASH`, `WALL_GRAB` and `WALL_SLIDE` are player-side
  states so Platformer Kit does not own stamina or the player graph.
- No grab action exists. Holding toward a wall attaches; up/down climbs;
  toward + jump is a climb jump; away/neutral + jump is a wall jump. The 0.2 s
  climb-jump conversion refunds the stamina, matching Celeste's forgiveness.
- `GameFreeze` is the global hit-stop autoload. It buffers jump/dash edges while
  frozen so instant super/hyper inputs are not lost.
- `EnvironmentProbe.lift_velocity` excludes a conveyor's
  `constant_linear_velocity`; `PlayerController` sets
  `platform_on_leave = DO_NOTHING` and applies capped lift itself.

Configure `WaypointMotionComponent2D.waypoints` as offsets from the platform's
authored position. Point zero must be `Vector2.ZERO`. Choose `PING_PONG` for
routes such as `1, 2, 3, 2, 1`, or `CYCLE` for `1, 2, 3, 1`; set
`arrival_pause_seconds` for the delay at each point.

## Checkpoints and Ability Rewards

Add `addons/platformer_kit/world/entities/save_point.tscn` below a source
room's `RoomContent/Entities`. Set a unique `entity_id` or `persistent_id`, set
the nested `SpawnPoint.spawn_id`, and choose `CONTACT` or `INTERACT`. The entity
updates respawn state before requesting an immediate save. `CONTACT` is the
prefab default; set `activation_mode = 1` for interaction-only checkpoints.
Bake the source room after adding it; never add checkpoints directly to generated
scenes. After changing an instanced entity prefab or a room-instance override,
re-bake and inspect the generated runtime — a source override equal to the
script default can be omitted by scene packing, exposing a different prefab
default.

Add `addons/platformer_abilities/entities/ability_pickup.tscn` for a persistent
ability reward. Assign a stable ID and an `AbilityDefinition`; use`addons/platformer_abilities/abilities/dash/default_dash.tres` for the supplied
Dash. Player-like receivers opt in with
`grant_ability_definition(definition: Resource) -> bool`. A rejected grant does
not consume the pickup.

## Doors: Portals and Shuttle Doors

Add `addons/platformer_kit/world/entities/world_door.tscn` below a source room's
`RoomContent/Entities` like a checkpoint. `PORTAL` doors pair two doors inside
one world; `SHUTTLE` doors pair a door in this world with a door in another
`WorldData` and move the player between worlds. Each side names the other through
`target_room_id` + `target_door_id` (plus `target_world` for a shuttle), so a
pair is bidirectional by construction. Contact activates the door, the state is
saved like a checkpoint, and the nested `ArrivalSpawn` is where the player lands
— keep it clear of the activation sensor. Bake the source room after adding one.
Full contract: `docs/doors.md`.

## Numbered Collectibles

Drop `scenes/world/number_pickup.tscn` under `RoomContent/Entities`, fill its
`number` (unique inside that world) and bake. The pickup bobs, glows with an
additive halo, and is collected on player contact; its collected state is saved
with the room. `Collectibles` (autoload) scans the world's baked rooms at
`world_ready`, so the collection screen knows every number without extra
authoring: the HUD badge shows `collected / total`, and `collection_toggle`
(default `J`) opens a full-screen grid where collected numbers are bright and
missing ones stay dim. Numbers are per world; a shuttle trip switches the shown
set. Full guide: `docs/collectibles.md`.

## Interaction and Prompts

`Interactable` areas (a door or checkpoint in `INTERACT` mode) are selected
through one detector on the player:

- `scenes/player/player.tscn` carries an `InteractionDetector` (Area2D, layer 0,
  mask 4, 14x14 at the feet) and a `PlayerInteractionController`. The controller
  fires the best candidate on a fresh `interact` press; remapping the action
  through the Input Mapping addon keeps working because nothing reads a key code.
- `scenes/ui/interaction_prompt.tscn` sits in `main.tscn`'s `HUD`, outside the
  game SubViewport, so the glyph is drawn at window resolution. It follows the
  selected interactable with the SubViewport's screen transform, shows the
  binding for the last used device (`E` on keyboard, `X` on a pad), and hides
  while the tree is paused, the player is control-locked, or nothing is in
  range. `Main` binds the runtime player to it.
- The prompt only appears for interactables whose `Interactable.enabled` is
  true, so `CONTACT`-mode doors and checkpoints never show it.

## Level Hierarchy and Stacked Worlds

The authoring hierarchy, bottom up: a **block** is one 1x1 chunk cell, a **room**
is one or more blocks (`RoomData.room_size_chunks`), a **world** groups rooms
with placements and connections (`WorldData`), and a **stack** is an ordered set
of worlds drawn as parallel slices in the editor's 3D view (`WorldStack`, saved
next to its world as `<world>_stack.tres`). Stacks are authoring data — the runtime
never reads them; they exist so several worlds can be seen and connected at once.
Open a world in the World editor and press `3D`; the left column becomes the
layer list (add, remove, reorder), and clicking a slice returns to that world in
2D. The add menu offers the worlds in `resources/worlds/world_catalog.tres` first
and then any other `WorldData` saved in `resources/worlds/`, so a world created
with **New World** can be layered before it is registered in the catalog (the
catalog still decides what the game's world-select screen lists). **Focus All**
frames the stack and **Reset View** restores the default orbit and frames it
again while the 3D view is open.

## World Selection

The start flow is `save slot -> world selection -> game`. The map list is the
`WorldCatalog` resource at `resources/worlds/world_catalog.tres`: add or remove
`WorldData` entries in the inspector and the menu builds the rows automatically.
Set each world's `display_name` and `description` for the card text. A save from
one world starts the selected world at its own start room; selecting the saved
world resumes its saved room.

Ladder zones and puzzle void collision bodies merge adjacent cells with
`CellRectMerger`. Author tiles or void footprints as before; painting more cells
does not create one collision shape per cell.

## Puzzle Sliding Regions

- A sliding piece uses `x_move_distance` / `y_move_distance` (cells per axis).
  The rule set generates and validates moves with the axis-specific distance.
- Set `PuzzlePiece.enable = false` to disable interactive control. The piece
  still occupies and blocks cells. Only primary moves are gated: a disabled
  void piece can still be moved by an A+ induced turn, but cannot be selected,
  dragged, or moved by direction input itself.
- A movable void slider is a `PuzzleTilePiece` whose `VoidTiles` child (collision
  disabled) defines its footprint. The script builds a player-only `VoidBody` on
  physics layer 4 (`void`). Other sliders pass through it; the player cannot
  enter it on foot or ride it, but may be carried through it while riding a
  normal piece. Give the piece `x_move_distance` / `y_move_distance` for its
  own moves. Do not mix `VoidTiles` with `SolidTiles`/`OneWayTiles`; void wins and
  the wall layers are ignored.
- Void pushes are atomic: if the mover's target min rectangle fully encloses a
  void's current min rectangle, the void moves by the opposite displacement.
  Validate the whole void footprint against board bounds, `blocked_cells`, and
  the player's post-move cell; any invalid void target rejects the entire turn.
  Partial overlap and void-primary moves never push another piece, and pushes do
  not chain.
- Keep void visuals above normal pieces but below the player and mode overlay
  (for example `z_index = 5` for the piece). Reusable legacy static region:
  `scenes/puzzle/puzzle_void_zone.tscn`; static `PuzzleVoidZone` still works for
  cells that never move.
- In slider mode, `Z` undoes one operation and `R` resets the board; reset is
  itself undoable. Both are scoped to boards whose rectangle contains the
  player, and every overlapping board reacts independently. A compound primary
  move plus its induced void moves is one history entry. `Z` takes priority over
  `R` in the same frame. The player is never moved by reset.
- Gamepad selection uses the project actions `slider_prev`, `slider_next`,
  `slider_select_rider`, and `slider_cancel`. `PuzzleBoard` filters these to
  `enable` + non-`STATIC` pieces in scene order. Entering drag mode auto-selects
  the ridden piece, or the first eligible piece. Controller selection is scoped
  to the board containing the player or a board the player is riding.
- `undo` keeps Z and gains Back/View; `reset` keeps R and gains Start/Menu.
  New slider actions have no keyboard defaults; assign them through the existing
  Input Mapping menu if needed.
- Test selection through `PuzzleBoard._handle_selection_input(previous, next,
  select, cancel)` with explicit booleans. Do not rely on
  `Input.action_press()` edge timing in headless tests.
- Right-stick aiming uses `aim_left/right/up/down` actions and
  `PuzzleBoard._handle_stick_selection(aim)`. The board chooses the nearest
  `_controllable_pieces()` center inside a 45-degree cone, draws
  `PuzzleAimArrow`, and switches selection only on release. The explicit aim
  vector is the test seam; no history entry is created.
- A successful slide that carries the rider earns one air jump on leaving drag
  mode. `PuzzleBoard` grants it through
  `PlayerController.grant_air_jump()`; the motor exposes the one-shot state as
  `MovementContext.air_jump_available`, consumes it on the next jump, and clears
  it when grounded or respawned. Selecting without moving, a rejected move, and
  a forced exit do not grant it. Extend the board rather than setting the motor
  flag directly so the carry bookkeeping stays authoritative.

### Generated and shuffled boards

- `PuzzleBoardAuto` replaces hand-authored `PuzzleTilePiece` children for
  equal-size puzzles. Assign `source_layer_path` to a `TileMapLayer` holding the
  whole picture and set `piece_size` / `puzzle_size`; the board splits the
  painted area into chunks and writes one generated piece per chunk. An
  optional `void_layer_path` layer marks void slider footprints (void wins over
  solid cells in the same chunk).
- Generation is editor-only (`@tool`). Generated pieces carry
  `meta("puzzle_generated")` and are owned by the edited scene root, so they are
  saved into the room source scene and baked with it. Regeneration only removes
  generated nodes. The board regenerates automatically when the source layers
  or export values change, and the inspector exposes a `重新生成` tool button for
  forced rebuilds.
- Put source layers outside `RoomContent` (for example under `PreviewOnly`) so
  the bake never sees them, and place the board at the puzzle's top-left corner.
  Source positions only provide cell contents.
- `PuzzleBoardShuffler` walks random legal turns on load (default 120) and
  adopts the result as the new initial layout, so `R` restores the scrambled
  board instead of the authored one. `void_only = true` only walks turns that
  move a void slider (primary or A+ induced); `seed = 0` randomizes per load,
  any other value reproduces the same layout.
- Place the shuffler after the board in the same parent
  (`board_path = ^"../PuzzleBoard"`) for a synchronous ready-pass scramble, or
  as a child of the board (`board_path = ^".."`, the default) and the shuffler
  waits for the board's `ready` signal. `shuffle_now()` scrambles again at
  runtime for debugging.
- Scrambling goes through `rules.get_legal_moves()` and
  `rules.resolve_turn()`, so every step is legal and reversible: a shuffled
  board is always solvable. History is cleared, the player is not moved, and
  the walk is pure data (`PuzzleScrambler`), so it can be tested headlessly.

## Exploration: Fog Zones, Crumble Tiles, Doors

See `docs/fog-zones-and-crumble.md` for the full rules and the test world.

- The room template has three tile layers: `BackTiles` (background),
  `SolidTiles` (playfield) and `DetailTiles` (front). Glass, one-way platforms,
  crumble tiles and ladders are all painted in `SolidTiles`; the tile decides the
  behaviour (glass atlas `0,3`, crumble `3,0`/`3,4`, ladder `0,7`).
- Fog is per room and uses the current camera view, so a 1x1 room reveals as one
  screen and a 2x1 room reveals screen by screen. Solid wall cells block sight
  automatically; glass is see-through. Sight spreads in eight directions, so a
  one-cell diagonal crack is see-through by design.
- One-way platforms block downward sight when the Game setting
  **One-way Platforms Block Sight** is on (default). Standing on top makes the
  space underneath a sealed pocket.
- `scenes/world/fog_zone.tscn` is an authored rectangle under
  `RoomContent/Entities`: `Dark` hides its cells, `Light` always lights them.
  `reveal_on_enter` lights it on entry, `restore_on_exit` re-darkens it on exit
  (explored cells stay on the map), and `focus_room` darkens the rest of the
  room towards the player while inside.
- `scenes/world/fog_door.tscn` blocks movement and sight while closed; interact
  toggles it. It is a prefab of `DoorComponent2D` (state, collision, interaction,
  panel) and `FogOccluderComponent2D` (sight), so an author can rebuild the same
  door at another size or with other art.
- Occluders join the `fog_occluder` group and expose `is_occluding()` and either
  `get_world_rect()` or `get_occluder_cells()` /
  `get_occluder_one_way_cells()`. `FogOccluderComponent2D` gives any platform or
  solid body that behavior without extra wiring, and `PuzzlePiece` /
  `PuzzleTilePiece` already implement the cell interface, so sliders block sight
  and refresh the fog as they move.
- Phantom walls: instance `scenes/world/phantom_wall.tscn` under
  `RoomContent/Entities` and paint tiles on the instance root. The layer has
  collision disabled and carries `PhantomWallComponent2D`, so the wall looks like
  terrain, can be walked through, and blocks sight until the player touches it.
  Erase the same cells from `Terrain/SolidTiles` — the painted wall replaces the
  solid one. `reveal_on_contact` can be turned off and `reveal()` called from an
  ability or a switch instead.
- `CrumbleRuntime` shakes a crumble cell for 0.25 s, erases it, and writes it
  back after 1.5 s; leaving the room restores everything.
- `scenes/levels/test/test_world_runner.tscn` starts the test world directly;
  edit `scenes/levels/test/*.tscn`, bake, then run the runner.

## Water and Gas

The fluid systems live in the **Fluid Kit** addon (`addons/fluid_kit/`); see
`addons/fluid_kit/README.md` for the node reference, every tunable parameter, the
interactor recipes and the demos, and `docs/water-and-mist.md` for the project
guide. In short:

- Water is a room extension (`WaterField`, group `water_field`) fed by `WaterBasin`
  markers; `WaterGate` holds the water until the room is entered. Column floors are
  scanned from `SolidTiles` bottom-up, so painting terrain is enough. Splashes are
  requested through the `splash_requested` signal (the template assigns
  `splash_scene`).
- The player composes `PlayerWaterMotion` (buoyancy, swimming, entry depth) the
  same way as `LadderMotionComponent2D`; keep water feel in that component, not in
  the controller.
- Gas is `Atmosphere`: a full 2D Navier-Stokes field (advection, buoyancy forces,
  viscosity, Jacobi pressure projection) moving three passive densities (heavy
  sinks, neutral drifts, light rises); the CPU `FogGrid` is the headless fallback.
  `FogLight` markers light it, an 8 px solid+water mask keeps it out of walls and
  pools, and the Game setting **Gas Simulation** (`atmosphere_enabled`) toggles it
  live. Add `GasInteractor` nodes to entities that should push, emit or blast gas.
  Add a `LIGHT` `FogZone` covering any room with water, otherwise the exploration
  fog clips the pools and the gas into a black band.
- Regenerate `scenes/levels/test/water_hall.tscn` with
  `godot --headless --path . -s res://tools/build_water_room.gd`. The room is
  generated rather than inherited from the template, so change the generator for
  layout edits.

## Map and Minimap

See `docs/map.md`. The map is generated, never authored:

- `MapDefinitionBuilder.from_world(world)` builds rooms and links from the
  `WorldData` the game is running, so the map follows room placement and size.
- `RoomTerrainSnapshot` scans a baked room's terrain once (cached by file time)
  to know each cell's kind for the precise map.
- `MapExploration` converts the fog's `room:x,y` ids into per-room local cells;
  `MapExplorationSource` merges the persistence bridge (all visited rooms) with
  the fog (the loaded room).
- `MapPreciseRenderer` paints explored cells only; unvisited rooms stay dark
  plates. `MapGridRenderer` draws one block per room with brightness equal to
  its exploration ratio.
- `MapScreen` (full map) and `MapMinimap` are created by `game/map/map_host.gd`,
  which is added to the HUD in `scenes/app/main.tscn` and the test world runner.
- Controls: `M` or left stick click toggles the map, `Tab` / `Y` switches style,
  `Esc` closes, the wheel zooms. Input actions `map_toggle` and `map_style`.

## The Loop Cistern World

See `docs/loop-world.md`. A four-room ring built from the template: a crumbling
bridge over a pool, falling platforms with a swimmable low road, a
rider-triggered elevator, two conveyors, a dash pickup and a dash gap that drops
back into the starting room.

- `scenes/levels/loop/*.tscn` are the editable source rooms; bake them before
  running the world.
- `scenes/levels/loop/loop_runner.tscn` starts the world directly with the debug
  HUD and overlay enabled.
- The elevator is `ElevatorMotionComponent2D` (rider-triggered, returns by
  itself); pair it with a rider trigger whose `trigger_once` is false.

## World Editor Workbench

The World main screen is a three-column workbench: room list, canvas, inspector
and a status bar. Diagnostics are printed to the editor Output panel.

- **Room list** shows a status dot (fresh / stale / error / unknown), the display
  name, chunk size and origin. Search filters by name/id; `Ctrl`/`Shift` selects
  several rooms; right-click opens Open Source / Bake / Validate / Focus /
  Set as Start / Remove. Double-click opens the source scene.
- **Canvas**: terrain previews sit under room frames; room labels show
  `id · W×H · (cx,cy)`, statuses tint the outline, the start room gets a star.
  `RoomAnnotationService` instantiates each baked runtime scene off-tree and
  draws spawns (`S`), entrances (`E`) and entity markers with hover tooltips.
  Drag empty space to box-select (intersection), `Ctrl+click` toggles a room,
  drag a selected room to move the whole group (one undo action), `Delete`
  removes the selected references, `Esc` clears, `Ctrl+A` selects all.
- **Inspector** is read-only: display name, id, size, origin, source/runtime/
  terrain paths, spawn and entrance lists, plus the Start row. Metadata such as
  `display_name` and `room_id` stays authorative in the source scene; rebaking
  would overwrite edits made here. Room actions live in the command bar (they
  apply to the whole selection) and the context menus, not in the inspector.
  Connection editing lives at the bottom.
- **New Room** opens a small wizard (room id, display name, source path).
  It writes the room as an inherited scene of `world_editor/room_template_scene`
  (so the template's player/camera/debug children stay instanced), imports and
  bakes it into the saved world, then opens the source scene for editing.
- **Bake Stale (N)** bakes every room whose source changed since the last bake.
  The count comes from the same fingerprint comparison as the list status.
- **Diagnostics** go to the editor Output panel, not a separate problems panel:
  room statuses, the session's last bake/validate failures and
  `WorldLayoutModel.validate_world()` are printed as
  `[World Editor][ERROR] ...` / `[World Editor][WARNING] ...`. The list and
  inspector still show the per-room status label, and repeating the same
  diagnostics is suppressed until the set changes.
- **Status** comes from `authoring/world/room_status_service.gd`: `fresh` when
  `RoomData.source_fingerprint` matches the current source sha256 and both
  artifacts exist, `stale` when the source changed after the last bake, `error`
  for missing sources/artifacts or a failed bake this session, and `unknown`
  when the room has no fingerprint yet. Hashes are cached by (path, mtime, size).
- New entity types appear on the canvas by extending
  `authoring/world/room_annotation_service.gd`; new room statuses plug into the
  status service and the list/inspector color maps.
- The workbench follows the **editor language** (Editor Settings → Interface → Editor Language, `zh*` uses the `zh_CN` table,
  everything else uses English (`world_editor_localization.gd`, `t(key, args)`).
  Room status messages carry a `message_key` so the list, inspector and problems
  panel show the same translated text. Add new UI strings to both tables.

## Settings Pages

The settings window is a full-screen scene (`scenes/ui/settings.tscn`) loaded
next to the main menu in `scenes/app/main.tscn`. It is a small navigation shell
(`scripts/ui/settings_menu.gd`) around four top tabs: Game, Audio, Video and
Controls. Rows are built from definitions in
`scripts/save/settings_catalog.gd` by `SettingsRow`; categories are
`SettingsPage` instances in the settings scene with their `section` export set.
There are no sub-headings inside a category: every setting is one row, and the
page scrolls when the rows overflow.

- To add a setting, append a `toggle`, `option`, `slider`, or `action`
  definition to the catalog and add its label, description and option labels to
  `localization/menu.csv`. Do not edit the menu script.
- `GlobalSettings.get_value(key)` / `set_value(key, value)` is the UI contract.
  Typed accessors such as `is_fog_enabled()` remain for gameplay code and
  delegate to the same store, so existing `user://settings.json` keys keep
  working.
- Video settings apply immediately: `resolution_scale` is the integer pixel
  scale (2X/4X/8X/16X of 320×180), `display_mode` supports windowed, exclusive
  fullscreen and borderless fullscreen, `vsync_enabled` toggles VSync, and
  `fps_limit` sets both `Engine.max_fps` and
  `Engine.physics_ticks_per_second` to the same value.
- The game view is centered at the largest integer scale that fits the window;
  `resources/ui/window_background.png` fills the remaining area, so a non-16:9
  window does not show black bars. The background is a replaceable `Texture2D`.
- `mute_on_focus_loss` mutes the Master bus when the application loses focus and
  restores it on return; it does not pause the game or change the volume slider.
- `reset_defaults()` restores every catalog default and still resets the input
  mapping service from the same button.

Good first game-specific extensions:

- Moving platforms.
- Ladders.
- Simple hazards.
- Room transition tests.
- Additional data-driven abilities.

For rooms, edit source scenes only. Generated runtime scenes, terrain scenes, and `RoomData` resources are bake outputs. `RoomData` is reusable local content; `WorldData.placements` owns each room's chunk origin and `WorldData.connections` owns transitions.

Depend on optional combat or progression addons from game content; never add
concrete enemies, items, or story rules to Platformer Kit.
