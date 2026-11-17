# Changelog

All notable Platformer Kit changes are recorded here. The project follows Semantic Versioning while the framework is developed as a reusable addon.

## [Unreleased]

### Added

- Reusable contact/interaction checkpoints with nested respawn points and immediate persistence requests.
- Persistent generic ability pickups and a data-driven Dash definition/runtime.
- Reference-player ability loadout synchronized with Metroidvania progression and save restoration.
- Eight-way Dash: vertical and diagonal dashing, with direction deadzone, facing fallback, and 45-degree snapping (`DashAbilityDefinition.eight_directional`).
- Dash charges (`max_charges`, `refill()`): one dash per landing by default, unlimited while the game chooses to refill every frame (swimming).
- Interactive Ability Lab using the same player, pickup, and Dash resources as the reference game.
- Room backdrop plate layer (`BackdropField` + `backdrop_drift` shader) with per-scanline air shimmer behind every room.
- Screen-space CRT finish (`crt_screen` shader) that keeps bright pixels bright, with a `crt_enabled` video setting.

### Changed

- Replaced two-point platform motion with paused multi-waypoint `PING_PONG` and `CYCLE` routes.
- Routed entity save requests through room and world runtimes instead of direct singleton access.

### Removed

- Removed `PingPongMotionComponent2D`; migrate authored platforms to `WaypointMotionComponent2D`.

## [0.1.0] - 2026-09-09

### Added

- Data-driven character motor, intent, sensors, movement profiles, and camera bounds.
- Composable moving, falling, rider-triggered, and conveyor platform behaviors.
- Generic interaction, stable-ID save, room, world graph, streaming, and transition contracts.
- Optional abilities, combat, Metroidvania, diagnostics, and World Editor addons.
- Independent movement, ability, combat, and Metroidvania example scenes.

### Changed

- Separated reusable framework code from reference game content.
- Moved map discovery and room authoring into optional addons.
- Defined relative, platform, and world velocity as distinct diagnostics.

### Removed

- Concrete one-way, moving, falling, and conveyor platform scripts in favor of native collision settings and composable components.
