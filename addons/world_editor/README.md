# World Editor 0.3.0

The main-screen authoring workbench: place rooms on a chunk grid, draw / merge /
split rooms, paint one terrain scene per world, bake rooms and worlds, and inspect
the stack of worlds in a 3D view. It is the only addon that performs editor-side
writes; the runtime never depends on it.

## Compatibility

| Item | Value |
| --- | --- |
| Godot | 4.7 (requires the editor, not just the export template) |
| Platformer Kit | 0.1.0 world contracts (`WorldData`, `RoomData`, `RoomConnectionData`, `WorldRoomPlacementData`) |
| Autoloads | none |
| Editor plugin | `addons/world_editor/plugin.cfg` — adds a dedicated editor main screen |
| Project setting | `world_editor/room_template_scene` (default `res://scenes/rooms/template/level_template.tscn`) |

## Install

1. Enable `addons/world_editor/plugin.cfg`.
2. Set `world_editor/room_template_scene` to the room template a fork should
   instantiate for **New Room**; the plugin never hard-codes a template path.
3. Select the **World** main-screen tab in the editor.

## Workbench

| Area | What it does |
| --- | --- |
| World bar | Pick / create / save a `WorldData` resource (`%WorldPicker`, `NewWorld`, `SaveWorld`) |
| Command bar | `NewRoom`, `AddExisting`, `DrawRoom`, `MergeRooms`, `SplitRoom`, `OpenSource`, `BakeRoom`, `BakeStale`, `ValidateRoom`, `ValidateWorld`, `BakeWorld`, `ViewMode3D` |
| Room list | Searchable list with per-room bake status (fresh / stale / error / unknown) |
| Canvas | Chunk-snapped layout, room selection, drag/move (`move_rooms_by`), zoom and focus |
| Inspector | Room metadata, start room, connections, source scene, bake status |
| Terrain bar | `EditTerrain` opens the world's single terrain scene; `SyncTerrain` slices it into every room and re-bakes |
| Stack / 3D view | Layer worlds, reorder, remove; `get_stack_3d_payload()` renders the stack with connections |
| Status bar | Validation and bake diagnostics (errors/warnings are also printed to the Output panel) |

## Authoring contract

| Item | Path / rule |
| --- | --- |
| Room source scene | `scenes/levels/<world_id>/<room_id>.tscn` (an inherited scene of the template, or a hand-authored scene following the contract) |
| Room runtime output | `scenes/rooms/generated/<room_id>/runtime.tscn` |
| Room terrain output | `scenes/rooms/generated/<room_id>/terrain.tscn` (sliced from the world terrain) |
| Room resource | `resources/rooms/generated/<room_id>.tres` (`RoomData`) |
| World terrain | `scenes/worlds/<world_id>/terrain.tscn` (one per world, world cell coordinates) |
| World resource | `resources/worlds/<world_id>.tres` (`WorldData`) |

`RoomData.source_fingerprint` is the SHA-256 of the source scene bytes. `BakeStale`
and `tools/validate_project.gd` report `stale bake` when the source changed since
the last bake. Room IDs are sanitized for output paths
(`RoomBakePaths.sanitize_room_id`), while source scenes keep their original ID.

## Useful commands (from a tool script or test)

`set_world_data`, `select_room`, `set_selection`, `move_room(s)`, `add_room`,
`remove_room`, `connect_rooms`, `disconnect_rooms`, `create_room_from_rect`,
`create_room`, `bake_selected_room`, `bake_stale_rooms`, `bake_world`,
`validate_world`, `validate_selected_room`, `sync_terrain`, `edit_terrain`,
`get_command_state`, `get_stack_worlds`, `add_layer`, `remove_layer`,
`move_layer`, `get_stack_3d_payload`.

## Tests

```powershell
godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=authoring
godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=world_editor
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/authoring/test_room_bake.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/authoring/test_room_authoring.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/authoring/test_world_stack.gd
```

## Known limits

- Editor-only: room sources, bakes and stack resources are written into `res://`,
  so the project must be writable.
- Merge requires the selected rooms to form a rectangle; split cuts on a chunk
  boundary. Both create new room IDs and back up the affected world/rooms.
- `WorldResourceService` refuses to save while a `.backup` file exists; resolve
  the interrupted save instead of deleting the backup silently.
- The 3D stack view is a preview, not a transform editor.
- Terrain painting happens in the normal TileMap editor; the plugin only opens
  and slices the scene.
