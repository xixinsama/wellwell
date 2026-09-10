# Extension Guide

`wellwell` is meant to branch easily. Add mechanics by composing around the player controller instead of expanding it into a large game-specific coordinator.

## Versioning Discipline

Treat `addons/platformer_kit/` as a versioned dependency. The framework version
is declared in its `plugin.cfg` and mirrored by `application/config/version` in
`project.godot`. Read `CHANGELOG.md` and `MIGRATION.md` before importing a newer
version into an existing game. Keep game-specific resources and scripts under
`game/` so framework upgrades do not overwrite content.

Dependencies flow from game content to optional addons to Platformer Kit to
Godot. Platformer Kit must never preload game code, examples, or optional
modules.

## Recommended Boundaries

- Keep reusable character motion in `addons/platformer_kit/character/`; concrete player composition may remain in `scripts/player/` or move under `game/player/`.
- Keep generic room data, streaming, and entities in `addons/platformer_kit/world/`.
- Keep map discovery and fog policy in `addons/metroidvania_kit/map/discovery/`.
- Put authoring code in `addons/world_editor/authoring/room/` or `addons/world_editor/authoring/world/`.
- Put reusable debug-only tools in `addons/platformer_debug/`.
- Use Resource files for tuning values.
- Keep visual feedback free to scale, flash, or animate, but do not move `SpriteRoot.position` away from `Vector2.ZERO`.

## SubViewport Safety Border

The game uses a 322x182 `SubViewport` while treating 320x180 as the safe design frame. The extra 1 pixel on each side prevents edge artifacts during camera smoothing and small screen shakes.

The integer scale is calculated from the 320x180 safe frame, not the larger 322x182 viewport. At 1280x720 this gives 4x scale, so the displayed viewport is 1288x728 and is centered at `(-4, -4)`. The outer window clips the hidden safety border.

If you change the viewport size, preserve the same idea:

- Decide the safe gameplay size first.
- Add a small hidden border.
- Integer-scale the larger viewport.
- Round the final camera position to source pixels.

## Adding Mechanics

Platform behavior is composed under `PlatformBody2D`: use
`WaypointMotionComponent2D`, `FallMotionComponent2D`,
`RiderTriggerComponent2D`, and `ConveyorSurfaceComponent2D` independently or
together. Native one-way platforms only require
`CollisionShape2D.one_way_collision`; no framework script is needed.

Configure `WaypointMotionComponent2D.waypoints` as offsets from the platform's
authored position. Point zero must be `Vector2.ZERO`. Choose `PING_PONG` for
routes such as `1, 2, 3, 2, 1`, or `CYCLE` for `1, 2, 3, 1`; set
`arrival_pause_seconds` for the delay at each point.

## Checkpoints and Ability Rewards

Add `addons/platformer_kit/world/entities/save_point.tscn` below a source
room's `RoomContent/Entities`. Set a unique `entity_id` or `persistent_id`, set
the nested `SpawnPoint.spawn_id`, and choose `CONTACT` or `INTERACT`. The entity
updates respawn state before requesting an immediate save. Bake the source room
after adding it; never add checkpoints directly to generated scenes.

Add `addons/platformer_abilities/entities/ability_pickup.tscn` for a persistent
ability reward. Assign a stable ID and an `AbilityDefinition`; use
`addons/platformer_abilities/abilities/dash/default_dash.tres` for the supplied
Dash. Player-like receivers opt in with
`grant_ability_definition(definition: Resource) -> bool`. A rejected grant does
not consume the pickup.

Good first game-specific extensions:

- Moving platforms.
- Ladders.
- Simple hazards.
- Room transition tests.
- Additional data-driven abilities.

For rooms, edit source scenes only. Generated runtime scenes, terrain scenes, and `RoomData` resources are bake outputs. `RoomData` is reusable local content; `WorldData.placements` owns each room's chunk origin and `WorldData.connections` owns transitions.

Depend on optional combat or progression addons from game content; never add
concrete enemies, items, or story rules to Platformer Kit.
