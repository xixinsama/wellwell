# Checkpoint, Dash Pickup, and Waypoint Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver reusable checkpoint and Dash pickup scenes and replace single-target moving-platform motion with paused multi-waypoint routes without editing authored room TileMaps.

**Architecture:** World entities emit save requests that runtime layers route to the configured save manager. Optional abilities expose generic definitions, pickups, and Dash runtime state, while the reference-game player adapts those APIs to input and Metroidvania progression. Moving platforms use one waypoint component with explicit local offsets and loop semantics.

**Tech Stack:** Godot 4.7, typed GDScript, `.tscn` and `.tres` resources, plain GDScript runtime tests.

**Spec:** `docs/superpowers/specs/2026-09-09-checkpoint-dash-waypoint-showcase-design.md`

## Global Constraints

- Do not edit authored TileMap cell data or create the user's new room.
- Delete `PingPongMotionComponent2D`; do not retain a compatibility class or deprecated fields.
- Waypoint 1 is `(0, 0)` relative to the platform's authored position.
- Platformer Kit must not depend on optional addons or `game/`.
- Entities must not access the SaveManager singleton directly.
- Input is represented by `CharacterIntent`; ability runtime code must not call `Input`.
- Every behavior change starts with a failing regression test.

---

### Task 1: Replace Single-Target Motion with Waypoint Motion

**Files:**
- Create: `addons/platformer_kit/platforms/components/waypoint_motion_component_2d.gd`
- Remove: `addons/platformer_kit/platforms/components/ping_pong_motion_component_2d.gd`
- Modify: `tests/platformer_kit/platforms/test_platform_motion.gd`
- Modify: `tests/examples/test_movement_lab.gd`
- Modify: `examples/movement_lab/movement_lab.tscn`
- Modify: `scenes/levels/room_02_00.tscn`
- Modify: `scenes/rooms/generated/room_02_00/runtime.tscn`
- Modify: `addons/platformer_kit/README.md`
- Modify: `docs/extension-guide.md`

**Interfaces:**
- Produces `WaypointMotionComponent2D.LoopMode { PING_PONG, CYCLE }`.
- Produces `sample_velocity(delta: float) -> Vector2`, `reset_component() -> void`, and `waypoint_reached(index: int)`.

- [x] Replace the old platform assertions with tests that configure `PackedVector2Array([Vector2.ZERO, Vector2(10, 0), Vector2(10, 10)])` and verify `0,1,2,1,0` and `0,1,2,0` traversal.
- [x] Add failing assertions for exact arrival, a zero-velocity pause, invalid first waypoint, and reset to route index zero.
- [x] Run the runtime suite and confirm failures reference the missing waypoint component.
- [x] Implement constant-speed segment traversal with `travel_speed`, `arrival_pause_seconds`, `loop_mode`, current index, direction, and remaining pause.
- [x] Remove the old script and migrate two-point scene properties to waypoint arrays plus equivalent speed `distance / (cycle_duration / 2.0)`.
- [x] Run platform, example contract, and scene smoke tests.

### Task 2: Route Entity Save Requests Through World Runtime

**Files:**
- Modify: `addons/platformer_kit/save/save_snapshot.gd`
- Modify: `addons/platformer_kit/world/entities/world_entity.gd`
- Modify: `addons/platformer_kit/world/runtime/room_runtime.gd`
- Modify: `addons/platformer_kit/world/runtime/world_runtime.gd`
- Test: `tests/save/test_save_codec.gd`
- Test: `tests/world/test_world_entity.gd`
- Test: `tests/world/test_room_runtime.gd`
- Test: `tests/world/test_world_runtime.gd`

**Interfaces:**
- `SaveSnapshot.set_respawn(room_id: String, spawn_id: String, position: Vector2) -> bool`.
- `WorldEntity.save_requested(immediate: bool)` and `request_save(immediate: bool = false) -> void`.
- `RoomRuntime.save_requested(immediate: bool)` forwards descendant entity requests.

- [x] Add failing tests proving respawn validation and proving an entity's immediate request reaches a fake persistence manager through RoomRuntime and WorldRuntime.
- [x] Run the runtime suite and confirm missing methods/signals are the failure cause.
- [x] Implement `set_respawn()` and generic request signaling without singleton access.
- [x] Connect descendant entity signals in `RoomRuntime`, then connect staged room runtimes in `WorldRuntime` and route immediate requests to `commit(_snapshot)` and delayed requests to `queue_commit()`.
- [x] Run all save and world-runtime tests.

### Task 3: Build the Reusable Checkpoint Scene

**Files:**
- Modify: `addons/platformer_kit/world/entities/save_point.gd`
- Create: `addons/platformer_kit/world/entities/save_point.tscn`
- Create: `tests/world/test_save_point.gd`
- Modify: `tests/runtime_suite.gd`

**Interfaces:**
- `SavePoint.ActivationMode { CONTACT, INTERACT }`.
- `activate(actor: Node = null) -> bool` updates respawn and requests immediate persistence.
- Scene exposes `ActivationArea`, `Interactable`, and nested `SpawnPoint` children.

- [x] Add a failing test that instances the scene, injects a snapshot sink, activates it, and asserts room ID, spawn ID, position, persistent state, and one immediate save request.
- [x] Add failing tests for one activation per room instance, restored visual state, contact mode, and interaction mode.
- [x] Implement the root entity and scene using native Area2D collision children and the existing `Interactable` API.
- [x] Register the test and run checkpoint, entity, room-runtime, and save tests.

### Task 4: Build the Generic Persistent Ability Pickup

**Files:**
- Create: `addons/platformer_abilities/entities/ability_pickup.gd`
- Create: `addons/platformer_abilities/entities/ability_pickup.tscn`
- Create: `tests/platformer_abilities/test_ability_pickup.gd`
- Modify: `tests/runtime_suite.gd`

**Interfaces:**
- `AbilityPickup.collect_for(body: Node) -> bool`.
- Receiver contract: `grant_ability_definition(definition: Resource) -> bool`.

- [x] Add failing tests for missing definition, incompatible body, successful grant, duplicate ownership confirmation, persistent hidden state, and immediate save request.
- [x] Run the runtime suite and confirm the scene/script is missing.
- [x] Implement contact collection by extending `PickupEntity`; collect only after receiver confirmation.
- [x] Create a reusable scene with `VisualRoot`, `ActivationArea`, and collision shape.
- [x] Register and run ability, entity-persistence, and addon-boundary tests.

### Task 5: Implement Dash Runtime and Generic Ability Intent

**Files:**
- Modify: `addons/platformer_kit/character/input/character_intent.gd`
- Modify: `addons/platformer_kit/character/input/player_input_source.gd`
- Create: `addons/platformer_abilities/abilities/dash/dash_ability_definition.gd`
- Create: `addons/platformer_abilities/abilities/dash/dash_ability_runtime.gd`
- Create: `addons/platformer_abilities/abilities/dash/default_dash.tres`
- Modify: `addons/platformer_abilities/runtime/ability_controller.gd`
- Test: `tests/platformer_kit/character/test_character_intent.gd`
- Test: `tests/platformer_kit/character/test_input_source.gd`
- Create: `tests/platformer_abilities/test_dash_ability.gd`
- Modify: `tests/runtime_suite.gd`

**Interfaces:**
- `CharacterIntent.press_action(action: StringName) -> bool` and `is_action_pressed(action: StringName) -> bool`.
- `PlayerInputSource.additional_actions: Array[StringName]`.
- `DashAbilityRuntime.get_velocity_override() -> Vector2` and `is_motion_overriding() -> bool`.

- [x] Add failing tests for generic transient intent actions and configured input action capture.
- [x] Add failing Dash tests for direction normalization, configured speed, duration expiry, cooldown, and cancellation.
- [x] Implement named intent actions and move controller ticking to `_physics_process()`.
- [x] Implement Dash definition/runtime without direct Input or game dependencies and create the default resource.
- [x] Register tests and run all character, ability, and boundary tests.

### Task 6: Connect Dash to the Reference Player and Progression

**Files:**
- Create: `game/player/player_ability_loadout.gd`
- Modify: `scenes/player/player.tscn`
- Modify: `scripts/player/player_controller.gd`
- Modify: `addons/metroidvania_kit/world_state/metroidvania_persistence_bridge.gd`
- Modify: `scripts/app/main.gd`
- Modify: `project.godot`
- Create: `tests/game/test_player_ability_loadout.gd`
- Modify: `tests/platformer_kit/character/test_character_motor_integration.gd`
- Modify: `tests/metroidvania_kit/test_map_runtime_persistence.gd`
- Modify: `tests/runtime_suite.gd`

**Interfaces:**
- `PlayerAbilityLoadout.bind_progression(progression: RefCounted) -> bool`.
- `grant_ability_definition(definition: Resource) -> bool`, `synchronize_unlocked_abilities() -> void`, and `get_motion_override(intent: RefCounted, environment: RefCounted, facing: int) -> Dictionary`.
- `MetroidvaniaPersistenceBridge.state_restored()`.

- [x] Add failing tests proving grant updates progression, duplicate grants remain successful without duplicate runtime, restored progression reinstalls Dash, and active Dash overrides velocity.
- [x] Add a failing integration assertion that normal motor velocity is replaced only while Dash is active.
- [x] Implement the game-owned loadout with a definition registry and AbilityController child.
- [x] Add the loadout to the player scene; delegate pickup grants and apply its override after motor stepping but before `move_and_slide()`.
- [x] Add `dash` to project input and bind the loadout to the progression context and bridge restore signal in `Main`.
- [x] Run game, player, ability, Metroidvania persistence, menu, and boundary tests.

### Task 7: Upgrade the Ability Lab and Document Authoring

**Files:**
- Modify: `examples/ability_lab/ability_lab.tscn`
- Modify: `examples/ability_lab/ability_lab.gd`
- Create: `tests/examples/test_ability_lab.gd`
- Modify: `tests/runtime_suite.gd`
- Modify: `addons/platformer_kit/README.md`
- Modify: `CHANGELOG.md`
- Modify: `MIGRATION.md`
- Modify: `docs/extension-guide.md`

**Interfaces:**
- Ability Lab instances the same default Dash resource and pickup used by the reference game.
- Documentation gives exact SavePoint and AbilityPickup authoring steps.

- [x] Add a failing scene-contract test requiring the ability pickup, reference player integration, and reusable Dash definition.
- [x] Replace the startup-only label demonstration with an interactive pickup and observable Dash cooldown/state while retaining independent launch.
- [x] Update platform component and entity authoring documentation, including the breaking waypoint migration.
- [x] Run the full runtime suite and project validator.
- [x] Run headless editor initialization and 120-frame smoke launches for the reference game and all five labs.
- [x] Review scene diffs and confirm no authored room TileMap cell data changed.
