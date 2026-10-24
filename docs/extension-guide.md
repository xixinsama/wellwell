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
- A successful slide that carries the rider earns one air jump on leaving drag
  mode. `PuzzleBoard` grants it through
  `PlayerController.grant_air_jump()`; the motor exposes the one-shot state as
  `MovementContext.air_jump_available`, consumes it on the next jump, and clears
  it when grounded or respawned. Selecting without moving, a rejected move, and
  a forced exit do not grant it. Extend the board rather than setting the motor
  flag directly so the carry bookkeeping stays authoritative.

Good first game-specific extensions:

- Moving platforms.
- Ladders.
- Simple hazards.
- Room transition tests.
- Additional data-driven abilities.

For rooms, edit source scenes only. Generated runtime scenes, terrain scenes, and `RoomData` resources are bake outputs. `RoomData` is reusable local content; `WorldData.placements` owns each room's chunk origin and `WorldData.connections` owns transitions.

Depend on optional combat or progression addons from game content; never add
concrete enemies, items, or story rules to Platformer Kit.
