# Checkpoint, Dash Pickup, and Waypoint Platform Design

**Date:** 2026-09-09

## Goal

Provide reusable checkpoint and ability-pickup entity scenes for the integrated reference game, implement Dash as the first real optional ability, and replace the single-target moving-platform behavior with a multi-waypoint route. The user authors the new room and TileMap; this change supplies components and scene contracts only.

## Ownership Boundaries

- `platformer_kit` owns checkpoints, entity save requests, waypoint platform motion, and generic character intent.
- `platformer_abilities` owns ability definitions, pickup behavior, and the reusable Dash runtime.
- `metroidvania_kit` owns permanent ability-unlock state.
- `game/player` adapts the reference player to optional abilities and progression.
- Plugins never reference `game/`, room scenes, or concrete world resources.

## Waypoint Motion

`PingPongMotionComponent2D` is removed rather than retained as a compatibility layer. It is replaced by `WaypointMotionComponent2D`.

```gdscript
@export var waypoints: PackedVector2Array
@export var travel_speed: float
@export var arrival_pause_seconds: float
@export var loop_mode: LoopMode

enum LoopMode {
    PING_PONG,
    CYCLE,
}
```

Waypoints are local offsets from the platform's authored position. The first point must be `(0, 0)` and represents the initial position. `PING_PONG` traverses `1, 2, 3, 2, 1`; `CYCLE` traverses `1, 2, 3, 1`. Every arrival emits `waypoint_reached(index)` and pauses for `arrival_pause_seconds`. Movement uses constant `travel_speed`, clamps to the target without overshoot, and resets to point 1.

Existing active scenes are migrated from `travel_offset` and `cycle_duration` to two-point waypoint arrays and equivalent constant speed. Authored TileMap cell data is not changed.

## Checkpoint Entity

`addons/platformer_kit/world/entities/save_point.tscn` contains a `SavePoint` root, visual root, contact area, interaction area, and nested `SpawnPoint`. It supports contact and interaction activation modes. Contact activation occurs once per loaded room instance; unloading and returning permits another activation even when the persistent activated state is already true.

Activation performs this transaction in order:

1. Set the snapshot respawn room, spawn ID, and exact global position.
2. Capture the checkpoint's persistent entity state.
3. Emit an immediate save request.
4. Route the request through `RoomRuntime` and `WorldRuntime` to the bound save manager.

Entities do not access the SaveManager singleton. `WorldEntity` exposes a generic save-request signal, and `SaveSnapshot` exposes `set_respawn()`.

## Ability Pickup and Dash

`addons/platformer_abilities/entities/ability_pickup.tscn` is a persistent contact pickup with an exported `AbilityDefinition`. It calls `grant_ability_definition(definition)` on the entering body. Only a successful grant collects, hides, and immediately saves the pickup.

Dash is configured by a `DashAbilityDefinition` resource with speed, duration, cooldown, and optional vertical input. `DashAbilityRuntime` owns activation duration and direction but does not read `Input` or know the concrete player.

Generic `CharacterIntent` gains named transient actions, and `PlayerInputSource` maps configured actions such as `dash`. The reference player's `PlayerAbilityLoadout`:

- registers known ability definitions;
- synchronizes unlocked IDs from `ProgressionContext`;
- grants definitions from pickups;
- activates Dash from intent;
- applies Dash velocity after normal motor calculation and before `move_and_slide()`.

The existing `PlayerController` remains the concrete game composition point. Platformer Kit does not depend on the optional ability plugin.

## Persistence Flow

The Metroidvania persistence bridge emits a restore notification after loading progression state. The reference loadout listens and reinstalls every unlocked definition into `AbilityController`. On pickup, progression is updated before the immediate snapshot commit, so both the ability unlock and collected entity state reach the same disk write.

Loading an old or empty snapshot produces no unlocked abilities. Unknown saved ability IDs remain in progression data but are ignored by a loadout that has no matching definition, preserving forward compatibility.

## Authoring Contract

The user creates and lays out the new room. To use these systems:

1. Instance `save_point.tscn` under the room's `Entities` node.
2. Assign unique `entity_id`, `persistent_id`, and checkpoint `spawn_id` values.
3. Instance `ability_pickup.tscn` under `Entities` and assign the default Dash definition.
4. Bake the room and add it to the world using the existing World Editor workflow.

No room scene or world placement is created automatically by this implementation.

## Error Handling

- Invalid waypoint lists return zero motion and report validation failures in tests.
- A checkpoint without a state sink updates visual state but reports activation failure and does not claim a disk save.
- A pickup with no definition or an incompatible body remains collectible.
- Duplicate ability grants do not duplicate runtimes; an already-owned pickup may still be consumed when the receiver confirms ownership.

## Verification

Tests cover route order, pauses, exact arrivals, reset, migrated fixtures, checkpoint respawn updates, immediate save routing, pickup persistence, Dash activation and expiry, input decoupling, progression restoration, and plugin dependency boundaries. Final verification runs the full runtime suite, project validator, headless editor initialization, and 120-frame smoke launches for the reference game and all labs.
