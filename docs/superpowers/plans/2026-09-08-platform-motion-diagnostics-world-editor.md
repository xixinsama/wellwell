# Platform Motion, Diagnostics, and World Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair save commits, introduce composable platform behaviors with explicit velocity semantics, improve diagnostics, and complete the World Editor addon migration.

**Architecture:** CharacterMotor continues to own relative locomotion while Godot owns platform transport; the player exposes relative, platform, and actual world velocity separately. A generic AnimatableBody host composes child motion, trigger, and surface components. The World Editor becomes a self-contained editor addon that consumes only public Platformer Kit world contracts.

**Tech Stack:** Godot 4.7, typed GDScript, `.tscn` scenes, plain GDScript runtime tests.

**Spec:** `docs/superpowers/specs/2026-09-08-platform-motion-diagnostics-world-editor-design.md`

## Global Constraints

- Do not alter authored room TileMap data.
- Do not redesign example content in this change.
- Runtime modules must not depend on `platformer_debug` or `world_editor`.
- Platform transport must not be manually added to CharacterBody velocity.
- New behavior must have a failing regression test before implementation.

---

### Task 1: Repair Snapshot Commit Integration

**Files:**
- Modify: `addons/platformer_kit/world/runtime/world_session.gd`
- Test: `tests/world/test_world_session.gd`

**Interfaces:**
- Consumes: `snapshot_committing(snapshot: RefCounted)`
- Produces: `_on_snapshot_committing(snapshot: RefCounted) -> void`

- [x] Add a regression test that emits a snapshot through the real signal and proves loaded entity persistence is called only for the active snapshot.
- [x] Run the focused runtime suite and confirm the callback arity failure.
- [x] Connect the signal to the typed WorldSession adapter and disconnect stale runtime bindings when sessions change.
- [x] Run the focused and save tests until clean.

### Task 2: Establish Explicit Character Velocity Semantics

**Files:**
- Modify: `addons/platformer_kit/character/environment/character_environment_snapshot.gd`
- Modify: `addons/platformer_kit/character/sensors/environment_probe.gd`
- Modify: `scripts/player/player_controller.gd`
- Test: `tests/platformer_kit/character/test_character_sensors.gd`
- Test: `tests/platformer_kit/character/test_character_motor_integration.gd`

**Interfaces:**
- Produces debug keys `relative_velocity`, `platform_velocity`, and `world_velocity`.
- Keeps `velocity` as a compatibility alias for relative velocity.

- [x] Add failing tests for separate relative, platform, and world values.
- [x] Capture Godot platform and real velocity without injecting either into Motor input.
- [x] Preserve collision-corrected relative velocity after `move_and_slide()`.
- [x] Run all character tests.

### Task 3: Replace Concrete Platforms with Components

**Files:**
- Create: `addons/platformer_kit/platforms/platform_body_2d.gd`
- Create: `addons/platformer_kit/platforms/components/platform_motion_component_2d.gd`
- Create: `addons/platformer_kit/platforms/components/ping_pong_motion_component_2d.gd`
- Create: `addons/platformer_kit/platforms/components/fall_motion_component_2d.gd`
- Create: `addons/platformer_kit/platforms/components/rider_trigger_component_2d.gd`
- Create: `addons/platformer_kit/platforms/components/conveyor_surface_component_2d.gd`
- Remove: `addons/platformer_kit/platforms/one_way_platform.gd`
- Remove: `addons/platformer_kit/world/entities/one_way_platform.gd`
- Adapt/remove: existing concrete platform scripts
- Test: `tests/platformer_kit/platforms/test_platform_motion.gd`

**Interfaces:**
- `PlatformBody2D.get_platform_id() -> StringName`
- `PlatformBody2D.get_motion_velocity() -> Vector2`
- Motion components implement `sample_velocity(delta: float) -> Vector2`.
- Fall component implements `activate()`, `reset_component()`, and collision policy.

- [x] Replace old type tests with failing composition and collision-policy tests.
- [x] Implement the generic host and the minimum motion component contract.
- [x] Implement ping-pong and fall components, including combined horizontal/fall motion.
- [x] Implement rider activation and conveyor surface components.
- [x] Remove the one-way scripts and assert native one-way collision is sufficient.
- [x] Run platform and framework boundary tests.

### Task 4: Upgrade Debug Diagnostics

**Files:**
- Modify: `addons/platformer_debug/runtime/debug_hud.gd`
- Modify: `addons/platformer_debug/runtime/debug_hud.tscn`
- Modify: `addons/platformer_debug/runtime/debug_visualizer_2d.gd`
- Modify: `examples/movement_lab/debug_overlay.tscn`
- Test: `tests/platformer_debug/test_debug_contract.gd`

**Interfaces:**
- Debug subjects provide a read-only `get_debug_state() -> Dictionary`.
- HUD sections remain independently togglable.

- [x] Add failing assertions for all velocity channels and platform identity.
- [x] Render compact motion, contact, timer, and identity groups.
- [x] Draw independently colored relative, platform, and world vectors.
- [x] Run Debug addon tests and base-lab independence checks.

### Task 5: Migrate Movement Lab Fixtures Without Redesign

**Files:**
- Modify: `examples/movement_lab/movement_lab.tscn`
- Modify: `examples/movement_lab/movement_lab.gd`
- Test: `tests/examples/test_movement_lab.gd`

**Interfaces:**
- One-way fixture uses `CollisionShape2D.one_way_collision = true`.
- Moving, falling, conveyor, and combined moving-falling fixtures use components.

- [x] Add failing fixture-contract assertions for native one-way and component composition.
- [x] Convert existing fixtures and add one combined moving-then-falling fixture without changing the lab's overall purpose.
- [x] Move fall activation from lab orchestration into RiderTriggerComponent2D.
- [x] Run Movement Lab load and smoke tests.

### Task 6: Complete Platformer Kit Task 11

**Files:**
- Move: `addons/wellwell_world_editor/` to `addons/world_editor/`
- Move/adapt: editor-only helpers from `scripts/authoring/` into `addons/world_editor/authoring/`
- Modify: `project.godot`
- Modify: active World Editor tests and documentation
- Create: `tests/world_editor/test_world_editor_framework_boundary.gd`

**Interfaces:**
- World Editor may depend on `addons/platformer_kit/world`.
- Runtime framework has no dependency on World Editor.

- [x] Add a failing boundary test for old paths and dependencies outside the plugin/framework contract.
- [x] Move the addon and editor-owned helpers using one path migration.
- [x] Update plugin manifest, scenes, tests, and active documentation.
- [x] Verify no active resource references remain under `addons/wellwell_world_editor`.
- [x] Run all authoring tests and headless editor initialization.

### Task 7: Full Regression Verification

**Files:**
- Modify: `tests/runtime_suite.gd` only if new test registration is required.

- [x] Run `godot --headless --path . -s res://tests/run_runtime_suite.gd`.
- [x] Run project/framework validation commands.
- [x] Import the project headlessly and verify no parse or missing-resource errors.
- [x] Smoke launch `res://scenes/app/main.tscn` and both Movement Lab scenes.
- [x] Review the diff for authored TileMap changes and remove any accidental scene-data churn.
