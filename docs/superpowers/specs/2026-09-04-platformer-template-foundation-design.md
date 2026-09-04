# Platformer Template Foundation Design

Date: 2026-09-04
Project: wellwell
Status: Ready for user review

## Goal

Turn `wellwell` from a compact movement prototype into a reusable Godot 2D
platformer level-building template. The template should provide generic
foundation systems for room authoring, chunk-based exploration, entity state,
save binding, fog of war, map rendering, and a practical editor workflow.

The first version must remain game-agnostic. Dash2Home or other projects can
migrate onto the template later, but the template itself should not encode
Dash2Home-specific mechanics such as room movement, traction, combat, story
systems, or progression rules.

## Non-Goals

Do not include these in the first foundation pass:

- in-game level editor
- custom Godot `EditorPlugin` or editor dock UI
- combat framework
- dialogue framework
- metroidvania ability gating
- room-moving mechanics
- complex room streaming or LRU cache policy
- final art, animation, sound, or production UI

The first pass should produce stable data boundaries and runtime behavior. Tool
UI can be added after those boundaries prove useful.

## Core Concepts

The template uses four coordinate layers:

- World: the full game space for one save file or campaign.
- Room: a rectangular authored gameplay area with stable `room_id`.
- Chunk: a fixed 320x180 safe-frame area. A room is one or more chunks.
- Cell: an 8x8 fog, tile, and fine-grained logic unit.

A minimum room is one chunk. Larger rooms use integer chunk sizes, for example
`room_origin_chunk = Vector2i(2, 1)` and `room_size_chunks = Vector2i(3, 2)`.
This produces a room spanning three screens wide and two screens tall, while
still letting the camera and map reason about screen-sized chunks.

Because 180 is not divisible by 8, chunk-to-cell conversion uses ceiling:
320x180 becomes 40x23 cells. The safe-frame and viewport border conventions
continue to handle the final clipped pixels.

## Data Model

Add Resource-backed data as the source of truth:

- `WorldData`
- `RoomData`
- `RoomConnectionData`
- `EntityInstanceData`

`WorldData` owns:

- `world_id`
- `start_room_id`
- `start_spawn_id`
- `rooms: Array[RoomData]`
- world-level tags or metadata

`RoomData` owns:

- `room_id`
- `display_name`
- `scene_path`
- `room_origin_chunk`
- `room_size_chunks`
- `adjacent_room_ids`
- optional map display metadata

`RoomConnectionData` owns:

- `from_room_id`
- `from_entrance_id`
- `to_room_id`
- `to_spawn_id`
- connection direction for map rendering

`EntityInstanceData` is optional in the first pass if entities are authored as
nodes inside room scenes. It becomes useful when editor tooling needs to list,
validate, or generate entities without opening each `.tscn`.

## Scene Organization

Keep room content as Godot scenes so designers can use the native editor.

Recommended structure:

```text
scenes/
  worlds/
    world_root.tscn
  rooms/
    room_template.tscn
    room_test_01.tscn
scripts/
  world/
    world_runtime.gd
    room_runtime.gd
    world_entity.gd
resources/
  worlds/
    world_01.tres
  rooms/
    room_test_01.tres
```

Recommended room scene layout:

```text
RoomRoot
  BackTiles
  SolidTiles
  GlassTiles
  VisionBlockTiles
  DetailTiles
  MarkerTiles
  Entities
```

`BackTiles`, `DetailTiles`, and `MarkerTiles` do not collide. `SolidTiles`
collide with the player. `GlassTiles` collide but do not block fog visibility.
`VisionBlockTiles` block fog visibility and may or may not collide depending on
tile metadata or layer use.

## Runtime Loading

Use current room plus adjacent rooms as the first loading model.

`WorldRuntime` responsibilities:

- load one `WorldData`
- track `current_room_id`
- instantiate current room and adjacent rooms
- unload rooms that are neither current nor adjacent
- coordinate room-entered events
- pass save state into room runtimes

`RoomRuntime` responsibilities:

- instantiate the room scene
- apply room world position from `RoomData`
- scan child `WorldEntity` nodes
- assign room context to entities
- collect tile layers for collision, visibility, fog, and map rendering
- expose room chunk bounds to fog and map systems

The player controller remains independent. It should not know about room
loading. Doors, entrances, room bounds, or triggers notify `WorldRuntime` when
a room transition should happen.

## Editor Workflow

First phase editing uses native Godot tools:

- Room scenes are edited directly as `.tscn`.
- Room metadata is edited as `.tres` Resources.
- Tiles are placed through `TileMapLayer`.
- Entities are placed as scene instances under `Entities`.
- IDs are exported strings and validated by scripts.

Add command-line or headless validation before custom editor UI:

- duplicate `room_id`
- missing `scene_path`
- invalid `adjacent_room_ids`
- duplicate `entity_id` within a room
- missing entrance target
- room scene missing required tile layers
- entity save interface mismatch

A custom `EditorPlugin` or dock is a second-phase tool once the data model
settles. It can later offer room lists, connection editing, ID generation, and
map previews.

## Entity System

Add `WorldEntity` as the base class for authored runtime entities.

Core fields:

- `entity_id`
- `entity_type`
- `room_id`
- `persistent`
- `map_visible`

Core methods:

- `setup_entity(context: Dictionary) -> void`
- `get_save_state() -> Dictionary`
- `apply_save_state(state: Dictionary) -> void`
- `get_map_marker() -> Dictionary`

First-pass built-in entities:

- `SpawnPoint`
- `ResetZone`
- `RoomEntrance`
- `Door` as a lockable or animated entrance variant
- `SavePoint`
- `Switch`
- `MovingPlatform`
- `Hazard`
- `Pickup`

Only persistent entities need save state. For example, pickups save collected
state, switches save activated state, doors save unlocked/open state, and save
points save activation state. Hazards and moving platforms may be stateless in
the first version unless explicitly configured otherwise.

## Save System

Save state uses stable IDs and avoids serializing whole scenes.

The snapshot should store:

- `world_id`
- `slot`
- `current_room_id`
- `respawn_room_id`
- `respawn_spawn_id`
- `explored_chunk_ids`
- `entity_states`
- `saved_unix_time`

Chunk IDs use a stable string format:

```text
world_01:chunk:2,1
```

Entity state keys use:

```text
world_01:room_test_01:pickup_health_01
```

`SaveManager` should expose focused methods:

- `mark_chunk_explored(chunk_id: String) -> bool`
- `is_chunk_explored(chunk_id: String) -> bool`
- `set_entity_state(entity_key: String, state: Dictionary) -> void`
- `get_entity_state(entity_key: String) -> Dictionary`
- `set_respawn(room_id: String, spawn_id: String) -> void`

The save layer should not know concrete entity classes. Entities convert their
own runtime state to small dictionaries.

## Fog Of War

Fog runtime works at 8x8 cell granularity inside the active room. The saved
exploration state works at chunk granularity.

Runtime behavior:

1. Convert player position to a fog cell.
2. Convert active room chunk bounds to a finite fog cell rectangle.
3. Collect visibility blockers from `VisionBlockTiles` and any entity that
   exposes a visibility-blocking cell set.
4. Flood-fill from the player cell.
5. Reveal reached cells in the current frame.
6. Stop propagation at blocker cells while still revealing the blocker face.
7. Update an `ImageTexture` mask for post-processing.
8. Mark the chunk containing the player as explored.

Fog should not depend on raycasts from the player center. Visibility is a grid
spread within the room. If the player stands near a chunk boundary inside a
larger room, fog can spread into both chunks as long as blockers do not stop it.

The first mask convention:

- transparent pixels: visible this frame
- fog-colored opaque pixels: not reached this frame

Map exploration should not depend on every fog cell being saved. It reads
`explored_chunk_ids`.

## Map Rendering

Map rendering is data-driven, not derived from visual tile pixels.

Inputs:

- `WorldData`
- each `RoomData.room_origin_chunk`
- each `RoomData.room_size_chunks`
- `RoomConnectionData`
- `explored_chunk_ids`
- optional entity map markers

Outputs:

- room rectangles in chunk coordinates
- explored chunk fill
- current room highlight
- entrance or door links
- optional icons for save points and important pickups

The first version can render a simple debug map rather than a polished UI. The
important part is that the same data can later drive minimap, full map, and
editor previews.

## Initial Tile Template

The initial tileset should be an art template, not final art. It must let an
artist replace each slot with consistent rules.

Use 8x8 tiles. Reserve a 16x8 atlas grid, 128 slots total. The first version
does not need every slot filled, but the layout should remain stable.

### Row 1: Solid Terrain Core

Required slots:

- full solid block
- top floor
- bottom ceiling
- left wall
- right wall
- top-left outer corner
- top-right outer corner
- bottom-left outer corner
- bottom-right outer corner
- inner corners
- single isolated block
- narrow column or beam variants

Default behavior: collides with player, blocks fog visibility unless placed on
a layer that explicitly says otherwise.

### Row 2: Solid Terrain Variants

Required slots:

- cracked block
- edge-worn floor
- alternate wall face
- small dents
- pipe or panel trim
- darker support block
- reserved slope slots for future slope support

Default behavior: same as solid terrain. These provide visual variety without
changing logic.

### Row 3: One-Way Platform

Required slots:

- left cap
- middle
- right cap
- single short platform
- hanging chain or support markers
- thin bridge variant

Default behavior: one-way collision, does not block fog visibility.

### Row 4: Background Tiles

Required slots:

- plain background fill
- darker fill
- subtle brick or panel pattern
- background top/bottom/side trim
- cracks
- noise variants

Default behavior: no collision, no visibility blocking, included in visual map
only if map styling wants it.

### Row 5: Glass Tiles

Required slots:

- glass full block
- glass wall
- glass floor
- glass corner pieces
- cracked glass
- broken glass proxy tile

Default behavior: collides with player, does not block fog visibility. This row
validates that collision and visibility are separate systems.

### Row 6: Vision Block Tiles

Required slots:

- thick black wall
- fog wall
- opaque curtain or shutter
- locked visibility gate
- partial occluder variants

Default behavior: blocks fog propagation. Collision is optional and should be
controlled separately by tile layer or metadata.

### Row 7: Hazard Tiles

Required slots:

- floor spikes
- ceiling spikes
- side spikes
- damage floor
- laser proxy tile
- hazard warning trim

Default behavior: damage trigger. These do not persist unless paired with a
persistent entity such as a switch-controlled hazard.

### Row 8: Utility And Marker Tiles

Required slots:

- spawn marker
- room entrance marker
- save point marker
- entity anchor
- camera boundary marker
- chunk boundary marker
- numbered test blocks
- fog blocker debug marker

Default behavior: editor/debug only. These should live on `MarkerTiles` and be
hidden or ignored at runtime.

## Tile Layer Rules

Prefer layer semantics over trying to infer behavior from art:

- `BackTiles`: background only.
- `SolidTiles`: physical collision terrain.
- `GlassTiles`: physical collision terrain that stays transparent to fog.
- `VisionBlockTiles`: fog blockers.
- `DetailTiles`: non-colliding foreground or trim.
- `MarkerTiles`: editor-only authoring markers.

If a tile needs multiple behaviors, use explicit metadata or separate layers.
Do not make "solid" automatically mean "blocks visibility" in every context.

## Validation And Tests

Headless tests should cover:

- room chunk bounds conversion
- duplicate ID detection
- room adjacency validation
- entity save-state round trip
- chunk exploration serialization
- fog flood-fill against blockers
- map model generation from `WorldData`

Manual Godot verification should cover:

- authoring a room from `room_template.tscn`
- placing tile layers and entities
- moving between current and adjacent rooms
- reloading persistent entity state
- fog mask update inside a multi-chunk room
- debug map showing explored chunks

## Implementation Phases

1. Foundation data resources: `WorldData`, `RoomData`, connection data, and
   validation tests.
2. Runtime loading: `WorldRuntime`, `RoomRuntime`, current plus adjacent room
   lifecycle.
3. Entity base: `WorldEntity`, stable keys, example entities.
4. Save binding: chunk exploration, entity state, respawn room/spawn.
5. Fog integration: active room bounds, `VisionBlockTiles`, mask texture.
6. Map model and debug renderer.
7. Tile template atlas and required tile layer scene conventions.
8. Editor helpers: validation command first, custom editor UI later.

Each phase should be independently testable and should avoid changing the
player movement controller unless the movement template itself requires it.
