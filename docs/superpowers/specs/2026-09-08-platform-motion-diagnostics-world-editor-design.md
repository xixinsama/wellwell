# Platform Motion, Diagnostics, and World Editor Design

## Scope

This change repairs snapshot commit integration, replaces concrete platform
types with composable platform behavior, clarifies character velocity
semantics, improves runtime diagnostics, and completes Platformer Kit Task 11
by moving the World Editor to `addons/world_editor/`. Existing authored room
tile data and the overall example layouts are not redesigned.

## Save Commit Contract

`PlatformerSaveManager.snapshot_committing` emits the snapshot that is about
to be written. Every listener must accept that argument. `WorldSession` owns
an adapter callback that verifies the emitted snapshot is its active snapshot
before asking `WorldRuntime` to persist loaded entity states. Runtime methods
remain independent of SaveManager signals and keep focused zero-argument APIs.

## Character Velocity Contract

The framework exposes three different values instead of calling all motion
`velocity`:

- `relative_velocity`: locomotion velocity controlled by CharacterMotor and
  stored in `CharacterBody2D.velocity`.
- `platform_velocity`: velocity reported by Godot for the current supporting
  body, including moving-body and constant surface motion.
- `world_velocity`: actual post-slide motion reported by
  `CharacterBody2D.get_real_velocity()`.

The controller never manually adds platform velocity before `move_and_slide()`;
Godot already carries a CharacterBody with its platform. This prevents double
application and preserves `platform_on_leave` behavior. Debug output displays
all three values explicitly.

## Composable Platforms

`PlatformBody2D` is a generic `AnimatableBody2D` host. Child components provide
behavior:

- `PingPongMotionComponent2D` contributes reversible path velocity.
- `FallMotionComponent2D` contributes gravity after activation and supports
  either stopping on collision or ignoring collisions.
- `RiderTriggerComponent2D` activates configured components when a character
  enters its Area2D.
- `ConveyorSurfaceComponent2D` configures Godot's
  `constant_linear_velocity`; it does not modify player code.

The body combines active motion contributions once per physics frame and owns
collision-aware movement. A ping-pong component and fall component can coexist,
which produces a moving platform that falls after being stepped on. Components
emit activation, collision, landing, and reset signals where applicable.

One-way collision remains a native `CollisionShape2D.one_way_collision`
property. The redundant `OneWayPlatform` runtime script and compatibility path
are removed. Future map generation sets the native property directly.

## Diagnostics

The optional Debug HUD remains read-only. It uses compact grouped rows for
motion, contacts, timers, and identity. Motion shows relative, platform, and
world velocity together, plus the current supporting platform identity when
available. The visualizer retains independent layer toggles and adds vectors
for the three velocity values without becoming a gameplay dependency.

## World Editor Task 11

The plugin moves from `addons/wellwell_world_editor/` to
`addons/world_editor/` and is renamed `World Editor`. Its internal authoring
helpers belong to the plugin; shared resources and runtime contracts come only
from `addons/platformer_kit/world`. Runtime scenes and Platformer Kit must not
reference the editor addon. Existing bake, terrain preview, chunk snapping,
focus, and WorldData behavior remain unchanged. Historical design documents
are not rewritten, but active documentation and tests use the new path.

## Verification

Tests cover the signal adapter, velocity reporting, component composition,
fall collision modes, native one-way configuration, debug rendering, and
World Editor dependency boundaries. Completion requires the full runtime suite,
framework boundary validation, headless editor import, and smoke launches for
the main scene and Movement Lab. Visual and feel acceptance remains a manual
Godot-editor check.
