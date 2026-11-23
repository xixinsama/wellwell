# Phantom Wall Component — Design

## Context

The fog work introduced `FogOccluderComponent2D`, which publishes a body's
collision footprint to the `fog_occluder` group. The reference game also wants
secret passages: a wall that looks exactly like the terrain, can be walked
through, and hides what is behind it until the player touches it.

Rooms are tile-based. A wall drawn in the ordinary `SolidTiles` layer always
collides, so a walk-through wall has to be drawn on a layer with collision off.
`TileMapLayer.collision_enabled = false` gives exactly that, and the tiles still
render with the room's own tileset, so the illusion is pixel-perfect.

## Goal

- One component plus one single-node prefab that an author can drop under
  `RoomContent/Entities` and paint.
- The wall blocks sight while it stands; touching it opens both the visual and
  the sight blocker.
- State is runtime-only: the wall is back the next time the room loads.

## Non-goals

- Solid-until-discovered walls, phase walls, and ability/interaction reveals.
  `reveal()` is public and `reveal_on_contact` can be turned off, so those modes
  can be layered on later without changing the component.
- Persisting "discovered" across room loads.
- Light shadows (the light field only reads solid tiles).
- A demo wall in the test world.

## Design

`addons/platformer_kit/world/components/phantom_wall_component_2d.gd`
(`@tool`, `extends FogOccluderComponent2D`), so the fog contract, group
membership, cell-change refresh and editor footprint are inherited rather than
re-implemented.

Overrides and additions:

- `_world_rect()` — the union of the painted cells of the tile layer (each cell
  centred through `map_to_local`, expanded by `TileSet.tile_size`). Falls back to
  the inherited body-shape footprint when it is not sitting on a tile layer.
- `is_occluding()` — false after `reveal()`.
- `get_tile_layer()` — `tiles_path` when set, otherwise the node itself.
- `reveal() -> bool` — marks the wall revealed, refreshes the fog, fades the
  layer out, emits `wall_revealed()`. Idempotent.
- `reset_component()` — restores visibility, alpha and occlusion.
- `_build_sense()` — an `Area2D` (`collision_layer = 0`, `collision_mask = 2`)
  covering the footprint plus `sense_margin_pixels`; `body_entered` on a
  `CharacterBody2D` calls `reveal()` when `reveal_on_contact` is on.
- `_validate_property()` hides the inherited `body_path`, `size_override` and
  `footprint_offset`, which do not apply to a painted wall.

`scenes/world/phantom_wall.tscn` is a single `TileMapLayer` root with the game's
tileset assigned, `collision_enabled = false`, and the component attached. The
root of an instanced scene is editable, so the author paints cells directly on
the instance — no editable children.

Authoring contract: the wall replaces solid tiles, so erase the same cells from
`Terrain/SolidTiles`; otherwise the old collision still blocks the player and the
secret does not exist.

## Testing

- `tests/world/test_phantom_wall.gd`: the layer does not collide, the footprint
  follows the painted cells, `reveal()` clears occlusion and hides the painting,
  the fake fog receives a refresh, `reset_component()` restores it.
- `tests/world/test_fog_visibility.gd`: the painted cells stop the sight fill,
  and after `reveal()` the same cells no longer block.

## Documentation

`docs/extension-guide.md`, `docs/fog-zones-and-crumble.md`,
`addons/platformer_kit/README.md`, `docs/project-structure.md`, `CHANGELOG.md`.
