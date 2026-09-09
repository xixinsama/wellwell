# Platformer Kit 0.1.0

Platformer Kit is the reusable runtime foundation in this repository. It provides character motion, platform composition, interaction, cameras, rooms, world streaming, and stable-ID persistence without depending on a specific game or optional addon.

Godot 4.7 is the supported engine baseline for version `0.1.0`.

## Dependency Rules

Dependencies must point downward:

```text
Game Content
    -> Optional Addons
    -> Platformer Kit
    -> Godot
```

Code under `addons/platformer_kit/` must not reference `game/`, `scripts/`, examples, or optional addons. Optional Addons include `platformer_abilities`, `platformer_combat`, `metroidvania_kit`, `platformer_debug`, and `world_editor`. A game may enable only the modules it needs.

## Public API

All `class_name` declarations under this addon are source-level public in `0.x`. The main integration surface is:

| Area | Types | Primary API |
| --- | --- | --- |
| Core | `StateMachine`, `ScopedEventBus`, `TagContainer`, `GameEvent` | State transitions, scoped events, and tag queries |
| Character | `CharacterIntent`, `CharacterMotor2D`, `MovementContext`, `MovementProfile`, `CharacterSensors` | `CharacterMotor2D.step(intent, context, profile, delta)` |
| Platforms | `PlatformBody2D`, `PingPongMotionComponent2D`, `FallMotionComponent2D`, `RiderTriggerComponent2D`, `ConveyorSurfaceComponent2D` | `advance_motion()`, `reset_platform()`, `activate()`, `reset_component()` |
| Interaction | `Interactable`, `InteractionDetector` | `can_interact()`, `interact()`, `get_best_candidate()` |
| Camera | `PixelCamera2D` | `bind_target()`, `set_camera_mode()`, `set_room_bounds()`, `add_shake()` |
| Save | `PlatformerSaveManager`, `SaveSnapshot`, `SaveStorage`, `PersistentId`, `Saveable` | Slot operations, `commit()`, entity/module state serialization |
| World | `RoomData`, `WorldData`, `WorldGraph`, `WorldSession`, `WorldRuntime`, `RoomRuntime` | Room lookup, graph construction, session startup, streaming, and transitions |
| Entities | `WorldEntity`, `SpawnPoint`, `RoomEntrance`, `SavePoint`, `HazardEntity`, `PickupEntity` | Stable-ID state capture and room integration |

Resources such as `MovementProfile`, `RoomData`, `WorldData`, `RegionData`, and `RoomConnectionData` are data contracts. Prefer `.tres` instances over hard-coded game tuning.

## Signals

Stable integration signals include:

- `PlatformerSaveManager.snapshot_committing(snapshot)`, `slot_committed(slot)`, and `slot_selected(slot, snapshot)`.
- `WorldSession.world_ready()` and `world_start_failed(errors)`.
- `Interactable.interacted(actor)` and `InteractionDetector.candidate_changed(candidate)`.
- `PlatformBody2D.motion_collided(normal)` and `platform_reset(position)`.
- `FallMotionComponent2D.activated()`, `landed()`, and `reset()`.

Connect through these signals or the listed public methods. Do not call underscore-prefixed methods or depend on scene-internal node order unless a scene contract documents it.

## Platform Composition

Create an `AnimatableBody2D` with `PlatformBody2D`, then add direct child components. Components can be combined; for example, a platform can use both `PingPongMotionComponent2D` and `FallMotionComponent2D`. Use `CollisionShape2D.one_way_collision` for native one-way behavior. Character relative velocity remains separate from `get_platform_velocity()` and `get_real_velocity()`.

## Example Labs

Run each lab independently from the repository root:

```powershell
godot --path . res://examples/movement_lab/movement_lab.tscn
godot --path . res://examples/movement_lab/movement_lab_debug.tscn
godot --path . res://examples/ability_lab/ability_lab.tscn
godot --path . res://examples/combat_lab/combat_lab.tscn
godot --path . res://examples/metroidvania_demo/metroidvania_demo.tscn
```

Run automated verification with:

```powershell
godot --headless --path . -s res://tests/run_runtime_suite.gd
godot --headless --path . -s res://tools/validate_project.gd
```

## Compatibility

Version `0.x` may change source APIs between minor releases. Record breaking path, resource, signal, or method changes in the root `MIGRATION.md`, and record user-visible framework changes in `CHANGELOG.md`. Game-specific code belongs under `game/`; forked projects should modify framework code only when extending a generic contract.
