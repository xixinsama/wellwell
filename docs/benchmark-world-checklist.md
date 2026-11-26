# Benchmark world: build checklist

Everything the solver benchmark needs from a hand-built world. The data file
`tools/benchmark/benchmark_rooms.gd` stays the source of truth for what each room
tests; this list is what the world itself has to provide so the runner can drive
it.

## 1. Rooms

- 16 rooms, each `1 x 1` chunk (320 x 184 px, 40 x 23 cells), placed side by side
  on one row: room *i* at chunk `(i, 0)`.
- Room ids are free-form, but the runner finds benchmark rooms by the `bench_`
  prefix: `bench_00_flat`, `bench_01_steps`, ... `bench_15_stable_choice`.
- Rooms connect by sharing the floor row: the playfield floor sits on row 20, so
  a 1-cell step at a room edge is walkable. Leave a corridor opening wherever two
  rooms should be traversable — the runner teleports between rooms, so openings
  are for the player walking the world by hand.

## 2. Terrain scene per room

Each room needs its own terrain scene (`room_data.terrain_scene_path`) with:

- root `Node2D`
- child `Background` (any `Node2D`; the runtime refuses the scene without it)
- child `Terrain` (`Node2D`) holding exactly these `TileMapLayer`s:
  `BackTiles`, `SolidTiles`, `DetailTiles`, `GlassTiles`, `VisionBlockTiles`,
  `MarkerTiles`, `CrumbleTiles`, `CrumbleOneWayTiles` — all with the world tileset,
  `collision_enabled` only on `SolidTiles`.
- Cells are room-local (0..39 x 0..22).
- Solid tiles: any atlas tile whose physics polygon is not one-way, e.g. `(0, 0)`.
- One-way platforms: the tileset's one-way tiles `(0, 4)`..`(3, 4)`. Their collider
  is the **upper 8 x 4 half** of the cell, so a one-way tile on row *y* gives a
  surface at `y * 8` you can jump up through.
- Ladders are not tiles: drop `LadderZone` (`addons/platformer_kit/world/entities/ladder_zone.tscn`)
  instances into the room with a `RectangleShape2D` sized to the ladder shaft.

## 3. Room scene per room

`room_data.scene_path` points at a scene that carries the waypoints:

- root `Node2D`
- `start` — a `SpawnPoint` (`spawn_point.gd`, which extends `Marker2D`) with
  `spawn_id = "start"` at the room's A waypoint.
- `goal` — same script, `spawn_id = "goal"`, at the room's B waypoint.

Spawn points are resolved **by script**, and `set_script()` on a plain `Node2D` is
silently refused because the base class is `Marker2D` — instantiate from
`spawn_point.gd` instead.

## 4. World resource

`WorldData` needs: `world_id`, `display_name`, `description` (shown in the menu),
`start_room_id`, `start_spawn_id = "start"`, one `RoomData` per room and one
`WorldRoomPlacementData` per room (`room_id` + `origin_chunk`). `RoomData` fields
that must be filled: `room_id`, `display_name`, `scene_path`, `source_scene_path`,
`terrain_scene_path`, `room_size_chunks = (1, 1)`, `spawn_ids` including `start`.

Add the world to `resources/worlds/world_catalog.tres` so it appears in the world
menu.

## 5. Per-room solver requirements

The runner reads waypoints, abilities and time budgets from
`tools/benchmark/benchmark_rooms.gd`; keep the authored A/B points and those cells
in agreement. Each room grants or revokes dash and climb:

| room | dash | climb | budget |
| --- | --- | --- | --- |
| flat | no | no | 6 s |
| steps | no | no | 9 s |
| one_way_up | no | no | 9 s |
| ladder | no | no | 11 s |
| gap_run | no | no | 9 s |
| gap_dash | yes | no | 9 s |
| dash_ledge | yes | no | 10 s |
| climb_shaft | no | yes | 11 s |
| wall_jump | no | yes | 12 s |
| no_climb | no | no | 14 s |
| one_way_slot | yes | no | 10 s |
| low_ceiling | no | no | 10 s |
| staircase | no | no | 12 s |
| narrow_landings | no | no | 12 s |
| mixed | yes | yes | 14 s |
| stable_choice | no | no | 12 s |

## 6. Running the benchmark on your world

1. Open the game, pick the benchmark world in the menu.
2. The `BenchRunner` node in `scenes/runtime/world_root.tscn` starts by itself in
   any `bench_` room and draws `BENCH n/16` with one line per room: `OK`/`FAIL`
   plus the replan count.
3. Headless solver-only check of the same data:
   `godot --headless --path . -s res://tools/benchmark/run_benchmark.gd`

## 7. Optional: procedural generation

`godot --headless --path . -s res://tools/benchmark/build_benchmark_world.gd`
rebuilds `scenes/worlds/benchmark_world/terrain.tscn`, the 16 room scenes and
`resources/worlds/benchmark_world.tres` from `benchmark_rooms.gd`. Use it as a
reference implementation for the scene shapes above, or delete the generated
files and author the rooms by hand.
