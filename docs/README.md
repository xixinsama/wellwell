# Documentation

Start with [architecture.md](architecture.md) — it is the directory map and the
dependency rules. Then pick the folder for the work in front of you.

## Read First

| Document | Use it when |
| --- | --- |
| [architecture.md](architecture.md) | You need to know where code belongs, what may depend on what, or which command proves a change. |
| [addons.md](addons.md) | You need the addon inventory: what is project-built, what is vendored, versions, READMEs and tests. |
| [extension-guide.md](extension-guide.md) | You are adding a mechanic and want the composition rules (player, platforms, doors, abilities, map, UI). |
| [testing.md](testing.md) | You are running or writing tests, or a suite run left files behind. |
| [roadmap.md](roadmap.md) | You are deciding what to build next, or checking the design references. |

## Authoring Content

| Document | Use it when |
| --- | --- |
| [authoring/world-painting.md](authoring/world-painting.md) | You are painting world terrain and baking rooms. |
| [authoring/world-alignment.md](authoring/world-alignment.md) | Chunk sizes, cell frames and why rooms snap the way they do. |
| [authoring/components-tutorial.md](authoring/components-tutorial.md) | You are assembling platforms, fog occluders, doors and phantom walls in a room. |
| [authoring/components-gallery.md](authoring/components-gallery.md) | You want a copyable node for each component. |

## Systems

| Document | Use it when |
| --- | --- |
| [systems/controls.md](systems/controls.md) | Keyboard and gamepad reference. |
| [systems/tuning.md](systems/tuning.md) | Player tuning resource and units. |
| [systems/ladders.md](systems/ladders.md) | Ladder tiles and ladder motion. |
| [systems/auto-route.md](systems/auto-route.md) | The in-game auto-route tool: set a start and a goal, plan a jump/dash/climb route, watch it run. |
| [benchmark.md](benchmark.md) | The 16-room solver benchmark: waypoints, per-room abilities and frame budgets, and how the stability cost changes routes. |
| [systems/doors.md](systems/doors.md) | Paired world doors, shuttle doors, entrance/spawn pairing. |
| [systems/collectibles.md](systems/collectibles.md) | Numbered collectibles and the collection screen. |
| [systems/map.md](systems/map.md) | Map model, precise/grid renderers, minimap. |
| [systems/fog-zones-and-crumble.md](systems/fog-zones-and-crumble.md) | Room fog, authored fog zones, crumble tiles, sight occluders. |
| [systems/terrain-highlight.md](systems/terrain-highlight.md) | Solid-tile highlight pass. |
| [systems/player-effects.md](systems/player-effects.md) | Jump/land/respawn particle effects. |
| [systems/water-and-mist.md](systems/water-and-mist.md) | Water basins, gas atmosphere, the demo rooms. |
| [systems/water-authoring.md](systems/water-authoring.md) | Painting a water room from scratch. |
| [systems/loop-world.md](systems/loop-world.md) | The Loop Cistern showcase world. |

## Rendering

| Document | Use it when |
| --- | --- |
| [rendering/art-layers.md](rendering/art-layers.md) | Bottom-to-top index of every visual layer. Start here for render work. |
| [rendering/render-pipeline.md](rendering/render-pipeline.md) | How one room is drawn, how masks stack, how to capture layers. |
| [rendering/lighting.md](rendering/lighting.md) | `LightField`, the light map contract, consumers. |
| [rendering/backdrop-and-dust.md](rendering/backdrop-and-dust.md) | Backdrop shadow and foreground dust layers. |
| [rendering/layers/crt.md](rendering/layers/crt.md) | CRT screen finish. |
| [rendering/layers/gas-layer.md](rendering/layers/gas-layer.md) | Gas render layer. |
| [rendering/layers/generated-assets.md](rendering/layers/generated-assets.md) | Normals, blue noise, light map — which assets are computed. |
| [rendering/layers/scene-structure.md](rendering/layers/scene-structure.md) | Why systems live in `world_root.tscn`, not the room template. |
| [rendering/layers/terrain-tiles.md](rendering/layers/terrain-tiles.md) | The three terrain tile layers and who reads each one. |

## Design and Roadmap

- [roadmap.md](roadmap.md) — planned work, sizing tables, design references.
- [design/puzzle-engine.md](design/puzzle-engine.md) — the grid-puzzle engine design (Chinese).
- [design/puzzle-mechanics.md](design/puzzle-mechanics.md) — the sliding-puzzle mechanics spec (Chinese).
- [design/README.md](design/README.md) — mockups and gameplay captures.

## Find Code by Feature

| Feature | Code | Tests | Doc |
| --- | --- | --- | --- |
| Player motion, stamina, dash orchestration | `game/player/`, `addons/platformer_kit/character/` | `tests/player/`, `tests/platformer_kit/character/` | [controls](systems/controls.md), [tuning](systems/tuning.md) |
| Auto-route planning and execution | `addons/platformer_kit/character/autopilot/`, `addons/platformer_debug/runtime/autopilot_tool.gd`, `tools/benchmark/` | `tests/platformer_kit/character/` | [auto route](systems/auto-route.md), [benchmark](benchmark.md) |
| Ability runtime (dash, climb, pickups) | `addons/platformer_kit/abilities/` | `tests/platformer_kit/abilities/` | [extension guide](extension-guide.md) |
| Combat (health, hit, hurt, knockback) | `addons/platformer_kit/combat/` | `tests/platformer_kit/combat/` | [extension guide](extension-guide.md) |
| Rooms, streaming, entities, save | `addons/platformer_kit/world/`, `addons/platformer_kit/save/` | `tests/world/`, `tests/save/` | [architecture](architecture.md) |
| Room/world authoring and bake | `addons/world_editor/` | `tests/authoring/`, `tests/world_editor/` | [world painting](authoring/world-painting.md) |
| Fog, map, progression | `addons/metroidvania_kit/` | `tests/metroidvania_kit/`, `tests/world/test_fog_*` | [map](systems/map.md), [fog](systems/fog-zones-and-crumble.md) |
| Water and gas | `addons/fluid_kit/`, `game/player/player_water_motion.gd` | `tests/world/test_water_*`, `tests/world/test_gas_*` | [water](systems/water-and-mist.md) |
| Lighting, backdrop, dust, CRT | `game/world/`, `game/shaders/` | `tests/world/test_light_field.gd`, `test_backdrop_*`, `test_dust_field.gd` | [rendering](rendering/art-layers.md) |
| Pixel effects | `addons/pixelfx/`, `game/player/effects/` | `tests/player/test_player_motion_effects.gd` | [player effects](systems/player-effects.md) |
| Sliding puzzle | `game/puzzle/`, `scenes/puzzle/` | `tests/puzzle/` | [puzzle mechanics](design/puzzle-mechanics.md) |
| Menus, settings, HUD | `scenes/ui/`, `game/ui/` | `tests/ui/` | [controls](systems/controls.md) |
| Input rebinding | `addons/input_mapping/` | `tests/input_mapping/` | — |
| Collectibles and map host | `game/collectibles/`, `game/map/` | `tests/game/` | [collectibles](systems/collectibles.md) |

## Conventions for These Docs

- Every path in a document is a live path. When you move code, update the docs
  in the same commit; `tests/tools/test_framework_documentation_contract.gd`
  fails when the contract documents drift.
- Prefer a table or a checklist over prose. The reader is usually an agent or a
  human fixing one concrete thing.
- Put world-specific notes in the world's own document (or the roadmap), not in
  the kit description.
