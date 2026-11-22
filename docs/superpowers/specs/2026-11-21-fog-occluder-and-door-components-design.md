# Fog Occluder and Door Components — Design

## Context

The platform components under `addons/platformer_kit/platforms/components/` move a
`PlatformBody2D` but say nothing to the fog of war. A falling or sliding platform
can sit right in front of the player and the room behind it is still revealed.

The one thing that does hide space today is the fog door
(`scripts/world/fog_door.gd` + `scenes/world/fog_door.tscn`), a bespoke game script
that mixes five jobs: collision, interaction, sight blocking, panel drawing and
shape sizing. The puzzle piece (`scripts/puzzle/view/puzzle_piece.gd`) implements
the same sight-blocking contract a third way, and refreshes the fog on every
frame it moves.

The fog already exposes a duck-typed contract: a node in the `fog_occluder` group
implementing `is_occluding() -> bool` and either `get_occluder_cells()` /
`get_occluder_one_way_cells()` or `get_world_rect() -> Rect2`. Nothing new is
needed in `FogOfWar` itself.

## Goal

1. Any solid body (platform, door, crate) can hide what is behind it by adding
   one component, with no change to existing rooms until an author opts in.
2. The door becomes composable from small components, so authors can build doors
   of their own size/art, and its sight blocking is the same component platforms
   use.
3. The occluder contract lives in one place, and the fog is refreshed once per
   crossed 8 px cell instead of once per frame.

## Non-goals

- Dynamic re-darkening. Fog exploration is monotonic per room visit: an occluder
  can stop a cell from being revealed for the first time, but it cannot push an
  already explored cell back into darkness. That matches the current door
  behavior and keeps `FogOfWar` untouched.
- Applying occlusion to the existing rooms in this change.
- Migrating `PuzzlePiece` to the new component.
- Light shadows, water or gas occlusion.

## Component A — `FogOccluderComponent2D`

File: `addons/platformer_kit/platforms/components/fog_occluder_component_2d.gd`
(`@tool`, `extends Node2D`).

Marks the host body's collision footprint as a sight blocker. It is added as a
child of a `StaticBody2D` / `AnimatableBody2D` / `PlatformBody2D`, or pointed at
one through `body_path`.

Exports:

- `enabled := true` — group membership follows this flag.
- `blocks_sight := true` — the door sets this to `false` to stay solid but
  see-through.
- `body_path := NodePath()` — empty means the parent node.
- `refresh_on_move := true` — request a fog refresh when the footprint enters a
  new 8 px cell.
- `size_override := Vector2.ZERO` / `offset := Vector2.ZERO` — pixels;
  a non-zero override replaces the derived footprint.

Public API:

- `is_occluding() -> bool`, `get_world_rect() -> Rect2` — the fog contract.
- `set_blocking(bool)`, `set_enabled(bool)`, `refresh_if_moved() -> bool`,
  `refresh()`, `get_body() -> Node2D`.

Footprint: the union of the host body's non-disabled `CollisionShape2D` children,
each transformed by `shape_node.global_transform * shape.get_rect()`. This keeps
the occlusion and the collision shape in sync; there is no second size to
maintain. No shapes and no override means the component occludes nothing.

Refresh: `get_tree().call_group(&"fog_of_war", "request_refresh")`, guarded so
it never runs in the editor. `_physics_process` compares the footprint's cell
rectangle (world / 8 px) with the last one and refreshes only on a change.
Registration happens in `_enter_tree` so the fog sees the occluder before any
fog `_ready` run.

Dependency: strings only (`fog_occluder`, `fog_of_war`). Platformer Kit does not
import Metroidvania Kit.

Editor: draws the footprint outline and an `OCC` label, like `FogZone`.

## Component B — `DoorComponent2D`

File: `addons/platformer_kit/world/components/door_component_2d.gd`
(`@tool`, `extends Node2D`).

Owns one door leaf: size, open/closed state, solid collision, interaction and the
panel drawing. It knows nothing about fog; it drives an occluder through a path.

Exports:

- `size_cells := Vector2i(1, 2)` — resizes the body's `RectangleShape2D` and the
  sense area.
- `closed := true`, `blocks_sight := true`, `interactive := true`.
- `interaction_action := &"interact"`.
- `body_path`, `sense_path`, `occluder_paths: Array[NodePath]`.

Public API: `set_closed(bool)`, `toggle()`, `is_closed()`, and the signals
`door_opened()` / `door_closed()`.

Behavior: closing enables the body shape and sets `collision_layer = 1`; opening
disables the shape and clears the layer, then calls `set_blocking(closed and
blocks_sight)` on every `occluder_paths` target. Interaction keeps the shipped
polling model (`Input.is_action_just_pressed` while the sense area overlaps a
body), guarded by `InputMap.has_action`.

`door_id` is removed: no code ever read it, and the reference room overrides it.

## Prefab

`scenes/world/fog_door.tscn` keeps its path and its `Node2D` root so existing
room instances stay valid (only the per-instance `script`/`door_id` overrides are
dropped):

```text
FogDoor (Node2D, z_index 2)
├── Body (StaticBody2D, layer 1, mask 0)
│   └── CollisionShape2D (8x16 RectangleShape2D, local to scene)
├── Door (Node2D, DoorComponent2D)      body ../Body, sense ../Sense,
│                                       occluder ../FogOccluder
├── FogOccluder (Node2D)                body ../Body
└── Sense (Area2D, layer 0, mask 2)
    └── CollisionShape2D (16x24 RectangleShape2D, local to scene)
```

## Migration

- Delete `scripts/world/fog_door.gd` and its `.uid`.
- Remove the `script` and `door_id` overrides from
  `scenes/levels/test/test_fog_start.tscn` and the matching lines in
  `scenes/rooms/generated/test_fog_start/runtime.tscn`, so the deleted script is
  not referenced. A later bake produces the same scene.
- Rebuild `tests/world/test_fog_door.gd` around the components, and assert the
  old script path is gone.

## Testing

- `tests/platformer_kit/platforms/test_fog_occluder.gd` (new): shape union to
  world rect, group membership, enable/disable, blocking toggle, refresh only on
  a crossed cell, refresh received by a fake `fog_of_war` node, `size_override`.
- `tests/world/test_fog_visibility.gd`: add a case that moves a real body with
  the component one cell and checks `_collect_sight` before/after.
- `tests/world/test_fog_door.gd`: rewrite against the prefab; opening clears both
  the shape and the occluder, closing restores both.
- Register the new test in `tests/runtime_suite.gd`.

## Documentation

`docs/extension-guide.md` (platform composition list plus an occluder/door
recipe), `addons/platformer_kit/README.md` (public API table and composition
paragraph), `docs/fog-zones-and-crumble.md` (door section and the contract for
future occluders), `docs/project-structure.md`, `MIGRATION.md`, `CHANGELOG.md`.
