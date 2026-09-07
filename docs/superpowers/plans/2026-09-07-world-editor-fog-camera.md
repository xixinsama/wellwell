# World Editor, Fog, And Camera Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add room-aware fog, free/locked camera modes, and complete center-canvas World editor interaction.

**Architecture:** Keep room layout authoritative in `WorldData`. `WorldSession` configures the active camera and fog from the same room rectangle. The editor canvas owns interaction state and delegates terrain drawing to its existing preview layer.

**Tech Stack:** Godot 4.7, typed GDScript, headless runtime suite.

**Spec:** `docs/superpowers/specs/2026-09-07-world-editor-fog-camera-design.md`

## Global Constraints

- Do not edit authored room scenes, tile placements, or `docs/todo.md`.
- Preserve the user's transparent `TerrainPreviewLayer` background change.
- Use `snake_case` files/methods and typed GDScript.
- Add every runtime test to `tests/runtime_suite.gd`.

---

### Task 1: Fog Visibility Contract

**Files:** Modify `scripts/world/fog_visibility.gd`, `scripts/world/fog_of_war.gd`; Test `tests/world/test_fog_visibility.gd`.

- [x] Add failing tests proving only `VisionBlockTiles` cells stop propagation and that mask origin/size match the active room.
- [x] Run the focused test and confirm the expected failure.
- [x] Implement optional flood-fill distance support with the default unlimited, and remove Solid/Glass from blocker collection.
- [x] Expose typed mask metadata accessors and keep the existing texture update path stable.
- [x] Run fog tests and the runtime suite.

### Task 2: Camera Modes

**Files:** Modify `scripts/camera/pixel_camera_2d.gd`, `scripts/world/world_session.gd`; Test `tests/world/test_pixel_camera.gd`.

- [x] Add failing tests for `FREE` and `ROOM_LOCKED`, including fixed one-chunk and bounded multi-chunk rooms.
- [x] Run the focused test and confirm failure.
- [x] Add camera mode, `set_room_bounds(Rect2)`, and `clear_room_bounds()` APIs. Keep free mode behavior unchanged; center one-chunk rooms and clamp larger rooms.
- [x] Configure the camera at session start and on current-room changes using `WorldData.get_room_pixel_rect()`.
- [x] Run camera, session, and full runtime tests.

### Task 3: World Editor Interaction

**Files:** Modify `addons/wellwell_world_editor/world_layout_canvas.gd`, `addons/wellwell_world_editor/world_editor_main.gd`; Test `tests/authoring/test_world_canvas_view.gd` or a focused new authoring test.

- [x] Add failing tests for hover/selection state, click-without-drag, and Escape cancellation.
- [x] Run the focused test and confirm failure.
- [x] Add selected/hovered room state, visual highlighting, status details, and cancellation that restores the original chunk.
- [x] Preserve whole-chunk snapping, coordinate guides, focus/zoom, terrain preview ownership, and existing undo/redo behavior.
- [x] Run authoring tests and the full runtime suite.

### Task 4: Verification

- [x] Run the complete headless runtime suite.
- [x] Run Godot headless project/editor initialization checks.
- [x] Review the diff for authored scene/tile changes and preserve known pre-existing test failures unrelated to this work.
