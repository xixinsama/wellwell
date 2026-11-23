# Platformer Kit Plugin Architecture

## Status

Approved direction for the next planning cycle. This document defines the
target architecture; it does not authorize implementation of every module at
once.

## Goal

Turn `wellwell` from a game template into a reusable 2D platformer framework
SDK. A future game should fork or consume the framework, place its content in
`game/`, and avoid rewriting character movement, camera, rooms, persistence,
damage, respawn, or optional Metroidvania infrastructure.

The dependency direction is always:

```text
Game Content -> Optional Modules -> Platformer Kit -> Godot
```

The framework must never reference concrete game content.

## Repository Boundaries

```text
res://
├── addons/
│   ├── platformer_kit/       # reusable runtime framework and contracts
│   ├── world_editor/         # optional Godot editor plugin
│   ├── platformer_debug/     # optional development diagnostics
│   ├── platformer_abilities/ # optional ability runtime
│   ├── platformer_combat/    # optional damage and health runtime
│   └── metroidvania_kit/     # optional progression and exploration layer
├── game/                     # concrete game content and composition
├── examples/                 # framework verification scenes and demos
├── tests/                    # framework and integration tests
└── assets/                   # project-owned art and audio
```

`platformer_kit` is internally divided into `core`, `character`, `camera`,
`platforms`, `interaction`, `world`, `save`, `contracts`, `resources`, and
`debug`-independent runtime code. These directories are modules, not separate
Godot plugins unless they later need an independent editor lifecycle.

`world_editor` consumes framework world contracts and never becomes a runtime
dependency. The existing world editor is frozen during the first migration
stages and can be renamed and moved after its contracts stabilize.

## Module Responsibilities

### Platformer Kit

Owns framework-neutral services and data: state machines, events, tags,
`CharacterIntent`, `CharacterEnvironmentSnapshot`, `CharacterMotor2D`,
movement profiles, sensors, pixel camera behavior, platform motion, rooms,
spawns, checkpoints, stable persistent IDs, save interfaces, and world
runtime contracts.

The motor does not read `Input`, inspect animation state, know about HP, or
look up autoloads. Runtime services are passed through explicit references or
small interfaces rather than hard-coded node paths.

### Optional Modules

`platformer_abilities` owns ability definitions, runtime instances, cooldowns,
and ability context. `platformer_combat` owns hitboxes, hurtboxes, health,
damage events, invulnerability, teams, and knockback. Neither module may
contain concrete player, enemy, weapon, or boss content.

`metroidvania_kit` depends on the world, save, and ability contracts. It owns
progression context, ability/item/flag conditions, gates, room discovery,
world state, maps, and fast travel. A basic platformer must be able to omit it.

### World And Map Separation

`platformer_kit/world` describes the playable world only: rooms, regions,
transitions, spawn points, and a `WorldGraph` of stable node and edge IDs. Graph
edges may carry direction, one-way, transition, door, or requirement metadata,
but the base world module does not track whether the player has seen or visited
anything. This keeps linear platformers independent from Metroidvania systems.

`metroidvania_kit/map` is a projection of those world contracts. Its authored
map coordinates are independent from scene/global coordinates so designers can
compress large rooms, offset floors, hide secret rooms, and draw intentionally
non-literal connections. Game content supplies `MapDefinition` resources; the
optional module supplies their schemas and runtime behavior.

The map module is split by responsibility:

```text
addons/metroidvania_kit/map/
├── data/       # MapDefinition, MapRegion, MapRoom, MapConnection
├── discovery/  # DiscoveryState, MapDiscovery, RevealRule, visibility policy
├── markers/    # MapMarker, MarkerDefinition, MarkerRegistry
├── runtime/    # MapRuntime and MapTracker, with no Control dependencies
└── ui/         # MapView, minimap, rendering, pan and zoom
```

The physical sibling addon preserves the optional dependency boundary even
though this is conceptually the framework's `metroidvania` tier.

### Discovery And Fog

Map discovery is state, not UI. The baseline states are `HIDDEN`,
`DISCOVERED`, `VISITED`, and `CLEARED`; projects may map those states to any
visual treatment. World events update `MapDiscovery`, and map views only read
the resulting state. A fog renderer is a replaceable visibility presentation
or reveal strategy under `map/discovery`, never a world-level manager.

Reveal behavior is data driven through `RevealRule` implementations such as
current room, adjacent rooms, region, radius, and reveal all. Marker discovery
is separate from room discovery: a room may be visited while its boss, shop,
checkpoint, treasure, or custom marker remains hidden, active, or completed.

Persistence stores stable room discovery and marker states only. Runtime/UI
details such as `Control.position`, zoom, TileMap nodes, and renderer state are
not save data unless a concrete game deliberately treats them as user
preferences.

`platformer_debug` owns optional runtime overlays and visualizers for velocity,
state, sensors, collision, hitboxes, room IDs, persistent IDs, and ability
tags. It must be removable without changing gameplay behavior.

## Composition Rules

Concrete scenes, enemies, bosses, items, authored map definitions, menus, and
story data belong in `game/`. Framework and optional-module resources provide
schemas; game resources provide values and concrete behavior. Gameplay state controls animation;
animation completion must not be the source of gameplay state transitions.

The framework must not depend on `main_world.tres`, concrete level scenes,
game-specific autoload names, fixed player paths, or editor-only classes.
Editor tools may depend on framework data contracts, but runtime code must
remain loadable with editor plugins disabled.

## Migration Strategy

Migration uses a strangler approach so current gameplay remains runnable:

1. Freeze new World Editor features and establish a passing baseline.
2. Create framework contracts and the `platformer_kit` package boundary.
3. Migrate input intent, character motor, sensors, and movement profiles.
4. Add a `movement_lab` example and migrate camera/platform behavior.
5. Migrate interaction, combat, and health into optional modules.
6. Migrate abilities and condition-based gates.
7. Move generic room/region/graph streaming and stable-ID persistence behind
   framework APIs; keep map discovery out of the base world module.
8. Build Metroidvania map data, discovery, marker, runtime, and UI boundaries;
   migrate the existing fog behavior as one discovery presentation strategy.
9. Reconnect the existing World Editor to generic world contracts only.
10. Add debug labs, versioning, migration notes, and package checks.
11. Consider extracting the framework into a separate repository only after a
    stable `1.0.0` API exists.

Existing `level_0` through `level_3` content remains available as a reference
game during migration. It is moved to `examples/metroidvania_demo/` only after
replacement framework contracts have tests and the current runtime still
launches successfully.

## Verification Requirements

Each module must have focused runtime tests and at least one integration test
through its public contract. Static checks must reject framework-to-game
references. `movement_lab`, `combat_lab`, `ability_lab`, and
`metroidvania_demo` must launch independently. Framework tests must not require
the current project's main scene or concrete world resource.

The project uses semantic versioning for the framework. Public resource fields,
script classes, signals, and method signatures are API surface. Breaking
changes require `CHANGELOG.md`, `MIGRATION.md`, and an explicit version bump.

## Non-Goals

This phase does not redesign the World Editor, add new tile authoring tools,
create a specific game, or immediately split the repository into Git
submodules. Those activities follow API stabilization.
