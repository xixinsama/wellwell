# Spike Tile Hazard Design

Date: 2026-11-22
Status: Approved for implementation

## Summary

Make atlas tile `(0,8)` a hazard spike. Its three alternatives are the same
spike rotated in 90-degree steps (up, right, down, left). Spikes do not block
movement; each spike cell gets a half-tile trigger area (`8x4` for floor/ceiling
spikes, `4x8` for wall spikes). Touching a trigger returns the player to the
last checkpoint or room spawn and plays the existing hurt effect.

## Existing Context

- `resources/tilesets/primordial_tileset.tres` has a single atlas source, 8x8
  tiles. `(0,8)` exists with no physics polygon and no alternatives; its art is
  two upward ice spikes occupying the lower half of the cell.
- `scenes/rooms/template/level_template.tscn` is the base of every room scene.
  Baked room terrain is sliced from the world terrain by `RoomBaker`, which
  duplicates the room source's `Terrain` node so helper nodes such as
  `LadderAreaBuilder` survive into `scenes/rooms/generated/<room>/terrain.tscn`.
- `scenes/world/killzone.tscn` is an `Area2D` on collision layer 0, mask 2. Its
  script respawns any body in the `player` group at that body's `spawn_position`
  and then requests `play_hurt_effect()`.
- `spawn_position` is the player's current checkpoint / room spawn. It is the
  same field kill zones already use.

## Behavior

- The spike art is unchanged. Alternatives only change the tile transform.
- The spike tile has no solid collision polygon, so it never blocks the player,
  casts light occluders, or becomes a wall in the TileSet.
- Every spike cell produces one `Killzone` trigger sized to the spike body:
  - up: bottom half, 8x4
  - right: left half, 4x8
  - down: top half, 8x4
  - left: right half, 4x8
- Adjacent spike cells produce adjacent, non-overlapping triggers.
- On contact the player is respawned at `spawn_position` first, then the hurt
  effect is played. No health is subtracted and no death screen is added.
- Trigger areas are only generated for rooms whose terrain is (re)baked after
  the builder is added. Rooms with no `(0,8)` cells are unaffected.

## Atlas Alternatives

Alternative ids and transforms (Godot applies transpose, then flip_h, then
flip_v):

| id | flags | spike direction | trigger half |
| :--- | :--- | :--- | :--- |
| 0 | none | up | bottom 8x4 |
| 1 | `flip_h` + `transpose` | right | left 4x8 |
| 2 | `flip_h` + `flip_v` | down | top 8x4 |
| 3 | `transpose` + `flip_v` | left | right 4x8 |

`0:8/next_alternative_id` becomes 4. The normal atlas is re-baked so its
TileSet mirrors the alternatives and their flags.

## Components

### `scripts/world/spike_hazard_area_builder.gd`

`class_name SpikeHazardAreaBuilder extends Node2D`.

- `const SPIKE_ATLAS := Vector2i(0, 8)`.
- On `_ready()` and on `rebuild()`, clears its children, walks every
  `TileMapLayer` under its parent `Terrain`, and finds cells whose source id is
  0 and atlas coordinates are `SPIKE_ATLAS` (any alternative).
- For each cell it reads `layer.get_cell_tile_data(cell)` and uses
  `flip_h` / `flip_v` / `transpose` to transform the base half-tile rectangle
  `Rect2(-4, 0, 8, 4)` exactly the way `TileData.get_transformed_vertices()`
  does.
- It instantiates `scenes/world/killzone.tscn`, replaces its collision shape
  with a `RectangleShape2D` of the transformed half-tile size, positions it at
  the transformed rectangle's center in global space, names it
  `SpikeZone_<x>_<y>`, and adds it as a child.
- It returns the number of zones built, mirroring `LadderTileAreaBuilder`.

### `scenes/rooms/template/level_template.tscn`

Add a `SpikeHazardAreaBuilder` node under `RoomContent/Terrain`, next to
`LadderAreaBuilder`. Room scenes inherit it, and `RoomBaker` copies it into the
sliced terrain, so the runtime and room preview both build the zones.

### Tests

New `tests/world/test_spike_hazard.gd`, preloaded by `tests/runtime_suite.gd`:

- the TileSet has four `(0,8)` alternatives in id order 0, 1, 2, 3 with the
  expected flags, and none has a solid collision polygon;
- a synthetic terrain with one cell of each orientation builds zones with the
  expected `8x4` / `4x8` sizes and centers, and zones have layer 0 / mask 2;
- emitting `body_entered` with a fake player respawns it at `spawn_position`
  before playing the hurt effect;
- the template and a baked/staged terrain carry the builder node, while runtime
  zones are not serialized into the terrain scene.

## Non-goals

- No spike health, knockback, invulnerability window, or death animation.
- No player-side per-frame tile scanning and no manual per-room hazard nodes.
- No changes to the spike art, light occlusion, gas/water solidity, or the
  existing kill zone contract.
