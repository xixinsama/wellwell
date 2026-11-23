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

- [x] Write a failing boundary test with one allowed framework reference, one allowed game-to-framework reference, and one forbidden framework-to-game reference.
- [x] Run `godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/tools/test_framework_boundaries.gd` and verify it fails on the forbidden reference rule.
- [x] Implement the validator using `DirAccess` and `FileAccess`, scanning only `.gd`, `.tscn`, and `.tres` files under `addons/platformer_kit/`.
- [x] Fix the existing World Editor dialog contract in the scene without changing its editor behavior beyond the resource restriction.
- [x] Register the test in `tests/runtime_suite.gd`.
- [x] Run the focused boundary test, the World Editor command test, and `tools/validate_project.gd`.

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

- [x] Write a failing contract test requiring the addon manifest, version field, and runtime/editor separation.
- [x] Run the focused test and confirm the package is missing.
- [x] Add the minimal manifest and `EditorPlugin`; keep `_enter_tree()` side-effect free except for editor registrations owned by the framework.
- [x] Add the initial package contract test to the runtime suite.
- [x] Add core primitive tests for state transitions, scoped event delivery, and tag add/remove/containment behavior.
- [x] Implement the core primitives with typed inputs and deterministic update order.
- [x] Run the contract test and headless editor initialization.

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
- `CharacterIntent` exposes `move_axis: float`, `jump_pressed: bool`, `jump_released: bool`, `jump_held: bool`, and `fast_fall: bool`, plus `clear_transient() -> void`.
- `InputSource` exposes `get_intent() -> CharacterIntent`.
- `MovementProfile` stores max speed, acceleration, deceleration, gravity, jump speed, fall speed, coyote time, jump buffer time, and variable jump parameters.

- [x] Write tests proving intent contains no `Input` dependency and transient fields clear without changing `move_axis`.
- [x] Run the focused tests and verify the new classes are absent.
- [x] Implement the data classes and a player input adapter that reads project actions only at the adapter boundary.
- [x] Migrate the current tuning resource values into `default_movement_profile.tres` without changing gameplay values.
- [x] Run focused tests and compare the reference game launch behavior.

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

- [x] Write tests for acceleration, deceleration, gravity, jump buffering, coyote time, variable jump release, and terminal velocity.
- [x] Run them before implementation and verify each failure is caused by missing motor behavior.
- [x] Implement the smallest motor API needed by the tests; keep all constants in `MovementProfile`.
- [x] Adapt the current player scene through the wrapper without changing collision layers or authored visuals.
- [x] Run character tests, the existing player/runtime tests, and a headless launch.

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

- [x] Write tests for wall/ceiling detection, floor normal capture, platform velocity inheritance, one-chunk camera locking, and multi-chunk camera movement.
- [x] Run focused tests before implementation.
- [x] Implement sensors and platform motion without putting platform-specific logic in the motor.
- [x] Implement the interaction contract and detector as a framework-neutral base facility.
- [x] Migrate the existing camera tests and scene references.
- [x] Run the camera, sensor, platform, and full runtime tests.

### Task 6: Create the `movement_lab` reference example

**Files:**
- Create: `examples/movement_lab/movement_lab.tscn`
- Create: `examples/movement_lab/movement_lab.gd`
- Create: `tests/examples/test_movement_lab.gd`
- Modify: `README.md` with the launch command

**Interfaces:**
- The lab uses only `platformer_kit` runtime APIs and test fixtures; it contains no game-specific production logic.
- The lab demonstrates slopes, one-way platforms, moving platforms, a low ceiling, a wall, a narrow gap, a falling platform, and a conveyor.

- [x] Add a scene contract test requiring the named lab fixtures and framework player composition.
- [x] Run it before the scene exists and confirm the expected failure.
- [x] Create the smallest playable lab scene.
- [x] Run the lab headless with `--quit-after 2` and the focused contract test.

### Task 7: Migrate world, room, and persistence contracts

**Files:**
- Move/adapt: `scripts/world/data/` to `addons/platformer_kit/world/data/`
- Move/adapt: `scripts/world/runtime/` to `addons/platformer_kit/world/runtime/`
- Move/adapt: `scripts/world/entities/` to `addons/platformer_kit/world/entities/`
- Move/adapt generic save snapshots, codecs, storage, and manager services from `scripts/save/` to `addons/platformer_kit/save/`
- Keep application display/audio/localization settings outside the framework save module
- Keep `map_model.gd` and fog/discovery behavior outside the base world module until Task 10
- Create: `addons/platformer_kit/save/saveable.gd`
- Create: `addons/platformer_kit/save/persistent_id.gd`
- Create/adapt: `addons/platformer_kit/world/region/`, `world/graph/`, and `world/transition/` contracts
- Create: `tests/platformer_kit/world/`
- Create: `tests/platformer_kit/save/`
- Update all internal `.tscn`, `.tres`, `.gd`, and test references atomically

**Interfaces:**
- `WorldData`, `RoomData`, region/graph topology, room placement, room connection, `WorldRuntime`, `RoomRuntime`, and save snapshots become framework contracts.
- Persistent entities expose stable IDs and save/restore methods through `Saveable`; no `NodePath` or instance ID is persisted.
- World/session startup receives its world, player, camera, terrain, and save adapters explicitly instead of resolving concrete global names.
- Generic world contracts contain no discovery state, map UI coordinates, fog renderer, or map marker policy.

- [x] Add tests proving framework world and save classes load without `main_world.tres` or `/root/SaveManager`.
- [x] Run the tests against the current paths and record the expected import failures for the new paths.
- [x] Move scripts and update resource references, preserving all room metadata and authored tile placement.
- [x] Remove fixed game-specific fallbacks from framework runtime code.
- [x] Run room, world, save, transition, legacy-fog compatibility, and reference-game startup tests.

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

- [x] Write tests for optional loading and read-only display bindings.
- [x] Run focused tests before implementation.
- [x] Move the tools behind the addon boundary and add toggles for collision, sensors, motor state, and IDs.
- [x] Run the movement lab with the debug addon enabled and disabled.

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

- [x] Write tests for cooldown, activation eligibility, cancellation, damage routing, invulnerability, knockback, and module-disabled startup.
- [x] Run focused tests before implementation.
- [x] Implement ability and combat primitives with data-driven resources.
- [x] Build the two labs and verify they launch independently.
- [x] Run all framework, lab, and reference-game tests.

### Task 10: Implement `metroidvania_kit` as an optional layer

**Files:**
- Create: `addons/metroidvania_kit/plugin.cfg`
- Create: `addons/metroidvania_kit/progression/`
- Create: `addons/metroidvania_kit/gates/`
- Create: `addons/metroidvania_kit/world_state/`
- Create: `addons/metroidvania_kit/map/data/`
- Create: `addons/metroidvania_kit/map/discovery/`
- Create: `addons/metroidvania_kit/map/markers/`
- Create: `addons/metroidvania_kit/map/runtime/`
- Create: `addons/metroidvania_kit/map/ui/`
- Create: `addons/metroidvania_kit/fast_travel/`
- Create: `tests/metroidvania_kit/`
- Create: `examples/metroidvania_demo/`

**Interfaces:**
- Conditions include `HasAbilityCondition`, `HasItemCondition`, `FlagCondition`, and `CompositeCondition`.
- Gates consume a progression context and do not inspect concrete player fields.
- Map data projects `platformer_kit/world` topology into independent authored map coordinates; it never derives layout directly from scene positions.
- `MapDiscovery` owns `HIDDEN`, `DISCOVERED`, `VISITED`, and `CLEARED` room state, while fog is a replaceable reveal/presentation policy.
- `RevealRule` supports current-room, adjacent-room, region, radius, reveal-all, and game-provided policies without changing map runtime code.
- Marker discovery and lifecycle state are independent from room discovery.
- `MapRuntime` and `MapTracker` contain no `Control`, `CanvasItem`, or concrete UI dependencies; map UI reads their public state.
- Save data contains stable room/marker discovery state, never map controls, zoom, renderer nodes, or TileMap state.
- Discovery and fast travel consume stable room IDs and save state.

- [x] Write tests for condition evaluation, gate denial/approval, independent map coordinates, discovery transitions, marker state, reveal rules, persistence, and fast-travel eligibility.
- [x] Run them before implementation.
- [x] Implement the optional module and its demo using only public framework APIs.
- [x] Run the demo with the module enabled and verify the base movement lab still works without it.

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

- [x] Write a boundary test that loads the editor with the framework plugin disabled and confirms runtime scenes still load.
- [x] Run it before rewiring and capture the expected old-path failure.
- [x] Move the plugin and update all resource paths without changing authored room tile data.
- [x] Run World Editor contract tests, project validation, and headless editor initialization.
- [x] Leave new editor features out of this task.

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

- [x] Add a documentation contract test for the version, dependency rules, and lab launch commands.
- [x] Run it before the documents exist and verify the expected failure.
- [x] Write the framework README, changelog, and migration guide with the final directory map.
- [x] Run documentation, boundary, full runtime, project validation, and headless editor checks.
- [x] Confirm the reference game and all labs launch before considering the migration complete.

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
