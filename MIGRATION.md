# Migration Guide

This guide describes the repository migration to Platformer Kit `0.1.0`. Commit or back up game-specific work before moving files, then update resource paths and run the complete runtime suite.

## Cleanup Branch Mappings

The cleanup branch removed the separate ability/combat addons and grouped room
sources by world. Apply these path rewrites to forks of the project:

| Previous location | Current location | Action |
| --- | --- | --- |
| `addons/platformer_abilities/abilities/` | `addons/platformer_kit/abilities/` | Update preloads and scene script paths. |
| `addons/platformer_abilities/entities/` | `addons/platformer_kit/abilities/entities/` | Ability pickup scenes moved with the runtime. |
| `addons/platformer_abilities/runtime/` | `addons/platformer_kit/abilities/runtime/` | `AbilityController` and definitions now ship with the kit. |
| `addons/platformer_combat/runtime/` | `addons/platformer_kit/combat/` | Combat is a kit module, not a plugin. |
| `addons/platformer_abilities/plugin.cfg`, `addons/platformer_combat/plugin.cfg` | — | Remove them from `editor_plugins/enabled`; keep `platformer_kit/plugin.cfg`. |
| `scenes/levels/main/`, `scenes/levels/test/`, `scenes/levels/loop/`, `scenes/levels/room_*.tscn` | `scenes/levels/<world_id>/<room_id>.tscn` | Update `RoomData.source_scene_path`; bake fingerprints are content hashes and stay valid. |
| `scenes/levels/generated/<world_id>/` | `scenes/levels/<world_id>/` | New, merged and split rooms are written next to the hand-authored ones. |
| `scenes/levels/test/*_runner.tscn` | `scenes/levels/test_world/runners/` | Development launchers moved with the test world. |

## Directory Mappings

| Previous location | Current location | Action |
| --- | --- | --- |
| `scripts/authoring/` | `addons/world_editor/authoring/` | Update editor tool and room-template references. |
| `addons/wellwell_world_editor/` | `addons/world_editor/` | Replace plugin paths in `project.godot` and editor resources. |
| `scripts/world/fog/` | `addons/metroidvania_kit/map/discovery/` | Enable `metroidvania_kit` when the game uses map discovery or fog. |
| `scripts/world/data/map_model.gd` | `addons/metroidvania_kit/map/data/map_model.gd` | Update map resource script references. |
| reusable `scripts/player/` logic | `addons/platformer_kit/character/` | Keep only concrete player composition and presentation in game code. |
| reusable save scripts | `addons/platformer_kit/save/` | Update autoload and preload paths. |
| reusable room/world scripts | `addons/platformer_kit/world/` | Update scene and resource script paths. |

Historical design documents may retain old paths as records. Active scenes, scripts, tests, and project settings must use the current paths.

## Platform Migration

Replace concrete platform scripts with a `PlatformBody2D` host and child components:

- Moving platform: add `WaypointMotionComponent2D` and start `waypoints` with `(0, 0)`.
- Falling platform: add `FallMotionComponent2D` and optionally `RiderTriggerComponent2D`.
- Moving-then-falling platform: combine waypoint, fall, and rider-trigger components.
- Conveyor: add `ConveyorSurfaceComponent2D`.
- Fog shadow: add `FogOccluderComponent2D` under the platform body. It publishes
  the body's collision footprint to the `fog_occluder` group, so the platform
  hides what is behind it from the fog without a second size to maintain.
- One-way platform: remove the framework script and set `CollisionShape2D.one_way_collision = true`.

Do not add platform velocity to `CharacterBody2D.velocity`. The character motor owns relative velocity, `get_platform_velocity()` reports support transport, and `get_real_velocity()` reports collision-corrected world movement.

`PingPongMotionComponent2D` has no compatibility alias. Replace its script with
`addons/platformer_kit/platforms/components/waypoint_motion_component_2d.gd`.
Convert the old target to `PackedVector2Array([Vector2.ZERO, target_offset])`
and set `travel_speed` to `target_offset.length() / (cycle_duration / 2.0)`.
Use `PING_PONG` to preserve the old return trip.

## World Stack Storage

`WorldData.world_stack` is gone. A world that referenced its own stack formed an
unloadable two-file cycle (the stack lists the world back), which made the world
catalog fail to load. The editor now finds the stack next to the world as
`<world>_stack.tres`; keep the stack resource at that path and remove any
`world_stack = ...` line from saved worlds.

## Fog Door Migration

`scripts/world/fog_door.gd` is gone. `scenes/world/fog_door.tscn` keeps its path
and its `Node2D` root but is now composed of `Body` (`StaticBody2D`),
`DoorComponent2D` and `FogOccluderComponent2D`:

- Remove room-instance overrides that assign the old script or the removed
  `door_id` export; both would otherwise fail to resolve.
- Re-bake rooms that instance the prefab. Door state stays runtime-only.
- A custom door is a `StaticBody2D` plus `DoorComponent2D` (point
  `body_path` / `sense_path` at the body and the sense area) and, for a sight
  blocker, a `FogOccluderComponent2D` in `DoorComponent2D.occluder_paths`.

## Save Integration

Persist long-lived entities with exported stable IDs rather than `NodePath` or `instance_id`. Save listeners must accept the snapshot emitted by `snapshot_committing(snapshot)` and ignore snapshots that are not active for their world session.

Optional modules store namespaced data through `SaveSnapshot.set_module_state(module_id, state)`. Do not serialize UI nodes or editor state into gameplay snapshots.

## World Editor

Enable `res://addons/world_editor/plugin.cfg`. Configure the fork-specific room template without modifying the plugin:

```ini
[world_editor]
room_template_scene="res://scenes/rooms/template/level_template.tscn"
```

Source rooms remain authored scenes. Generated room scenes and `.tres` files remain bake outputs; world placement belongs to `WorldData`.

### World Terrain Storage

Terrain is authored once per world, not per room:

| Before | Now |
| --- | --- |
| Each room source owned its `RoomContent/Terrain` cells | `scenes/worlds/<world_id>/terrain.tscn` owns every cell in world cell coordinates |
| Baking packed the room's own terrain | Baking slices the room's cell rectangle out of the world terrain |
| World editor painted terrain with a brush | **Edit Terrain** opens the terrain scene in the normal Godot editor; **Sync Terrain** re-slices and re-bakes every room |

Room source scenes keep an empty `RoomContent/Terrain` (the authoring contract
still requires the layers), but their cells are ignored at bake time. Run
`tools/migrate_world_terrain.gd` (dry-run first) to move existing room terrain
into the world scenes and clear the room cells; it backs every modified scene up
to `resources/worlds/_migration_backup/`.

The World editor can also create rooms (**Draw Room**), merge the selection into
one room (**Merge**, the union must be a rectangle) and split a room at a chunk
boundary (**Split**). Both partition operations use new room ids and back the
world and the replaced room assets up before touching them.

## Verification

After migrating, run:

```powershell
godot --headless --path . -s res://tests/run_runtime_suite.gd
godot --headless --path . -s res://tools/validate_project.gd
godot --headless --editor --path . --quit
```

Then launch the reference game and each scene listed under `Example Labs` in `addons/platformer_kit/README.md`.
