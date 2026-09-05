# Platformer Template Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the reusable Godot platformer foundation around the existing tilemap scene without altering its authored tile placement.

**Architecture:** Keep gameplay composition scene-based. Resource data describes worlds, rooms, chunks, connections, and map markers; runtime nodes load current and adjacent rooms; entities expose a small save contract; UI calls managers through narrow APIs. Fog consumes explicit visibility blockers and produces a per-frame mask texture.

**Tech Stack:** Godot 4.7, typed GDScript, TileMapLayer, Resource, CanvasItem drawing, JSON in `user://`, headless runtime tests.

**Spec:** `docs/superpowers/specs/2026-09-04-platformer-template-foundation-design.md` and `docs/superpowers/specs/2026-09-04-tilemap-fog-save-design.md`

## Global Constraints

- Do not modify `docs/todo.md` or existing authored tile placement in `.tscn` scenes.
- Preserve the 320x180 safe gameplay frame and 8x8 cell convention.
- Keep movement authority in `PlayerController`; world, save, fog, and UI communicate through signals and focused APIs.
- Use explicit tile-layer semantics: `BackTiles`, `SolidTiles`, `GlassTiles`, `VisionBlockTiles`, `DetailTiles`, and `MarkerTiles`.
- New behavior requires a failing runtime test before production code.

---

### Task 1: Entity Contract And Built-In World Entities

**Files:**
- Create: `scripts/world/world_entity.gd`, `scripts/world/room_entrance.gd`, `scripts/world/save_point.gd`, `scripts/world/switch_entity.gd`, `scripts/world/pickup_entity.gd`, `scripts/world/hazard_entity.gd`
- Modify: `scripts/world/spawn_point.gd`, `scripts/world/reset_zone.gd`, `scripts/world/room_runtime.gd`
- Test: `tests/world/test_world_entity.gd`

Define `setup_entity(context: Dictionary)`, `get_save_key() -> String`, `get_save_state() -> Dictionary`, `apply_save_state(state: Dictionary) -> void`, and `get_map_marker() -> Dictionary`. Persistent entities register with `RoomRuntime`; stateless entities remain local. Test stable keys and state round trips before implementation.

### Task 2: Save Snapshot And Slot Operations

**Files:**
- Modify: `scripts/save/save_snapshot.gd`, `scripts/save/save_manager.gd`, `scripts/save/save_storage.gd`
- Test: `tests/save/test_save_slots.gd`

Add world/room/spawn fields, entity state dictionaries, explored chunk IDs, quick-save/quick-load, slot summaries, copy, delete, and respawn setters. Preserve existing cell exploration compatibility. Test empty slots, copy independence, deletion, and entity state round trips.

### Task 3: Room Transitions And Preloading

**Files:**
- Create: `scripts/world/room_transition.gd`
- Modify: `scripts/world/world_runtime.gd`, `scripts/world/room_runtime.gd`
- Test: `tests/world/test_room_transition.gd`

Add a signal-driven transition request that resolves an entrance to a target room/spawn, keeps current plus adjacent rooms loaded, applies saved entity state, and emits completion after the target room is ready. Tests must cover valid transitions and unknown targets without changing the player controller.

### Task 4: Map Model And Debug Renderer

**Files:**
- Create: `scripts/world/map_model.gd`, `scripts/tools/debug_map.gd`
- Modify: `scripts/save/save_snapshot.gd`, `scripts/world/world_data.gd`
- Test: `tests/world/test_map_model.gd`

Build a pure map model from `WorldData`, room rectangles, connections, explored chunks, current room, and entity markers. Add a compact `Node2D` debug renderer with configurable scale and colors. Test rectangle generation, explored filtering, current-room highlighting, and markers.

### Task 5: Menu, Settings, And Save-Slot UI

**Files:**
- Create: `scenes/ui/main_menu.tscn`, `scenes/ui/save_slots.tscn`, `scenes/ui/settings.tscn`, `scripts/ui/main_menu.gd`, `scripts/ui/save_slots.gd`, `scripts/ui/settings_menu.gd`
- Modify: `scenes/main.tscn`, `scripts/main.gd`, `scripts/save/global_settings_manager.gd`
- Test: `tests/ui/test_menu_contract.gd`

Implement editable native Control scenes for start, settings, exit, slot selection, copy, delete, quick save, and quick load. Keep presentation simple and make button behavior testable through manager calls. Test scene contracts and slot action routing without requiring rendered screenshots.

### Task 6: Tile Template Conventions And Validation Tool

**Files:**
- Create: `tools/validate_project.gd`, `scripts/world/tile_layer_contract.gd`, `tests/tools/test_project_validation.gd`
- Modify: `resources/tilesets/template_platform_tileset.tres`, `README.md`, `docs/extension-guide.md`

Document and validate the six semantic tile layers and the initial 8x8 atlas slot layout. The validator reports duplicate IDs, missing room scenes/layers, invalid connections, and invalid entity save contracts. It must inspect existing scenes without rewriting them.

### Task 7: Integration Wiring And Regression Coverage

**Files:**
- Modify: `project.godot`, `scenes/game.tscn`, `tests/runtime_suite.gd`
- Create: `resources/worlds/template_world.tres`, `resources/rooms/template_room.tres`
- Test: full runtime suite and headless project launch

Wire autoloads, map/fog/runtime references, and template resources while preserving existing tile coordinates. Add all new tests to the suite, run the validator, run headless tests, and launch the main scene headlessly for startup errors.

