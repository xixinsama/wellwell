# Platformer Kit 0.1.0

Platformer Kit is the reusable runtime foundation in this repository. It provides character motion, platform composition, interaction, cameras, rooms, world streaming, and stable-ID persistence without depending on a specific game or optional addon.

Godot 4.7 is the supported engine baseline for version `0.1.0`.

| Item | Value |
| --- | --- |
| Godot | 4.7 |
| Autoloads | `SaveManager` (`save/save_manager.gd`) is the only one the kit needs |
| Optional modules | `abilities/` and `combat/` ship inside the kit; the game may leave them unused |
| Editor plugin | `plugin.cfg` (no editor UI; safe to disable) |

## Modules

| Module | Path | Contents |
| --- | --- | --- |
| Core | `core/` | `StateMachine`, `ScopedEventBus`, `TagContainer`, `GameEvent` |
| Character | `character/` | `CharacterIntent`, `CharacterMotor2D`, `MovementContext`, `MovementProfile`, sensors, ladder motion, input sources, and the `autopilot/` route solver (`AutopilotGrid`, `AutopilotMotion`, `AutopilotPlanner`, `AutopilotDriver`, shared-state guard `autopilot_lock.gd`) |
| Platforms | `platforms/` | `PlatformBody2D` plus waypoint / fall / elevator / conveyor / rider / fog-occluder components |
| Interaction | `interaction/` | `Interactable`, `InteractionDetector` |
| Camera | `camera/` | `PixelCamera2D` |
| Save | `save/` | `PlatformerSaveManager`, `SaveSnapshot`, `SaveCodec`, `SaveStorage`, `Saveable`, `PersistentId` |
| World | `world/` | Room/world data contracts, glue, entities, doors, phantom walls, streaming, transitions, validation |
| Abilities | `abilities/` | `AbilityController`, definitions/runtimes, Dash, Climb, pickups |
| Combat | `combat/` | `HealthComponent`, `Hitbox`, `Hurtbox`, `DamageData`/`DamageEvent`, invulnerability, knockback |

## Dependency Rules

Dependencies must point downward:

```text
Game Content
    -> Optional Addons
    -> Platformer Kit
    -> Godot
```

Code under `addons/platformer_kit/` must not reference `game/`, `scripts/`, examples, or optional addons. The kit ships the core runtime plus the `abilities/` and `combat/` modules; optional addons are `metroidvania_kit`, `platformer_debug`, `world_editor`, `fluid_kit`, `input_mapping`, and `pixelfx`. A game may enable only the modules it needs.

## Public API

All `class_name` declarations under this addon are source-level public in `0.x`. The main integration surface is:

| Area | Types | Primary API |
| --- | --- | --- |
| Core | `StateMachine`, `ScopedEventBus`, `TagContainer`, `GameEvent` | State transitions, scoped events, and tag queries |
| Character | `CharacterIntent`, `CharacterMotor2D`, `MovementContext`, `MovementProfile`, `CharacterSensors` | `CharacterMotor2D.step(intent, context, profile, delta)` |
| Auto route | `AutopilotGrid`, `AutopilotMotion`, `AutopilotPlanner`, `AutopilotRoute`, `AutopilotDriver` | `AutopilotGrid.build(space, cell_rect, ladder_rects, avoid_rects)`, `AutopilotPlanner.plan(state, goal)`, `AutopilotDriver.set_route(route)` |
| Platforms | `PlatformBody2D`, `WaypointMotionComponent2D`, `FallMotionComponent2D`, `ElevatorMotionComponent2D`, `RiderTriggerComponent2D`, `ConveyorSurfaceComponent2D`, `FogOccluderComponent2D` | `advance_motion()`, `reset_platform()`, `activate()`, `reset_component()`, `is_occluding()`, `get_world_rect()` |
| Interaction | `Interactable`, `InteractionDetector` | `can_interact()`, `interact()`, `get_best_candidate()` |
| Camera | `PixelCamera2D` | `bind_target()`, `set_camera_mode()`, `set_room_bounds()`, `add_shake()` |
| Save | `PlatformerSaveManager`, `SaveSnapshot`, `SaveStorage`, `PersistentId`, `Saveable` | Slot operations, `commit()`, entity/module state serialization |
| World | `RoomData`, `WorldData`, `WorldGraph`, `WorldSession`, `WorldRuntime`, `RoomRuntime` | Room lookup, graph construction, session startup, streaming, and transitions |
| Entities | `WorldEntity`, `SpawnPoint`, `RoomEntrance`, `SavePoint`, `HazardEntity`, `PickupEntity` | Stable-ID state capture and room integration |
| Doors | `DoorComponent2D` | `set_closed()`, `toggle()`, `door_opened`, `door_closed` |
| Hidden walls | `PhantomWallComponent2D` | `reveal()`, `reset_component()`, `wall_revealed`, `is_occluding()`, `get_world_rect()` |
| Abilities | `AbilityController`, `AbilityDefinition`, `AbilityRuntime`, `DashAbilityRuntime`, `AbilityPickup`, `AbilityContext` | `grant()`, `activate()`, `is_unlocked()`, `available_abilities()` |
| Combat | `HealthComponent`, `Hitbox`, `Hurtbox`, `DamageEvent`, `DamageData`, `Invulnerability`, `Knockback` | `apply_damage()`, `heal()`, `can_be_hit()`, `hit_landed()` |

Resources such as `MovementProfile`, `RoomData`, `WorldData`, `RegionData`, and `RoomConnectionData` are data contracts. Prefer `.tres` instances over hard-coded game tuning.

## Signals

Stable integration signals include:

- `PlatformerSaveManager.snapshot_committing(snapshot)`, `slot_committed(slot)`, and `slot_selected(slot, snapshot)`.
- `WorldSession.world_ready()` and `world_start_failed(errors)`.
- `Interactable.interacted(actor)` and `InteractionDetector.candidate_changed(candidate)`.
- `PlatformBody2D.motion_collided(normal)` and `platform_reset(position)`.
- `WaypointMotionComponent2D.waypoint_reached(index)`.
- `FallMotionComponent2D.activated()`, `landed()`, and `reset()`.

Connect through these signals or the listed public methods. Do not call underscore-prefixed methods or depend on scene-internal node order unless a scene contract documents it.

## Platform Composition

Create an `AnimatableBody2D` with `PlatformBody2D`, then add direct child components. Components can be combined; for example, a platform can use both `WaypointMotionComponent2D` and `FallMotionComponent2D`. Waypoints are local offsets, start with `(0, 0)`, and support `PING_PONG` or `CYCLE` traversal plus a pause at every arrival. Use `CollisionShape2D.one_way_collision` for native one-way behavior. Character relative velocity remains separate from `get_platform_velocity()` and `get_real_velocity()`.

Add `FogOccluderComponent2D` under the body when the platform should hide what is behind it. It answers the fog's `is_occluding()` / `get_world_rect()` contract with the host's collision footprint, joins the `fog_occluder` group, and refreshes the `fog_of_war` group only when the footprint crosses an 8 px cell. The kit never imports the Metroidvania addon: the wiring is the group names and the two methods.

A door is a `StaticBody2D` plus `DoorComponent2D` (size, state, collision, interaction, panel) and, when it should block sight, a `FogOccluderComponent2D` listed in `DoorComponent2D.occluder_paths`.

A phantom wall is a `TileMapLayer` with collision disabled and `PhantomWallComponent2D` attached: the painted cells look like terrain, can be walked through, block sight while the wall stands, and fade out when a character touches them. `scenes/world/phantom_wall.tscn` is the prefab. Erase the matching `SolidTiles` cells when authoring, or the old collision keeps the player out.

## World Entities

Instance `world/entities/save_point.tscn` under a source room's `RoomContent/Entities`. Give each instance a unique `entity_id` or `persistent_id`, choose `CONTACT` or `INTERACT`, and set its nested `SpawnPoint.spawn_id` to a room-unique value. Re-bake the room so the spawn ID enters its manifest.

For an ability reward, instance `addons/platformer_kit/abilities/entities/ability_pickup.tscn`, assign a stable ID, and set `ability_definition`. The supplied Dash uses `addons/platformer_kit/abilities/dash/default_dash.tres`. A compatible body must implement `grant_ability_definition(definition) -> bool`; collection occurs only after that method returns `true`.

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
godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=platformer_kit
godot --headless --path . -s res://tools/validate_project.gd
```

## Tests

| Suite file | Covers |
| --- | --- |
| `tests/platformer_kit/test_kit_contract.gd` | State machine, event bus, tags, core primitives |
| `tests/platformer_kit/character/test_character_motor_2d.gd` | Run/fall, over-speed friction, jump buffer, coyote, variable jump, lift caps, tick-rate equivalence |
| `tests/platformer_kit/character/test_character_input.gd` | Intent, input source, movement profile, sensors |
| `tests/platformer_kit/character/test_ladder_motion.gd` | Ladder component |
| `tests/platformer_kit/character/test_autopilot.gd` | Route grid, jump/dash/wall/ladder simulation, A\* reachability and route continuity, input replay |
| `tests/platformer_kit/platforms/test_platforms.gd` | Footprints, waypoint routes, composed motion, fall policies, riders, conveyor, native one-way |
| `tests/platformer_kit/interaction/test_interaction.gd` | Detector/Interactable contract |
| `tests/platformer_kit/save/test_save_contracts.gd` | Snapshot validation, entity/module state, commit ordering |
| `tests/platformer_kit/world/test_world_contract_independence.gd` | World contracts without optional addons |
| `tests/platformer_kit/abilities/test_abilities.gd` | Runtime, pickup, Climb, Dash composition |
| `tests/platformer_kit/combat/test_combat_runtime.gd` | Health, hit/hurt routing, teams, invulnerability, knockback |

## Known Limits

- The kit is runtime only: no enemies, dialogue, animation player, or menuing; those
  belong to the game composition.
- Save slots are fixed to `1..3` (`SaveCodec`/`SaveStorage`/`SaveManager`). Change
  all three together if a fork needs more.
- Abilities and combat are modules: a game that does not instance
  `AbilityController` / add `Hitbox`+`Hurtbox` pays nothing for them, but the kit
  also does not auto-wire them into a player.
- `PlatformBody2D` components assume an `AnimatableBody2D` host moved through
  physics; teleporting the host directly skips `advance_motion()` bookkeeping.
- The fog occluder communicates through group names and two methods; it does not
  require the Metroidvania addon, so deleting that addon leaves harmless group
  traffic.

## Compatibility

Version `0.x` may change source APIs between minor releases. Record breaking path, resource, signal, or method changes in the root `MIGRATION.md`, and record user-visible framework changes in `CHANGELOG.md`. Game-specific code belongs under `game/`; forked projects should modify framework code only when extending a generic contract.
