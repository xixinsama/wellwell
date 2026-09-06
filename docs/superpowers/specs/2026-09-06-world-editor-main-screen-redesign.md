# World Editor Main Screen Redesign

## Context

The current `wellwell_world_editor` registers `world_editor_dock.tscn` with `add_control_to_dock()`. This constrains the layout canvas to a narrow side panel and hides a second requirement: commands such as **Add Existing** only work after a `WorldData` resource has been selected elsewhere in the editor. The button currently does nothing when no world is active, and successful in-memory mutations are not reliably persisted.

Godot's documented main-screen plugin pattern is the correct integration. The plugin must instantiate a dedicated scene under `EditorInterface.get_editor_main_screen()`, expose a top-level editor workspace, and manage visibility through the `EditorPlugin` main-screen virtual methods.

## Goals

- Provide a standard center-screen `World` workspace backed by a `.tscn` UI scene.
- Make the active `WorldData` explicit and support creating, opening, and saving it from the workspace.
- Keep room placement snapped to complete `320x180` pixel chunks.
- Add predictable pan, zoom, focus-all, grid, guide, and coordinate behavior.
- Make **Add Existing** explain failures and persist both room outputs and the world reference safely.
- Preserve the existing `RoomBaker`, `WorldLayoutModel`, runtime loading, and authored level scenes.

## Non-Goals

- Editing room-internal tiles or entities from the world workspace.
- Replacing the inherited `level_template.tscn` workflow.
- Providing arbitrary graph nodes, scripting, minimap decoration, or runtime gameplay preview in the world workspace.
- Modifying tile data or metadata in `scenes/levels/level_0.tscn` through `level_2.tscn`.

## Resource Model

A room source and a world layout are different assets:

- `scenes/levels/level_x.tscn` is the editable inherited room source.
- `resources/rooms/generated/level_x_room.tres` is generated `RoomData`.
- `scenes/rooms/generated/level_x_runtime.tscn` is generated non-terrain room content.
- `scenes/rooms/generated/level_x_terrain.tscn` is generated terrain content.
- `resources/worlds/<world_id>.tres` is one `WorldData` containing references to many `RoomData` resources and their connections.

There is no required `level_x_world.tres` per room. A project can use one world such as `main_world.tres` for level 0, 1, and 2. The existing `level_0_world.tres` is an initial world asset, not a per-level generation convention.

## Main-Screen Plugin Architecture

Create `world_editor_main.tscn` with `world_editor_main.gd` as its controller. The root is a full-rect `Control` with vertical expand/fill sizing. `world_editor_plugin.gd` will:

1. Instantiate the main scene in `_enter_tree()`.
2. Add it to `EditorInterface.get_editor_main_screen()`.
3. Inject `EditorInterface` and `EditorUndoRedoManager` adapters.
4. Hide it initially through `_make_visible(false)`.
5. Return `true` from `_has_main_screen()`.
6. Return `World` and a built-in editor icon from `_get_plugin_name()` and `_get_plugin_icon()`.
7. Continue handling `WorldData`; selecting one in the editor sets the active world and may focus the workspace.
8. Free only the plugin-owned main scene in `_exit_tree()`.

The old side-dock registration and dock-specific scene are removed. The plugin must never remove or free the editor's main-screen container.

## Main Scene Layout

The scene contains four unframed bands:

- **World toolbar:** `EditorResourcePicker` restricted to `WorldData`, plus icon buttons for new and save.
- **Room toolbar:** new inherited room, add existing source, remove reference, open source, validate room, bake room, validate world, and bake world.
- **World canvas:** the expanding central control that draws rooms, connections, grid, guides, and coordinate overlays.
- **Connection/status band:** source entrance, target room, target spawn, connect/disconnect controls, persistent status text, and zoom percentage.

Commands that require an active world or room are disabled when their prerequisite is absent. Their tooltip and the status line state the missing prerequisite. No command silently returns because `world_data` is null.

## World And Room Workflows

### Create Or Open A World

**New World** opens a resource save dialog rooted at `res://resources/worlds/`. Choosing `<name>.tres` creates a `WorldData`; `world_id` defaults to the filename stem and can later be edited in the Inspector. The resource is saved immediately and assigned to the picker.

The picker loads an existing `WorldData`. Selecting a `WorldData` in the FileSystem/Inspector also updates the picker through `_handles()` and `_edit()`. **Save World** validates the active resource path and uses `ResourceSaver.save()`; failures remain visible in the status line.

### Create Or Open A Room

**New Room** calls `open_scene_from_path(TEMPLATE_SCENE_PATH, true)`, creating an unsaved inherited scene. The creator saves it under `res://scenes/levels/level_x.tscn` with Godot's normal Save As command.

An authored source can be opened directly from the FileSystem. Once it is referenced by the world, selecting its rectangle and pressing **Open Source** opens its `source_scene_path`.

### Add Existing

**Add Existing** is enabled only when a saved `WorldData` is active. It accepts a room source `.tscn`, then:

1. Loads and instantiates the source.
2. Validates the room authoring contract and normalized room ID.
3. Stages and reload-validates the runtime scene, terrain scene, and `RoomData` without changing finals.
4. Applies the candidate metadata to a duplicate of the active world and rejects duplicate IDs before final writes. If the world was empty, the imported room becomes `start_room_id` and its validated `preview_spawn_id` becomes `start_spawn_id`. A non-empty legacy world with a missing start endpoint is rejected instead of guessed.
5. Backs up and promotes the three room artifacts, then loads the promoted final `RoomData` path.
6. Builds and reload-validates a staged world resource that references the final `RoomData`.
7. Backs up and promotes the world resource; any failure after step 5 restores all previous room and world files.
8. Updates the live world from the validated saved state, selects the added room, focuses it, and reports all generated paths.

An invalid scene, duplicate room ID, unsaved world, or write error produces a concrete status message and no partial final state.

## Canvas Navigation And Drawing

`WorldLayoutCanvas` owns a world-to-screen transform consisting of `view_center_world_pixels` and `zoom`. Room metadata remains integer chunks; navigation never modifies world data.

- Mouse wheel zooms by fixed multiplicative steps around the cursor, clamped from `10%` to `400%`.
- Middle-mouse drag and `Space + left-mouse drag` pan the canvas.
- **Focus All** computes the pixel bounds of all rooms, adds screen-space padding, and chooses a fitting zoom. With no rooms it centers chunk `(0, 0)`.
- **Reset View** returns to `100%` zoom centered on chunk `(0, 0)`.
- Room dragging converts the pointer delta into world pixels, rounds by `(320, 180)`, and commits integer chunk coordinates through `WorldLayoutModel` and undo/redo.

The canvas draws vertical grid lines every 320 world pixels and horizontal lines every 180 world pixels. Axes at chunk coordinate zero use stronger styling. At low zoom, labels and minor lines are thinned to avoid noise. During room drag, guide lines cross the candidate chunk origin and the target `(x, y)` chunk coordinate is displayed.

A compact overlay displays cursor world pixels, cursor chunk coordinates, selected room origin/size, and zoom percentage. Connection geometry and overlap highlighting continue using transformed room rectangles.

## Persistence And Undo

Move, remove, connect, and disconnect remain undoable model operations. They mark the active world dirty; **Save World** persists the current state. Add Existing is persisted immediately because it also creates generated artifacts. Its history action captures complete before/after world states, including `start_room_id` and `start_spawn_id`; undo and redo persist the corresponding state without deleting valid generated room artifacts.

Room baking preserves world-owned `room_origin_chunk` and `adjacent_room_ids`. World baking continues to validate all referenced room artifacts before replacing the world resource.

## Error Handling

The status band shows the first error and exposes the full result through a tooltip. Success reports the affected resource or output paths. File dialogs are restricted to `res://` and the expected extensions. Buttons are disabled during a transaction to prevent re-entry.

The editor plugin must not depend on undocumented `CanvasItemEditor` internals. All pan, zoom, focus, grid, and input behavior belongs to the plugin's own canvas.

## Verification

Automated coverage will include:

- Main-screen plugin lifecycle and the absence of side-dock registration.
- Required main scene controls and full expand/fill layout.
- World creation, loading, explicit null-world errors, and save failures.
- Add Existing success, duplicate rejection, invalid source rejection, and forced transactional rollback.
- World/screen transform round trips, cursor-anchored zoom, pan, focus-all bounds, and exact chunk snapping.
- Grid spacing, visible coordinate calculations, drag guides, connection geometry, and overlap detection.
- Existing runtime suite, project parse, enabled-plugin headless editor initialization, and main scene boot.

Manual Godot acceptance remains user-owned: confirm the top `World` workspace, dialogs, visual grid density, mouse navigation feel, focus behavior, and authored level appearance.

`level_1.tscn` and `level_2.tscn` currently use preview IDs that do not match the inherited `start` spawn. Correcting those scenes in Godot is a separate user-owned prerequisite for importing and previewing those two rooms; it is not an implementation task or an automated-completion requirement for this redesign.
