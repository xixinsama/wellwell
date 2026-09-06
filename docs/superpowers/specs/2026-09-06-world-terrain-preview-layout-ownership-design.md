# World Terrain Preview and Layout Ownership Design

**Date:** 2026-09-06  
**Status:** Approved in discussion; pending written-spec review

## Context

The World Editor currently draws each room as a colored rectangle. This is enough to arrange room bounds, but it does not show the authored terrain and makes spatial composition difficult. Room placement is also stored in generated `RoomData`, even though placement belongs to a specific `WorldData`. Moving a room changes an external room resource in memory while world saving writes only the world file. Reload validation can therefore fail with `reloaded world differs from staged WorldData`.

Connections remain optional. They describe explicit transitions from a room entrance to a target spawn, not ordinary spatial placement. A world with no doors, portals, or other transition triggers does not need connection records yet.

For layout storage, room-bake preservation, world persistence, terrain preview, and optional-connection reachability, this document supersedes the corresponding rules in the 2026-09-05 level-authoring design and the earlier 2026-09-06 main-screen redesign. Their remaining requirements continue to apply.

## Goals

- Render an approximate but faithful world-map preview from generated terrain TileMapLayers.
- Keep room construction in source scenes and coarse placement in WorldData.
- Make room movement survive Save World, Bake World, reload, Undo, and Redo.
- Give different worlds independent positions for the same RoomData.
- Preserve existing world resources through an explicit compatibility migration.
- Keep the editor small: arrangement, inspection, validation, and explicit connections only.

## Non-Goals

- Editing tiles, entities, source scenes, or generated terrain from the World Editor.
- Rendering players, runtime entities, foreground content, `PreviewOnly`, marker tiles, or non-tile backgrounds.
- Automatic room layout, automatic connection creation, or large-world streaming of editor previews.
- Modifying `scenes/levels/level_0.tscn`, `level_1.tscn`, or `level_2.tscn` as part of this work.

## Authoritative Data Model

Add `WorldRoomPlacementData`, an editor/runtime resource with:

```gdscript
@export var room_id := ""
@export var origin_chunk := Vector2i.ZERO
```

`WorldData` gains an embedded `placements` collection. Placement resources are subresources of the world `.tres`; they are not saved as separate files. `WorldData.rooms` continues to hold external generated RoomData references, and `WorldData.connections` continues to hold directed transition records.

Ownership is:

- RoomData owns room identity, display metadata, dimensions, source/runtime/terrain paths, tags, entrances, spawns, and entities.
- WorldRoomPlacementData owns one room's origin in one world.
- WorldData owns membership, placements, start endpoint, and connections.

WorldData provides the only supported layout API:

```gdscript
get_room_placement(room_id: String) -> WorldRoomPlacementData
get_room_origin_chunk(room_id: String) -> Vector2i
set_room_origin_chunk(room_id: String, origin: Vector2i) -> bool
get_room_chunk_rect(room_id: String) -> Rect2i
get_room_pixel_rect(room_id: String) -> Rect2i
normalize_room_placements() -> Dictionary
```

World-aware code must stop reading `RoomData.room_origin_chunk` and `RoomData.get_chunk_rect()` directly. The old field remains temporarily for migration but is no longer authoritative and is excluded from world save signatures.

## Migration Rules

Loading a legacy world does not immediately write files. Normalization performs these steps in memory:

1. For every valid room without a placement, create one from its legacy `RoomData.room_origin_chunk`.
2. Sort placements deterministically by `room_id`.
3. Report how many placements were created and tell the user to Save World to persist the migration.
4. Treat empty IDs, duplicate placements, and placements for unknown rooms as validation errors rather than silently deleting data.

Once a placement exists, every editor and runtime system uses it even if the legacy RoomData coordinate differs. Saving the normalized world persists the migration in the world file. No room source scene or generated terrain scene is rewritten.

## Membership and Editing Semantics

- The first room imported into an empty world receives placement `(0, 0)`.
- A room imported into a non-empty world receives placement `(-1, -1)`.
- Occupied default positions are allowed; overlap validation tells the user to move the room.
- Moving a room mutates only its placement.
- Removing a room also removes its placement and any associated connections.
- Re-baking or replacing RoomData preserves the placement keyed by `room_id`.
- Undo/Redo snapshots include room references, deep-copied placements, start fields, connections, and legacy adjacency state.

## Terrain Preview Architecture

The canvas becomes three visual layers:

```text
WorldLayoutCanvas
|- BackgroundLayer       canvas background, chunk grid, and zero axes
|- TerrainPreviewLayer   read-only terrain scene instances
`- OverlayLayer          room frames, labels, connection arrows, and guides
```

TerrainPreviewLayer creates one clipped preview container per room. The container is positioned from `WorldData.get_room_origin_chunk()` and sized to `room_size_chunks * Vector2i(320, 180)`. Its child is an instance of `RoomData.terrain_scene_path` loaded with cache-ignore semantics.

Only these TileMapLayers are visible:

- `BackTiles`
- `SolidTiles`
- `GlassTiles`
- `VisionBlockTiles`
- `DetailTiles`

`Background`, `MarkerTiles`, collision, navigation, processing, and input are disabled. Content outside the declared room bounds is clipped. Project nearest-neighbor filtering remains authoritative so scaled previews preserve pixel edges.

The overlay stays above tiles. It draws the selected-room border, start marker, room label, red overlap tint, optional connection arrows, cursor coordinates, and drag guides. Preview children ignore mouse input; the existing canvas retains selection, snapping, pan, zoom, Focus All, and Reset View behavior.

The preview root receives one transform derived from `WorldCanvasView`: canvas center, world view center, and zoom. Individual preview containers remain in world-pixel coordinates. During a drag, only the selected container's temporary origin changes; scenes are not reloaded.

## Preview Lifecycle

- Selecting or loading a WorldData synchronizes the complete preview collection.
- Add Existing success adds one preview after the room and world transaction commits.
- Bake Room success reloads only that room's terrain instance.
- Move and Undo/Redo update placement transforms without rebuilding terrain.
- Switching worlds or removing the plugin frees obsolete instances and resource references.
- Missing, invalid, or wrong-root terrain scenes fall back to the existing colored room rectangle. The status area identifies the room and path, while other rooms remain editable.

No SubViewport, per-frame resource load, generated thumbnail file, or editor preview cache is introduced. One read-only terrain instance exists per room; TileMapLayer handles its normal render culling.

## Validation Semantics

World validation checks placement integrity and overlap using WorldData coordinates. Every room must have exactly one valid placement after normalization.

Connections remain directed and optional:

- A world with no connection records does not emit `unreachable from start room` warnings.
- Once at least one valid connection exists, reachability is computed from `start_room_id` over valid directed connections.
- Invalid endpoints and duplicate source entrances remain errors.
- Authored but unconnected entrances remain warnings.
- Overlapping room rectangles remain warnings regardless of connection use.

Warnings do not prevent Bake World. Structural errors and invalid generated room artifacts do.

## Save and Bake Transactions

Save World and Bake World use one WorldData persistence path. Bake World first performs full world and generated-artifact validation; Save World permits incomplete authoring state so work can be saved.

The shared transaction:

1. Normalize placements and deep-duplicate the candidate WorldData.
2. Sort rooms, placements, and connections deterministically.
3. Capture a stable signature containing world metadata, external room content metadata, embedded placements, start fields, and connections.
4. Save the candidate to a marked stage path.
5. Reload with `ResourceLoader.CACHE_MODE_IGNORE` and compare the signature.
6. Back up the existing final, promote the stage, and synchronize ResourceUID from stage to final.
7. Reload and compare again before deleting the backup.
8. Return the validated final WorldData and make it the editor's active resource.

Failure restores the previous final and removes newly created temporary files and stale temporary UID mappings. Signature errors identify the first differing field, for example `placement level_1 origin differs: expected (-1, -1), got (0, 0)`.

WorldBaker validates and then delegates persistence to the shared resource service instead of maintaining a second transaction implementation. Since placements are embedded, moving rooms changes only one persisted world file and no external RoomData save is required.

## Runtime Integration

WorldRuntime, WorldTerrainRuntime, MapModel, world overlap/reachability helpers, and fog room binding obtain room origins through WorldData. Fog still receives room dimensions from RoomData but receives the authoritative origin from the active world placement. Spatial residency and neighboring-chunk calculations use world placement rectangles.

This preserves current runtime behavior while preventing one RoomData from imposing the same coordinate on every world that references it.

## Automated Verification

Tests cover:

- Legacy placement migration and malformed placement rejection.
- Two worlds assigning different origins to the same RoomData.
- First and subsequent Add Existing defaults.
- Move, Save World, Bake World, reload, Undo, and Redo persistence.
- Bake Room replacement preserving placement.
- Remove Reference cleaning placement and connections.
- Stable stage/final signatures and ResourceUID promotion.
- Optional connection reachability behavior.
- Terrain layer allow-listing, clipping, transforms, selective refresh, and fallback placeholders.
- Runtime terrain, map, residency, and fog use of WorldData placement coordinates.

## Manual Godot Acceptance

The user performs visual editor acceptance:

1. Open `world_test.tres` and confirm actual tiles appear for all generated rooms.
2. Confirm Background and MarkerTiles are hidden.
3. Exercise zoom, pan, Focus All, Reset View, selection, and chunk-snapped dragging.
4. Confirm tiles and room overlays move together and overlap tint stays visible.
5. Save, close, and reopen the world; confirm coordinates persist.
6. Bake one room and confirm only its terrain preview refreshes.
7. Bake the world and confirm reload validation succeeds.
