# Platformer Kit Plugin Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Each task must complete its test cycle before the next task begins.

**Goal:** Convert `wellwell` into a reusable platformer framework SDK while preserving the current playable reference game and freezing new World Editor feature work until the runtime contracts are stable.

**Architecture:** `addons/platformer_kit/` owns framework-neutral runtime contracts and implementations. Optional sibling addons provide world editing, diagnostics, abilities, combat, and Metroidvania progression. Concrete scenes and game-specific data live under `game/` or `examples/` and may depend on the framework, never the reverse.

**Tech Stack:** Godot 4.7.2, typed GDScript, `Resource` data assets, `CharacterBody2D`, `TileMapLayer`, plain GDScript runtime tests, Godot headless validation.

**Spec:** `docs/superpowers/specs/2026-09-07-platformer-kit-plugin-architecture-design.md`

## Global Constraints

- Work directly on branch `level0`; do not create a worktree.
- Do not modify `AGENTS.md` or `docs/todo.md`.
- Do not modify authored tile cell placement while moving scripts, scenes, or resources.
- Keep the existing reference game runnable after every task.
- Framework code must not reference `game/`, concrete levels, game-specific autoload names, or editor-only classes.
- Runtime modules must work when optional editor plugins are disabled.
- Use the existing Godot headless test harness; do not add third-party dependencies.
- Do not commit automatically. End each task with `git diff --check`, focused tests, and a user review checkpoint.

## Target File Map

The migration will converge on this structure:

```text
addons/
├── platformer_kit/
│   ├── core/
│   ├── contracts/
│   ├── character/
│   ├── camera/
│   ├── platforms/
│   ├── interaction/
│   ├── world/
│   ├── save/
│   ├── resources/
│   └── plugin.cfg
├── world_editor/
├── platformer_debug/
├── platformer_abilities/
├── platformer_combat/
└── metroidvania_kit/

game/
├── bootstrap/
├── player/
├── enemies/
├── world/
├── items/
├── abilities/
├── ui/
└── data/

examples/
├── movement_lab/
├── combat_lab/
├── ability_lab/
└── metroidvania_demo/
```

The first migration tasks may keep compatibility paths temporarily while all
internal resource references are updated and validated. Compatibility code is
removed only after the full suite and headless editor load pass.

---

### Task 1: Establish a clean baseline and dependency checks

**Files:**
- Modify: `addons/wellwell_world_editor/world_editor_main.tscn`
- Create: `tools/validate_framework_boundaries.gd`
- Create: `tests/tools/test_framework_boundaries.gd`
- Modify: `tests/runtime_suite.gd`
- Test: existing authoring and project validation tests

**Interfaces:**
- Produces a boundary validator that accepts only framework-to-framework and game-to-framework references.
- Produces a clean baseline where resource dialogs use `FileDialog.ACCESS_RESOURCES`, `FILE_MODE_OPEN_FILE` for Add Existing, and `FILE_MODE_SAVE_FILE` with `res://resources/worlds` for New World.

- [ ] Write a failing boundary test with one allowed framework reference, one allowed game-to-framework reference, and one forbidden framework-to-game reference.
- [ ] Run `godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/tools/test_framework_boundaries.gd` and verify it fails on the forbidden reference rule.
- [ ] Implement the validator using `DirAccess` and `FileAccess`, scanning only `.gd`, `.tscn`, and `.tres` files under `addons/platformer_kit/`.
- [ ] Fix the existing World Editor dialog contract in the scene without changing its editor behavior beyond the resource restriction.
- [ ] Register the test in `tests/runtime_suite.gd`.
- [ ] Run the focused boundary test, the World Editor command test, and `tools/validate_project.gd`.

### Task 2: Create the `platformer_kit` package shell

**Files:**
- Create: `addons/platformer_kit/plugin.cfg`
- Create: `addons/platformer_kit/platformer_kit_plugin.gd`
- Create: `addons/platformer_kit/core/state/state_machine.gd`
- Create: `addons/platformer_kit/core/events/game_event.gd`
- Create: `addons/platformer_kit/core/events/scoped_event_bus.gd`
- Create: `addons/platformer_kit/core/tags/tag_container.gd`
- Create: `addons/platformer_kit/core/README.md`
- Create: `addons/platformer_kit/contracts/README.md`
- Create: `tests/platformer_kit/test_platformer_kit_contract.gd`
- Create: `tests/platformer_kit/test_core_primitives.gd`
- Modify: `project.godot` only to register the addon if the plugin manifest requires it

**Interfaces:**
- `platformer_kit/plugin.cfg` exposes the framework version and Godot compatibility.
- The plugin performs no autoload registration and does not make runtime behavior depend on editor startup.
- `StateMachine`, `GameEvent`, `ScopedEventBus`, and `TagContainer` are explicit objects; no global singleton is required by the framework.

- [ ] Write a failing contract test requiring the addon manifest, version field, and runtime/editor separation.
- [ ] Run the focused test and confirm the package is missing.
- [ ] Add the minimal manifest and `EditorPlugin`; keep `_enter_tree()` side-effect free except for editor registrations owned by the framework.
- [ ] Add the initial package contract test to the runtime suite.
- [ ] Add core primitive tests for state transitions, scoped event delivery, and tag add/remove/containment behavior.
- [ ] Implement the core primitives with typed inputs and deterministic update order.
- [ ] Run the contract test and headless editor initialization.

### Task 3: Introduce input intent and movement profiles

**Files:**
- Create: `addons/platformer_kit/character/input/character_intent.gd`
- Create: `addons/platformer_kit/character/input/input_source.gd`
- Create: `addons/platformer_kit/character/input/player_input_source.gd`
- Create: `addons/platformer_kit/character/resources/movement_profile.gd`
- Create: `addons/platformer_kit/character/resources/default_movement_profile.tres`
- Create: `tests/platformer_kit/character/test_character_intent.gd`
- Create: `tests/platformer_kit/character/test_input_source.gd`

**Interfaces:**
- `CharacterIntent` exposes `move_axis: float`, `jump_pressed: bool`, `jump_released: bool`, and `fast_fall: bool`, plus `clear_transient() -> void`.
- `InputSource` exposes `get_intent() -> CharacterIntent`.
- `MovementProfile` stores max speed, acceleration, deceleration, gravity, jump speed, fall speed, coyote time, jump buffer time, and variable jump parameters.

- [ ] Write tests proving intent contains no `Input` dependency and transient fields clear without changing `move_axis`.
- [ ] Run the focused tests and verify the new classes are absent.
- [ ] Implement the data classes and a player input adapter that reads project actions only at the adapter boundary.
- [ ] Migrate the current tuning resource values into `default_movement_profile.tres` without changing gameplay values.
- [ ] Run focused tests and compare the reference game launch behavior.

### Task 4: Build `CharacterEnvironmentSnapshot` and `CharacterMotor2D`

**Files:**
- Create: `addons/platformer_kit/character/environment/character_environment_snapshot.gd`
- Create: `addons/platformer_kit/character/motor/character_motor_2d.gd`
- Create: `addons/platformer_kit/character/motor/movement_context.gd`
- Create: `tests/platformer_kit/character/test_character_motor_2d.gd`
- Create: `tests/platformer_kit/character/test_character_motor_integration.gd`
- Modify: `scenes/player/player.tscn` during the migration cutover
- Replace or wrap: `scripts/player/player_controller.gd`

**Interfaces:**
- `CharacterEnvironmentSnapshot` reports grounded state, ceiling state, left/right wall state, floor normal, floor velocity, and moving-platform state.
- `CharacterMotor2D` consumes `CharacterIntent`, `MovementProfile`, and the environment snapshot; it does not read input, animation, HP, save state, or game nodes.
- The temporary `PlayerController` compatibility wrapper composes the motor and preserves the current scene contract until `game/player/` is introduced.

- [ ] Write tests for acceleration, deceleration, gravity, jump buffering, coyote time, variable jump release, and terminal velocity.
- [ ] Run them before implementation and verify each failure is caused by missing motor behavior.
- [ ] Implement the smallest motor API needed by the tests; keep all constants in `MovementProfile`.
- [ ] Adapt the current player scene through the wrapper without changing collision layers or authored visuals.
- [ ] Run character tests, the existing player/runtime tests, and a headless launch.

### Task 5: Add sensors, camera, and platform motion as framework modules

**Files:**
- Create: `addons/platformer_kit/character/sensors/character_sensors.gd`
- Create: `addons/platformer_kit/character/sensors/environment_probe.gd`
- Move/adapt: `scripts/camera/pixel_camera_2d.gd` to `addons/platformer_kit/camera/pixel_camera_2d.gd`
- Create: `addons/platformer_kit/platforms/moving_platform.gd`
- Create: `addons/platformer_kit/platforms/one_way_platform.gd`
- Create: `addons/platformer_kit/platforms/falling_platform.gd`
- Create: `addons/platformer_kit/platforms/conveyor_platform.gd`
- Create: `addons/platformer_kit/interaction/interactable.gd`
- Create: `addons/platformer_kit/interaction/interaction_detector.gd`
- Create: `tests/platformer_kit/character/test_character_sensors.gd`
- Create: `tests/platformer_kit/platforms/test_platform_motion.gd`
- Create: `tests/platformer_kit/interaction/test_interaction.gd`
- Modify: camera and player scene references after tests pass

**Interfaces:**
- Sensors produce one `CharacterEnvironmentSnapshot` per physics frame.
- Moving platforms expose current velocity and a stable platform identity for motor inheritance.
- `PixelCamera2D` consumes room bounds and camera mode through explicit methods, preserving the existing free and room-locked modes.
- `Interactable` exposes an interaction contract and `InteractionDetector` reports nearby candidates without knowing concrete game content.

- [ ] Write tests for wall/ceiling detection, floor normal capture, platform velocity inheritance, one-chunk camera locking, and multi-chunk camera movement.
- [ ] Run focused tests before implementation.
- [ ] Implement sensors and platform motion without putting platform-specific logic in the motor.
- [ ] Implement the interaction contract and detector as a framework-neutral base facility.
- [ ] Migrate the existing camera tests and scene references.
- [ ] Run the camera, sensor, platform, and full runtime tests.

### Task 6: Create the `movement_lab` reference example

**Files:**
- Create: `examples/movement_lab/movement_lab.tscn`
- Create: `examples/movement_lab/movement_lab.gd`
- Create: `tests/examples/test_movement_lab.gd`
- Modify: `README.md` with the launch command

**Interfaces:**
- The lab uses only `platformer_kit` runtime APIs and test fixtures; it contains no game-specific production logic.
- The lab demonstrates slopes, one-way platforms, moving platforms, a low ceiling, a wall, a narrow gap, a falling platform, and a conveyor.

- [ ] Add a scene contract test requiring the named lab fixtures and framework player composition.
- [ ] Run it before the scene exists and confirm the expected failure.
- [ ] Create the smallest playable lab scene.
- [ ] Run the lab headless with `--quit-after 2` and the focused contract test.

### Task 7: Migrate world, room, and persistence contracts

**Files:**
- Move/adapt: `scripts/world/data/` to `addons/platformer_kit/world/data/`
- Move/adapt: `scripts/world/runtime/` to `addons/platformer_kit/world/runtime/`
- Move/adapt: `scripts/world/entities/` to `addons/platformer_kit/world/entities/`
- Move/adapt: `scripts/save/` to `addons/platformer_kit/save/`
- Create: `addons/platformer_kit/save/saveable.gd`
- Create: `addons/platformer_kit/save/persistent_id.gd`
- Create: `tests/platformer_kit/world/`
- Create: `tests/platformer_kit/save/`
- Update all internal `.tscn`, `.tres`, `.gd`, and test references atomically

**Interfaces:**
- `WorldData`, `RoomData`, room placement, room connection, `WorldRuntime`, `RoomRuntime`, fog bindings, and save snapshots become framework contracts.
- Persistent entities expose stable IDs and save/restore methods through `Saveable`; no `NodePath` or instance ID is persisted.
- World/session startup receives its world, player, camera, terrain, fog, and save adapters explicitly instead of resolving concrete global names.

- [ ] Add tests proving framework world and save classes load without `main_world.tres` or `/root/SaveManager`.
- [ ] Run the tests against the current paths and record the expected import failures for the new paths.
- [ ] Move scripts and update resource references, preserving all room metadata and authored tile placement.
- [ ] Remove fixed game-specific fallbacks from framework runtime code.
- [ ] Run room, world, fog, save, transition, and reference-game startup tests.

### Task 8: Add optional `platformer_debug` and diagnostics

**Files:**
- Create: `addons/platformer_debug/plugin.cfg`
- Create: `addons/platformer_debug/platformer_debug_plugin.gd`
- Move/adapt: `scripts/tools/debug_hud.gd`, `debug_map.gd`, `grid_overlay.gd`, and `tuning_hotkeys.gd`
- Create: `tests/platformer_debug/test_debug_contract.gd`
- Create: `examples/movement_lab/debug_overlay.tscn`

**Interfaces:**
- Debug tools subscribe to public framework state and never alter gameplay state.
- Debug display is optional and removable from a scene without breaking runtime startup.

- [ ] Write tests for optional loading and read-only display bindings.
- [ ] Run focused tests before implementation.
- [ ] Move the tools behind the addon boundary and add toggles for collision, sensors, motor state, and IDs.
- [ ] Run the movement lab with the debug addon enabled and disabled.

### Task 9: Implement optional abilities and combat modules

**Files:**
- Create: `addons/platformer_abilities/` runtime scripts, resources, plugin manifest, and tests
- Create: `addons/platformer_combat/` runtime scripts, resources, plugin manifest, and tests
- Create: `examples/ability_lab/ability_lab.tscn`
- Create: `examples/combat_lab/combat_lab.tscn`

**Interfaces:**
- Abilities use `AbilityDefinition`, `AbilityRuntime`, `AbilityController`, and `AbilityContext`; a definition is data and a runtime object owns transient state.
- Combat uses `DamageData`, `DamageEvent`, `HealthComponent`, `Hitbox`, `Hurtbox`, `Invulnerability`, and `Knockback`.
- Neither addon references concrete game content.

- [ ] Write tests for cooldown, activation eligibility, cancellation, damage routing, invulnerability, knockback, and module-disabled startup.
- [ ] Run focused tests before implementation.
- [ ] Implement ability and combat primitives with data-driven resources.
- [ ] Build the two labs and verify they launch independently.
- [ ] Run all framework, lab, and reference-game tests.

### Task 10: Implement `metroidvania_kit` as an optional layer

**Files:**
- Create: `addons/metroidvania_kit/plugin.cfg`
- Create: `addons/metroidvania_kit/progression/`
- Create: `addons/metroidvania_kit/gates/`
- Create: `addons/metroidvania_kit/discovery/`
- Create: `addons/metroidvania_kit/world_state/`
- Create: `addons/metroidvania_kit/map/`
- Create: `addons/metroidvania_kit/fast_travel/`
- Create: `tests/metroidvania_kit/`
- Create: `examples/metroidvania_demo/`

**Interfaces:**
- Conditions include `HasAbilityCondition`, `HasItemCondition`, `FlagCondition`, and `CompositeCondition`.
- Gates consume a progression context and do not inspect concrete player fields.
- Discovery and fast travel consume stable room IDs and save state.

- [ ] Write tests for condition evaluation, gate denial/approval, room discovery persistence, and fast-travel eligibility.
- [ ] Run them before implementation.
- [ ] Implement the optional module and its demo using only public framework APIs.
- [ ] Run the demo with the module enabled and verify the base movement lab still works without it.

### Task 11: Reconnect and rename the World Editor

**Files:**
- Move/adapt: `addons/wellwell_world_editor/` to `addons/world_editor/`
- Update: `addons/world_editor/plugin.cfg`
- Update: editor references to framework world contracts
- Create: `tests/world_editor/test_world_editor_framework_boundary.gd`
- Update: `README.md` and `docs/extension-guide.md`

**Interfaces:**
- World Editor depends on `platformer_kit/world` authoring contracts only.
- Runtime framework has no dependency on World Editor.
- Existing room baking, terrain preview, snapping, focus, and WorldData operations retain their current public behavior.

- [ ] Write a boundary test that loads the editor with the framework plugin disabled and confirms runtime scenes still load.
- [ ] Run it before rewiring and capture the expected old-path failure.
- [ ] Move the plugin and update all resource paths without changing authored room tile data.
- [ ] Run World Editor contract tests, project validation, and headless editor initialization.
- [ ] Leave new editor features out of this task.

### Task 12: Package documentation and framework versioning

**Files:**
- Create: `addons/platformer_kit/README.md`
- Create: `CHANGELOG.md`
- Create: `MIGRATION.md`
- Modify: `README.md`
- Modify: `docs/extension-guide.md`
- Create: `tests/tools/test_framework_documentation_contract.gd`

**Interfaces:**
- Framework version is declared in the addon manifest and project metadata.
- Public classes, resources, signals, and methods are listed as API surface.
- Migration notes describe path and API changes from the current reference game.

- [ ] Add a documentation contract test for the version, dependency rules, and lab launch commands.
- [ ] Run it before the documents exist and verify the expected failure.
- [ ] Write the framework README, changelog, and migration guide with the final directory map.
- [ ] Run documentation, boundary, full runtime, project validation, and headless editor checks.
- [ ] Confirm the reference game and all labs launch before considering the migration complete.

## Verification Matrix

Every task must run the narrowest relevant test first, then the affected
integration tests. The final release gate is:

```powershell
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tests/run_runtime_suite.gd
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tools/validate_project.gd
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path . --quit
git diff --check
```

The migration is complete only when the framework boundary validator reports
no framework-to-game references, the reference game launches, each lab
launches independently, and disabling optional addons does not break the base
platformer runtime.
