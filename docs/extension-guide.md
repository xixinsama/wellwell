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
`WaypointMotionComponent2D`, `FallMotionComponent2D`,
`RiderTriggerComponent2D`, and `ConveyorSurfaceComponent2D` independently or
together. Native one-way platforms only require
`CollisionShape2D.one_way_collision`; no framework script is needed.

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
ability reward. Assign a stable ID and an `AbilityDefinition`; use
`addons/platformer_abilities/abilities/dash/default_dash.tres` for the supplied
Dash. Player-like receivers opt in with
`grant_ability_definition(definition: Resource) -> bool`. A rejected grant does
not consume the pickup.

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

Good first game-specific extensions:

- Moving platforms.
- Ladders.
- Simple hazards.
- Room transition tests.
- Additional data-driven abilities.

For rooms, edit source scenes only. Generated runtime scenes, terrain scenes, and `RoomData` resources are bake outputs. `RoomData` is reusable local content; `WorldData.placements` owns each room's chunk origin and `WorldData.connections` owns transitions.

Depend on optional combat or progression addons from game content; never add
concrete enemies, items, or story rules to Platformer Kit.
