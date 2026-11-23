# wellwell

A Godot 4.7 pixel platformer kit with a room/world authoring pipeline, streamed
rooms, fog of war, water/gas fields, and five showcase worlds. The project is
built to be **edited by humans and repaired by agents**: every subsystem has one
home, one test folder, and one document.

## Run It

```powershell
godot --path .                  # open the project, then F5
godot --path . res://scenes/app/main.tscn
```

The game boots to the menu: save slot → world select → play. The world list is
`resources/worlds/world_catalog.tres`.

## Worlds

| World | Id | What it shows |
| --- | --- | --- |
| 梯子试炼 | `the_world` | Ladders, climbing, five connected rooms |
| 滑块回廊 | `main_world` | Sliding puzzle boards, void sliders, gamepad selection |
| Exploration Test World | `test_world` | Fog zones, crumble tiles, doors, water hall, gas lab, light lab |
| 回环水窖 | `loop_world` | Water cascade, crumble planks, dash loop |
| 冲刺世界 | `dash_world` | Dash pickups, one-way piercing, stacked layer 1 |

Room source scenes live in `scenes/levels/<world_id>/`; baked runtime scenes in
`scenes/rooms/generated/<room_id>/` are generated — never edit them by hand.

## Layout

| Path | Contents |
| --- | --- |
| `addons/platformer_kit/` | Reusable runtime: character, platforms, camera, save, rooms/world streaming, abilities, combat |
| `addons/platformer_debug/` | Debug HUD, TAS record/replay, tuning hotkeys |
| `addons/metroidvania_kit/` | Progression, map discovery, fog, fast travel |
| `addons/fluid_kit/` | Water columns and gas atmosphere |
| `addons/input_mapping/` | Rebindable controls |
| `addons/pixelfx/` | Vendored pixel-effect library |
| `addons/world_editor/` | Main-screen world/room editor and baker |
| `scenes/`, `resources/` | Game scenes, worlds, rooms, tilesets, tuning |
| `game/`, `scripts/` | Project composition and the systems the kit does not own |
| `tests/` | One folder per owner; see `docs/testing.md` |
| `tools/` | One-shot CLI maintenance scripts |
| `examples/` | Kit labs: movement, ability, combat, metroidvania, TAS |
| `docs/` | Start at `docs/README.md`; the directory map is `docs/architecture.md` |

## Verify

```powershell
# Full suite: 153 tests, exit code 0 on success
godot --headless --path . -s res://tests/run_runtime_suite.gd

# One owner while iterating
godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=world

# Compile one script
godot --headless --path . --check-only -s res://scripts/player/player_controller.gd

# Boot with no warnings or errors
godot --headless --path . --quit-after 120

# Validate the shipped world/terrain contract
godot --headless --path . -s res://tools/validate_project.gd
```

## Controls

A/D move, Space/Z jump, X dash, E/C interact, M map, J collection, F1 grid
overlay. Full keyboard and gamepad reference: `docs/systems/controls.md`.

## Start Here

- `docs/architecture.md` — where code belongs, dependency rules, verification.
- `docs/extension-guide.md` — how to add a mechanic without touching the kit.
- `docs/authoring/world-painting.md` — paint terrain, bake rooms, place entities.
- `docs/testing.md` — suite layout, groups, fixture hygiene.
- `MIGRATION.md` — path mappings, including this cleanup branch's addon merge.
