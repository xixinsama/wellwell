# World Doors and Stacked Worlds — Design

Date: 2026-11-19
Status: implemented

## Goal

Add a paired door entity to the platformer world system with two uses:

- **Portal (传送门)** — moves the player to a specific place inside one world.
- **Shuttle door (穿梭门)** — swaps the whole world session for another world and
  moves the player to the matching door there, and back.

Both start as contact-activated with an unactivated/activated look, like the
existing save point. The World editor must support authoring stacked worlds,
which are the multi-world layouts the shuttle doors connect.

## Decision: free room placement, no placeholder rooms

The user offered two options for the editor: remove the forced top-left snapping
of imported rooms, or add "placeholder rooms" that reserve space without
existing at runtime.

**Chosen: remove the snapping, no placeholder rooms.**

- A placeholder room is a fake `RoomData` that has to be taught to the importer,
  the baker, validation, the room list, the runtime residency rules and the map
  model. Every path that misses a check either errors at runtime or silently
  occupies a chunk it should not.
- Room coordinates were already free — `WorldPlacementData.origin_chunk` accepts
  any chunk, including negative ones. The only constraint was a hardcoded
  `(-1, -1)` for every imported room, so the editor needed one behaviour change,
  not a new data type.
- What the placeholder idea was reaching for — "see where the other world is
  while I place this room" — is solved by drawing the other worlds, not by
  inventing rooms for them.

## Door entity

`WorldDoor extends WorldEntity`, so it inherits persistent id, save state, world
and room context, and the room runtime wiring for free.

- `Kind`: `PORTAL` (same world) or `SHUTTLE` (cross world).
- `ActivationMode`: `CONTACT` (default, touch) or `INTERACT`.
- Pairing is explicit and mutual: `target_room_id` + `target_door_id`, plus
  `target_world` for `SHUTTLE`. No implicit "same coordinates in the other
  world" rule, because stacked worlds are authoring convenience, not a
  coordinate contract.
- The door owns its arrival point as a nested `SpawnPoint` whose `spawn_id`
  mirrors the door's `entity_id`. That is what lets the cross-world path reuse
  the existing session spawn lookup instead of a parallel "door position" table.
- The door draws itself (`_draw`) in the 8px grid style: a stone frame, a dark
  field, a nested-ring glyph with a travelling shimmer for portals, a diamond
  and scan lines for shuttle doors. No art dependency, both states legible in a
  dark room (the activation accent is the only saturated colour).
- Arming: a door that sent or received the actor is disarmed until no body is in
  its sensor. The arrival spawn clears the sensor by design, so arrival never
  bounces the actor back; the test asserts that clearance.

## Travel paths

`PORTAL` goes through `WorldRuntime.travel_to_door`, which mirrors
`request_transition`: stage resident rooms, resolve the destination, commit the
room change (camera/fog/map react to `current_room_changed`), respawn the actor,
disarm the arrival door, record player tracking. It never touches the respawn
identity, so a checkpoint still owns death respawns.

`SHUTTLE` goes through `WorldSession.travel_to_world`, which rewrites the active
snapshot (world, room, respawn identity, arrival position) and restarts the
session on the target world. The snapshot object stays the same, so the save
manager, entity state and checkpoint wiring survive the swap. A failed start
restores the snapshot fields and leaves the previous world active.

One ordering hazard shaped the door code: a cross-world trip frees the room tree
the door lives in. `activate()` therefore travels last and touches nothing on
itself afterwards.

## Editor: free placement

- `WorldLayoutModel.find_free_origin_chunk(world, desired, size)` returns the
  requested chunk when it is free, else the nearest free chunk by Chebyshev ring
  (deterministic tie-break), never overlapping an existing room.
- `WorldLayoutModel.find_default_origin_chunk` scans row-major from (0,0) for
  callers with no cursor hint, so an empty world still starts at the origin and a
  new room never lands above/left of it.
- `WorldRoomImporter.import_room` takes an optional origin; the editor passes the
  chunk under the cursor, or the view centre when the cursor is outside the
  canvas.
- The status bar gained a chunk field: with a room selected it moves that room
  (through the normal undo path), otherwise it centres the view on the chunk.

## Editor: stacked world view

The user rejected the first pass as "just piled up" and asked for a real 3D stack
plus arrows for both door kinds, so the view was rebuilt:

- `WorldStackCamera` — pure projection: yaw, pitch, weak perspective, per-layer
  height (`LAYER_HEIGHT`), fit-to-view and slice picking. Nearer slices project
  larger, so the stack reads as depth. Layer spacing is deliberately tight and
  the fit fills most of the viewport (larger slices, per user feedback).
- `WorldStack3DLayer` — draws the slices (top face + thickness), rooms, door
  glyphs, portal arcs inside a slice, shuttle arcs across slices, name plates
  with a depth badge, hover lift and a legend. Left drag orbits, middle/right
  drag (or Shift+left) pans, the wheel zooms, and an `x / y / z` readout under the
  pointer uses `WorldStackCamera.unproject` so `z` is the layer index. Clicking a
  slice emits `world_picked`; the dock switches the edited world and returns to
  the flat 2D view, which is where precise room editing happens.
- `WorldStackModel` gained `build_door_links`, which classifies every door pair
  once (portal when both ends share a world, shuttle otherwise), plus
  `build_portal_links` and `collect_world_doors` for the canvas and the dock.
- The flat canvas now draws the same portal links as teal arcs between the doors
  and restyles room entrance → spawn connections as dim dashed lines, because
  the user had read those centre-to-centre arrows as teleports.
- **No ghost layers.** The first pass drew the other worlds as offset rectangles
  on the flat canvas behind a `Stack` popup; the user asked for that to go and be
  replaced by a real layer panel in the 3D view. The flat ghost layer and its
  popup are deleted.
- **The stack is a resource.** Auto-including every catalog world was wrong: the
  view must draw an authored set. `WorldStack` (`world_stack_data.gd`,
  `resources/worlds/<world>_stack.tres`) holds an ordered `layers: Array[WorldData]`,
  bottom slice first, and `WorldData.world_stack` points at it. The 3D view draws
  exactly those layers; a world without a stack is a stack of one. `+ World`
  creates and saves the resource on demand, so there is no separate setup step.
  This also names the hierarchy the project builds on: a **block** is a 1x1 chunk
  cell, a **room** is one or more blocks (`RoomData.room_size_chunks`), a **world**
  groups rooms (`WorldData`), and a **stack** (`WorldStack`) is the multi-layer
  world the 3D view shows.
- **Axes and coordinates.** The first pass reported `x / y / z` in a plate at the
  bottom-right, and its floor plan was mirrored vertically against the 2D view.
  The camera now negates world y so `+y` goes *down* the plan (the chunk grid's
  own direction), which puts every room exactly where the 2D editor draws it; the
  stack axis stays `z` and points up. The readout became an axis gizmo in the
  viewport's top-right: X/Y/Z arrows drawn from the live camera orientation, with
  the pointer's compact `x / y / z` line under them. Godot's editor resolves the
  same way — a 2D floor plan is a plane whose y runs down the screen.
- **No transitions.** The 0.42s entry rise and the 0.26s click lift were built,
  shipped, then turned off at the author's request: the view is instant again, so
  clicking a slice emits `world_picked` immediately.
- `WorldStackLayer` draws the ghosts behind the canvas grid, the links on top
  (teal solid when paired, red dashed when dangling, dot at the origin) and a
  legend line with the layer and dangling counts. It ignores the mouse; ghosts
  cannot be selected or dragged.
- `RoomAnnotationService` gained a `door` annotation carrying kind and link
  fields, which is what the editor reads to build the ghost doors and links.
- Dangling links are reported as de-duplicated warnings in the Output panel while
  the stack view is on.

## Testing

- Unit: `test_world_door` (entity behaviour, both travel dispatches, sensor
  clearance, arm/disarm), `test_world_travel` (real room fixture: portal trip,
  return trip, cross-world swap and rollback), `test_world_stack_model`,
  `test_world_layout_model` (free-chunk search).
- The full runtime suite passes headless.
- Gameplay was verified in `runners/test_world_runner.tscn` with scripted input: walking
  into a portal switched rooms and landed the player on the partner arrival
  without bouncing; touching a shuttle door swapped `test_world` → `the_world`
  (rooms `room_00_00`/`room_01_00` loaded) and an injected return door brought the
  player back to `test_world`/`water_hall`.
