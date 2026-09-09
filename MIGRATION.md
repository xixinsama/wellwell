# Migration Guide

This guide describes the repository migration to Platformer Kit `0.1.0`. Commit or back up game-specific work before moving files, then update resource paths and run the complete runtime suite.

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

- Moving platform: add `PingPongMotionComponent2D`.
- Falling platform: add `FallMotionComponent2D` and optionally `RiderTriggerComponent2D`.
- Moving-then-falling platform: combine ping-pong, fall, and rider-trigger components.
- Conveyor: add `ConveyorSurfaceComponent2D`.
- One-way platform: remove the framework script and set `CollisionShape2D.one_way_collision = true`.

Do not add platform velocity to `CharacterBody2D.velocity`. The character motor owns relative velocity, `get_platform_velocity()` reports support transport, and `get_real_velocity()` reports collision-corrected world movement.

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

## Verification

After migrating, run:

```powershell
godot --headless --path . -s res://tests/run_runtime_suite.gd
godot --headless --path . -s res://tools/validate_project.gd
godot --headless --editor --path . --quit
```

Then launch the reference game and each scene listed under `Example Labs` in `addons/platformer_kit/README.md`.
