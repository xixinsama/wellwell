# Tilemap, Exploration Fog, and Save Design

Date: 2026-09-04
Project: wellwell
Status: Ready for user review

## Goal

Build a reusable 2D platformer template level around Godot 4.7
`TileMapLayer` resources, then add exploration-based fog of war that can
hide unseen rooms behind black fog. Exploration must persist through a
lightweight save system modeled after `after-blast`, but scaled down for this
template.

The first playable result is a two-room test level:

- The left and right rooms are separated by solid wall tiles.
- The player starts in the left room and can only see cells visible from the
  left side.
- After the player reaches the right room, right-side cells are discovered and
  stay uncovered on the map.
- Solid walls block line of sight, so content behind the separator is hidden
  until reachable from the other side.

## Existing Context

`wellwell` currently uses a compact 320x180 safe gameplay frame inside a
322x182 `SubViewport`. The playable world is instantiated from
`scenes/game.tscn`, where the graybox level is authored as separate
`StaticBody2D` and `Polygon2D` nodes. The player, pixel camera, reset zone,
debug HUD, and grid overlay are already present and should remain intact.

The project targets Godot 4.7. Godot 4.7 supports `TileMapLayer` as the modern
tilemap node and `TileSet` physics layers for tile collision. The template
should use those instead of introducing older `TileMap`-centric patterns.

`after-blast` uses a clean save split:

- `SaveSnapshot` owns versioned game progress fields and serialization data.
- `SaveCodec` converts snapshots to and from JSON.
- `SaveStorage` handles `user://saves`, temporary files, and backups.
- `SaveManager` is an autoload that selects slots and commits snapshots.
- `GlobalSettingsStore` persists settings separately in `user://settings.json`.
- `ExplorationState` stores discovered map/content IDs and percent helpers.

`wellwell` should borrow this shape, not the full feature set.

## Architecture

Add three focused subsystems:

1. Tilemap level authoring
2. Exploration fog runtime
3. Lightweight save and settings persistence

The subsystems communicate through small data surfaces:

- The tilemap exposes solid/vision-blocking cells.
- The fog controller consumes player position and blocking cells, then updates
  discovered cell IDs.
- The save manager owns the snapshot and persists discovered cells.

No player movement logic should move into the fog or save system. The existing
`PlayerController` remains responsible for movement and respawn.

## Tilemap Level

Create a template tileset under `resources/tilesets/` and replace the graybox
StaticBody platforms in `scenes/game.tscn` with layered tilemaps.

Recommended scene layout:

```text
WorldRoot
  Background
  Level
    BackTiles: TileMapLayer
    SolidTiles: TileMapLayer
    DetailTiles: TileMapLayer
    SpawnPoint
    ResetZone
  Player
  PixelCamera2D
  FogOfWar
  GridOverlay
  TuningHotkeys
```

Layer responsibilities:

- `BackTiles`: non-colliding background wall/floor fill.
- `SolidTiles`: colliding terrain and vision blockers.
- `DetailTiles`: non-colliding edge trim, cracks, highlights, and test markers.

The initial `TileSet` should use 8x8 tiles to match the player visual and debug
grid. It should include at minimum:

- solid block
- left/right/top/bottom wall edges
- one-way platform visual tile
- floor trim
- background brick or panel
- marker/detail variants for authored map readability

`SolidTiles` must use TileSet physics layer 0 with collision layer bit 1
(`world`) so the current player collision continues working.

## Test Map Shape

The first map should be wide enough for camera follow and fog validation, but
small enough to inspect quickly.

Proposed layout:

- left room around x = -176 to x = 104
- right room around x = 128 to x = 408
- separator wall around x = 112 to x = 128
- a lower or upper passage that allows the player to travel between rooms
- spawn in the left room
- reset zone below both rooms

This produces a clear validation case: standing in the left room cannot reveal
the right room through the separator, but entering the passage and right room
reveals new cells permanently.

## Fog Runtime

Add `scripts/world/fog_of_war.gd` as a `Node2D` controller. It should render
black rectangles aligned to the same 8x8 grid as the tilemap.

State model:

- `currently_visible: Dictionary[Vector2i, bool]`
- `explored_cells: Dictionary[String, bool]`
- `cell_size := Vector2i(8, 8)`
- `reveal_radius_cells` exported, initially around 11 to cover most of the
  320x180 viewport without revealing through blockers.

Each physics frame or throttled interval:

1. Convert player global position to a fog cell.
2. Enumerate cells inside the reveal radius.
3. For each candidate cell, test line of sight from player cell to candidate.
4. If no solid blocking tile lies on the cell ray, mark it currently visible
   and discovered.
5. Redraw the fog overlay.
6. If new cells were discovered, ask `SaveManager` to mark the snapshot dirty
   and commit on a short debounce.

Line of sight should use a grid traversal algorithm over cell coordinates. For
the template, Bresenham-style stepping is sufficient and easy to test. A solid
cell blocks vision unless it is the player's own cell or the target cell being
revealed. This allows wall faces to be seen while hiding what is behind them.

Rendering:

- Unexplored cells draw as opaque black.
- Explored but not currently visible cells are configurable. For the first
  implementation, draw them transparent because the user's requirement is that
  once a map area has been entered, its fog is unfolded.
- A later setting can draw explored/offscreen cells as semi-transparent, but it
  should not be part of the first implementation.

The fog node should cover a configured map rectangle rather than infinite space.
This keeps draw cost stable and gives the save system a finite exploration
domain for progress calculations.

## Save System

Add lightweight save files under `scripts/save/`:

- `save_snapshot.gd`
- `save_codec.gd`
- `save_storage.gd`
- `save_manager.gd`
- `global_settings_store.gd`
- `global_settings_manager.gd`

Register autoloads in `project.godot`:

- `SaveManager="*res://scripts/save/save_manager.gd"`
- `GlobalSettings="*res://scripts/save/global_settings_manager.gd"`

`SaveSnapshot` fields:

- `FORMAT_VERSION := 1`
- `slot := 1`
- `respawn_position := Vector2.ZERO`
- `explored_cells: Array[String] = []`
- `saved_unix_time := 0`

Cell IDs should serialize as stable strings, for example `"level_01:12,-4"`.
This avoids Godot JSON ambiguity around `Vector2i` keys and keeps future map IDs
available.

`SaveStorage` should write `user://saves/slot_1.json` through a temporary file
and keep `slot_1.backup.json`, following the `after-blast` approach. Reads
should fall back to the backup if the primary is missing or invalid.

`SaveManager` should expose:

- `start_or_continue(slot := 1) -> SaveSnapshot`
- `commit(snapshot := null) -> bool`
- `mark_cell_explored(cell_id: String) -> bool`
- `has_explored_cell(cell_id: String) -> bool`
- `get_explored_cells() -> Array[String]`

For this template, use one slot by default. The API should still accept a slot
argument so a future save menu can expand without rewriting storage.

`GlobalSettingsManager` should load and save a small dictionary separately from
game progress. Initial fields:

- `display_mode`
- `master_volume`
- `music_volume`
- `sfx_volume`
- `fog_enabled`

No settings UI is required in the first implementation.

## Data Flow

Startup:

1. `SaveManager` autoload initializes storage.
2. `WorldRoot` or `FogOfWar` calls `SaveManager.start_or_continue(1)`.
3. `FogOfWar` loads saved explored cell IDs into its local dictionary.
4. The first visibility pass reveals cells around the spawn point.

During play:

1. Player moves.
2. Fog controller calculates visible cells using `SolidTiles`.
3. Newly visible cells become explored.
4. New explored IDs are added to the current snapshot.
5. Save manager commits after a debounce to avoid writing every frame.

On respawn:

- The player returns to the spawn/checkpoint position.
- Exploration remains unchanged.
- Current visibility updates from the new player position.

## Error Handling

Save decode failures should return `null`, not partially mutated data. Storage
should attempt primary first, backup second. If both fail, the manager creates a
fresh snapshot.

Fog should degrade gracefully:

- If the player path is missing, it should draw all unexplored fog and push one
  warning.
- If the solid tile layer is missing, it should reveal by radius without wall
  blocking and push one warning.
- If `SaveManager` is not registered, fog should still work for the session
  without persistence.

## Tests and Verification

Add a minimal headless runtime test suite under `tests/` for logic that does
not require rendering:

- `SaveCodec` round-trips format version, slot, respawn position, and explored
  cell IDs.
- `SaveStorage` falls back to backup when the primary file is invalid.
- `FogOfWar` line of sight blocks cells behind solid wall cells.
- `FogOfWar` preserves discovered cells after visibility changes.

Manual verification in Godot:

1. Run `res://scenes/main.tscn`.
2. Confirm the player starts in the left room.
3. Confirm right-room tiles are blacked out from the left room.
4. Move through the passage into the right room.
5. Confirm right-room fog unfolds.
6. Restart the scene and confirm discovered cells reload from `user://saves`.
7. Confirm collisions, reset zone, debug HUD, grid overlay, and pixel camera
   still work.

## Out of Scope

Do not build these in the first pass:

- save-slot menu UI
- save preview screenshots
- minimap UI
- room streaming
- dynamic fog light textures
- enemies, pickups, combat, or progression gates
- editor baking tools

These can be added later on top of the same snapshot and explored-cell format.
