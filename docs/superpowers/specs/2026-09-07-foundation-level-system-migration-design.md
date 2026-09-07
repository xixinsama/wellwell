# Foundation Level System Migration Design

## Goal

Replace the project's parallel legacy and WorldData-based level paths with one
production-ready foundation. The result must be a clean starting point for
future games: one room authoring format, one generated-output convention, one
world resource model, and reliable state ownership across loading and saving.

## Non-Goals

- Do not alter authored tile cell placement or room content semantics.
- Do not add gameplay systems such as combat, dialogue, or AI.
- Do not preserve runtime compatibility for removed legacy scenes/resources.
- Do not modify `docs/todo.md` or the existing `AGENTS.md`.

## Final Layout

```text
scenes/
  app/main.tscn
  runtime/world_root.tscn
  rooms/
    template/level_template.tscn
    source/level_0.tscn ... level_3.tscn
    generated/<room_id>/runtime.tscn
    generated/<room_id>/terrain.tscn
resources/
  worlds/main_world.tres
  rooms/generated/<room_id>.tres
scripts/
  app/
  player/
  save/
  camera/
  ui/
  tools/
  world/{data,runtime,entities,fog}/
  authoring/{room,world}/
tests/
  authoring/{room,world}/
  world/{data,runtime,entities,fog}/
```

The editor plugin remains in `addons/wellwell_world_editor/`; its plugin
configuration stays at the addon root and its implementation follows the same
authoring room/world boundary.

## Resource Ownership

`RoomData` owns immutable room metadata: room ID, display name, source scene,
generated runtime scene, generated terrain scene, room size, identifiers, tags,
and map color. It no longer owns placement or adjacency.

`WorldData` owns the complete topology: room membership, one embedded
`WorldRoomPlacementData` per room, directed `RoomConnectionData` entries,
and the start room/spawn. There is no `RoomData.room_origin_chunk` fallback
and no `adjacent_room_ids` field. Runtime residency derives from chunk
neighborhood plus connections only.

`RoomEntrance` owns only its stable entity ID and emits a transition request.
It contains no serialized target room/spawn fields. Connections are resolved
only by `WorldData`.

## Source And Bake Contract

The source scene path is `scenes/rooms/source/<room_id>.tscn`. Baking writes:

```text
scenes/rooms/generated/<room_id>/runtime.tscn
scenes/rooms/generated/<room_id>/terrain.tscn
resources/rooms/generated/<room_id>.tres
```

The room baker stages and validates all three outputs before replacing prior
files. `Bake World` validates only a fully baked WorldData; its UI status
explicitly reports sources newer than their generated artifacts and directs the
author to bake those rooms first. A source-content fingerprint stored in
`RoomData` makes stale artifacts a validation error rather than a timestamp
guess.

`resources/worlds/main_world.tres` is the only shipped example WorldData and
`scenes/runtime/world_root.tscn` references it. Empty/legacy template worlds,
the former graybox `game.tscn`, and obsolete room template resources are
removed after tests are migrated to dedicated fixtures.

## Runtime State

Every persistent `WorldEntity` receives a state sink during
`RoomRuntime.setup_room()`. `commit_save_state()` writes
`get_save_state()` to the active `SaveSnapshot`; `PickupEntity.collect()`,
`SwitchEntity.toggle()`, and `SavePoint.activate()` call it immediately.
`RoomRuntime.persist_entity_states()` is called before every room unload and
before a quick save. This preserves state both while crossing room boundaries
and while saving in place.

`SaveSnapshot.load_from_dictionary()` parses into temporary values and
replaces explored cells, explored chunks, and entity states atomically. Loading
a second snapshot cannot retain data from the first.

## Camera And Fog

`PixelCamera2D.camera_mode` is an authored setting. `WorldSession` supplies
active room bounds without changing the mode. The shipped WorldRoot selects
`ROOM_LOCKED`; direct room preview uses `FREE`.

In room-locked mode, a one-chunk room fixes the camera at the exact room center.
Larger rooms clamp the camera target to the room rectangle, and room changes
clamp the current smoothed position immediately so the prior room is never
shown. Free mode follows the target without room limits.

Fog is room-local cardinal flood-fill. Only `VisionBlockTiles` blocks
propagation; a blocker cell is visible but stops the next step. The current
visibility mask is transparent only for currently visible cells. Explored cells
persist for map discovery and saves, not for a dimmed in-world fog state.
All cell rectangles use exact room pixel extent:
`ceil(room_size_chunks * Vector2i(320, 180) / cell_size)`.

## Migration

1. Move scripts, scenes, resources, and tests to the final layout; update every
   explicit preload, scene ext_resource path, project setting, and documentation
   reference.
2. Convert all generated `RoomData` resources and `main_world.tres` to the
   no-legacy data schema, then re-bake level_0 through level_3.
3. Remove the legacy files only after the new references load and the migrated
   generated outputs validate.
4. Update the World editor file-dialog configuration, stale source detection,
   and all tests to the new paths and contracts.

Moves are explicit repository changes, not runtime fallback rules. A missing old
path is a migration defect and must fail tests.

## Verification

Automated coverage must prove:

- all source/generated/world paths resolve under the final layout;
- no RoomData or RoomEntrance legacy placement/target field remains;
- exact multi-chunk cell bounds agree across RoomData, RoomRuntime, and fog;
- persistent entity changes survive quick-save and unload/reload;
- free and room-locked camera modes remain distinct;
- fog blocker and mask behavior matches the stated rules;
- World editor resource dialogs are confined to resource paths;
- `main_world.tres` starts WorldRoot and all four baked rooms validate.

Godot headless editor initialization, the complete runtime suite, and direct
startup of main and every source room must be clean. The user performs the
final visual verification of tile placement, room preview, World editor layout,
and camera feel.
