# Architecture: One Project, Clear Layers

`wellwell` keeps a reusable 2D platformer kit, optional engine-side modules,
authored worlds, and the editor tooling in one Godot project while keeping the
dependencies pointing one way. This file is the map: read it first, then jump to
the subsystem document you need from [docs/README.md](README.md).

## Layers

- **Platformer Kit** — `addons/platformer_kit/` owns character motion, sensors,
  platforms, interaction, camera, save data, room streaming, world data
  contracts, the ability runtime (`abilities/`) and the combat runtime
  (`combat/`). It must not preload `game/`, `scripts/`, `examples/`, project
  scenes, or any optional addon.
- **Optional addons** — `platformer_debug` (overlay, TAS, tuning hotkeys),
  `metroidvania_kit` (progression, map discovery, fog, fast travel),
  `fluid_kit` (water and gas fields), `input_mapping` (rebindable controls),
  `pixelfx` (vendored pixel effect library), `world_editor` (main-screen
  authoring workbench), `godot_mcp` (development-only editor/game bridge).
- **Game composition** — `game/`, `scripts/player/`, and `scenes/` assemble the
  kit, the addons, and the current worlds. Game code may depend on the kit; the
  kit never depends on game code.
- **Worlds** — `resources/worlds/*.tres` hold `WorldData` only: room
  placements, connections, stacks. The menu reads
  `resources/worlds/world_catalog.tres`.

## Directory Map

| Path | What lives there | Edit it when |
| --- | --- | --- |
| `scenes/app/main.tscn` | Application entry, viewport scaling, menu/HUD wiring | Changing the boot flow |
| `scenes/runtime/world_root.tscn` | Streamed world, player instance, room camera, room extensions, HUD bindings | Adding a room-wide system |
| `scenes/player/player.tscn` | The shipped player composition | Adding a player component |
| `scenes/levels/<world_id>/` | Editable room source scenes, one folder per world | Authoring room content |
| `scenes/levels/test_world/runners/` | Development launchers that skip the menu | Testing a room in isolation |
| `scenes/rooms/template/level_template.tscn` | Empty room authoring template | Changing the room contract |
| `scenes/rooms/generated/<room_id>/` | Baked `runtime.tscn` + `terrain.tscn` | Never by hand — bake it |
| `scenes/worlds/<world_id>/terrain.tscn` | The world's single authored terrain scene | Painting terrain |
| `scenes/ui/`, `scenes/world/`, `scenes/puzzle/` | Menus, reusable world components, puzzle pieces | UI or prefab work |
| `resources/worlds/` | `WorldData`, `WorldCatalog`, stacks | Adding or ordering worlds |
| `resources/rooms/generated/` | Baked `RoomData` resources | Never by hand — bake it |
| `resources/player/`, `resources/tilesets/`, `resources/ui/` | Tuning, tilesets, theme | Art and feel tuning |
| `addons/` | Reusable engine-side code (see Layers) | Framework work |
| `game/` | Project-specific composition: collectibles, entities, interaction, map host, water motion | Gameplay assembly |
| `scripts/player/`, `scripts/puzzle/`, `scripts/save/`, `scripts/ui/`, `scripts/world/` | Project gameplay systems not owned by an addon | Gameplay work |
| `tests/<owner>/` | One folder per module owner; every `test_*.gd` is listed in `tests/runtime_suite.gd` | Writing tests |
| `tools/` | One-shot CLI maintenance scripts run with `-s` | Repo maintenance |
| `examples/` | Movement, ability, combat, metroidvania and TAS fixture scenes | Trying the kit standalone |
| `docs/` | This map plus authoring, systems, rendering and design notes | Documentation |

## Dependency Rules

Dependencies flow downward:

```text
Game Content
    -> Optional Addons
    -> Platformer Kit
    -> Godot
```

`tools/validate_framework_boundaries.gd` enforces that no addon references
`res://game/`. `tests/tools/test_framework_boundaries.gd` runs it over every
addon on every suite run. The same test suite guards the documentation contract
(`tests/tools/test_framework_documentation_contract.gd`).

## Isolation Rules

- A world may only reference room IDs defined in that world. Do not share a room
  ID between two worlds with different content; give the variant its own ID and
  generated resource path.
- A mechanic is enabled by scene composition (nodes, components, resources), not
  by a global flag in the kit.
- Mechanics may promote generic fixes back into the kit. Examples already in
  this project: shared collision-rectangle merging, ladder contact refresh on
  respawn, and the one-shot rider air jump in the movement context.
- World-specific tuning and art live with the game content, not in Platformer
  Kit.
- New collision areas should merge adjacent cells. Ladder zones and puzzle void
  bodies use the shared `CellRectMerger`; do not emit one Area or shape per
  painted cell.
- Room geometry is local to its source scene. `WorldRoomPlacementData` stores an
  integer chunk origin; `RoomConnectionData` stores an entrance-to-spawn
  transition.

## Verification

```powershell
# Full test suite (fails the process on any failure)
godot --headless --path . -s res://tests/run_runtime_suite.gd

# One owner's tests while iterating
godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=world
godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=platformer_kit,player

# Compile check for a script you touched
godot --headless --path . --check-only -s res://path/to/script.gd

# Refresh import/class caches and catch editor-side breakage
godot --headless --editor --path . --quit

# Validate the shipped terrain/world contract
godot --headless --path . -s res://tools/validate_project.gd

# Re-bake every room after moving source scenes or changing the room template
godot --headless --path . -s res://tools/rebake_all_rooms.gd

# Boot with no warnings or errors
godot --headless --path . --quit-after 120
```

Rule of thumb: a change is not done until the suite is green, the boot log is
clean, and any visible change was checked in a deterministic playtest (frozen
game time + screenshot), not by "it looks right".

## Branch and Worktree Policy

- Keep one active integration branch and one main worktree for day-to-day work.
- Use short-lived branches for mechanics, worlds, and art experiments.
- Merge mechanics through their tests and the world catalog; do not copy an
  entire project directory to start a variant.
- When a mechanic exposes a kit weakness, fix the kit and add a regression test
  there before depending on the fix from the mechanic.
