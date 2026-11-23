# Addons

Eight addons live under `addons/`. Five are built and maintained in this
repository; three are vendored third-party code. This page is the index: what each
one owns, where its README is, and which tests cover it.

## Project-built addons

| Addon | Version | Owns | README | Tests |
| --- | --- | --- | --- | --- |
| `platformer_kit` | 0.1.0 | Character motor/sensors, platforms, interaction, camera, save, room/world streaming, abilities (`abilities/`), combat (`combat/`) | [README](../addons/platformer_kit/README.md) | `--group=platformer_kit` |
| `platformer_debug` | 0.1.0 | Read-only debug HUD, overlays, grid, debug map, TAS record/replay, tuning hotkeys | [README](../addons/platformer_debug/README.md) | `--group=platformer_debug` |
| `metroidvania_kit` | 0.1.0 | Progression, gates, map model/discovery/markers, fog, map UI, fast travel, save bridge | [README](../addons/metroidvania_kit/README.md) | `--group=metroidvania_kit`, plus `tests/world/test_fog_visibility.gd` |
| `fluid_kit` | 1.0.0 | Column water, grid water, GPU gas with CPU fallback, vents/interactors/lights | [README](../addons/fluid_kit/README.md) | `tests/world/test_world_water.gd`, `test_world_gas.gd` (`--group=world`) |
| `world_editor` | 0.3.0 | Editor main screen: room layout, draw/merge/split, terrain paint/sync, bake, 3D stack view | [README](../addons/world_editor/README.md) | `--group=authoring`, `--group=world_editor` |

Dependency direction is one-way: game content → optional addons → Platformer Kit
→ Godot. `tests/tools/test_framework_boundaries.gd` fails the suite if any addon
references `res://game/`.

## Vendored addons

These are third-party projects. Treat the directory as read-only: upgrade by
replacing the folder from upstream, not by hand-patching it. Adapt through the
project side (game code, scenes, settings) instead.

| Addon | Version | Role in this project | Notes |
| --- | --- | --- | --- |
| `input_mapping` | 0.1.0 | Rebindable input, settings UI, runtime service autoload (`InputMapping`) | Ships its own README and translations; enable the plugin, keep the autoload. |
| `pixelfx` | 0.3.0 | Baked pixel-effect library. **All effects are kept**; the game currently uses the four motion effects under `game/player/effects/`. | See `LICENSE` and `NOTICE.md` in the addon. `plugin.cfg` registers the library; effects are data-driven scenes, not project code. |
| `godot_mcp` | 4.1.11 | Development bridge between the editor and external agents (WebSocket server + `MCPGameBridge` autoload). | **Development-only.** It is not gameplay code: disable the plugin and remove the `MCPGameBridge` autoload before shipping an export. |

### Vendored health check (last review: 2026-11)

| Addon | State | Action |
| --- | --- | --- |
| `input_mapping` | Clean: full README, `plugin.cfg`, runtime service autoload `InputMapping`, CSV + `.translation` files present. | None. Patch upstream only. |
| `pixelfx` | Clean: `LICENSE` (MIT) + `NOTICE.md` (upstream attributions) present; 583 files, all effects intentionally kept; plugin enabled; the game uses four motion effects. | None. Re-import upstream wholesale to upgrade. |
| `godot_mcp` | Development bridge only; `plugin.cfg` + WebSocket server + game bridge. Port override 6550 in `project.godot`. | Keep out of exports; remove the autoload and plugin for a release build. |

No file inside a vendored addon was modified by this project. If an upgrade is
needed, replace the folder and re-run the suite; project-specific adaptations
belong in `game/` or `scenes/`.

## Compatibility

| Item | Value |
| --- | --- |
| Engine | Godot 4.7 (Forward Plus, pixel-art 2D settings) |
| Project version | `0.1.0` (`project.godot`, mirrors Platformer Kit) |
| Platformer Kit API | `0.x`; treat `class_name` declarations as source-level public |

## Verify an addon

```powershell
# whole suite
godot --headless --path . -s res://tests/run_runtime_suite.gd

# one owner
godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=platformer_kit

# one merged suite file
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/platformer_kit/abilities/test_abilities.gd

# addon scripts compile
godot --headless --path . --check-only -s res://addons/metroidvania_kit/map/runtime/map_runtime.gd
```

## Editing rules

- Keep addon code free of project paths (`res://game/`, `res://scenes/`,
  `res://examples/`). Demos and labs for an addon live in `examples/`.
- Every project-built addon has a README; when you add a public class, add it to
  that README's table in the same commit.
- Do not edit vendored addons. If a vendored addon needs a fix, record it here as
  an upgrade note and apply it after re-importing the upstream release.
