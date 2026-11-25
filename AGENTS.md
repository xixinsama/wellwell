# Repository Guidelines

`wellwell` is a Godot 4.7 pixel platformer kit plus five showcase worlds. It is
maintained by agents: humans mostly author rooms, art and tuning; agents fix,
optimise and extend the systems. Optimise every choice for those two readers.

## Read First

1. `docs/architecture.md` — directory map, dependency rules, verification.
2. `docs/README.md` — index: which subsystem doc and which code folder you need.
3. `docs/testing.md` — suite layout, groups, fixture hygiene.
4. `docs/extension-guide.md` — how to add a mechanic by composition.

## Where Code Belongs

- Reusable runtime goes in `addons/platformer_kit/` (core, character, platforms,
  interaction, camera, save, world, `abilities/`, `combat/`). It must never
  preload `res://game/`, `examples/`, project scenes, or an optional addon —
  `tests/tools/test_framework_boundaries.gd` fails the suite if it does.
- Optional engine-side modules go in their own addon: `platformer_debug`,
  `metroidvania_kit`, `fluid_kit`, `input_mapping`, `world_editor`, `pixelfx`.
- Project-specific code goes in `game/<area>/` (app, player, puzzle, save, ui,
  world, shaders, collectibles, entities, interaction, map, water). If the code
  is only useful to this game, it does not belong in an addon.
- Room source scenes go in `scenes/levels/<world_id>/`. Baked outputs in
  `scenes/rooms/generated/<room_id>/` and `resources/rooms/generated/` are
  generated: bake them with the World Editor, never hand-edit.
- World terrain is one scene per world: `scenes/worlds/<world_id>/terrain.tscn`.
  Rooms are rectangles sliced out of it at bake time.
- Tests mirror owners: `tests/<owner>/test_<feature>.gd`. New folder only for a
  new owner.
- One-shot CLI maintenance scripts go in `tools/`; runtime debug tools in the
  addon they serve.

## Build, Test, Verify

```powershell
godot --path .                                   # open the editor
godot --headless --path . -s res://tests/run_runtime_suite.gd
godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=world
godot --headless --path . --check-only -s <script>
godot --headless --editor --path . --quit        # refresh import/class caches
godot --headless --path . --quit-after 120       # boot log must stay clean
godot --headless --path . -s res://tools/validate_project.gd
```

A change is done only when the full suite exits 0, the boot log has no
`ERROR:`/`WARNING:` lines, and visible behaviour was checked with a deterministic
playtest (frozen game time + screenshot or runtime digest), not by eye.

Use the Godot MCP bridge for scene/resource work and playtests. Never hand-edit
`tile_map_data`; use the TileMapLayer tools. Do not invent `.uid` files. When art
is missing, ship a placeholder and say so.

## Script Hygiene (always on)

- Typed variables, explicit return types, small focused methods, `snake_case`
  files/functions, `PascalCase` `class_name`.
- Never reuse an engine member name for your own identifier (`position`,
  `material`, `size`, `name`, `root`, `visible`, `text`, `offset`, `scale`,
  `rotation`, `owner`, `theme`, `color`, …) — `SHADOWED_VARIABLE_BASE_CLASS`.
  Use the domain name: `door_position`, `scene_root`, `label`.
- Unused callback parameters get a `_` prefix, never deletion.
- Keep fractional math fractional (`cells.x / 2.0`); never shadow built-ins
  (`seed`, `randi`, `print`).
- `tests/tools/test_script_hygiene.gd` enforces the shadowing rules across the
  whole project. A finding is a test failure.

## Testing Rules

- Every `test_*.gd` must be registered in `tests/runtime_suite.gd`;
  `tests/tools/test_suite_registration.gd` enforces it both ways.
- Tests expose `run() -> Array[String]`; empty means success.
- Fixtures live under `user://`. If a test must write into `res://`, clean up
  recursively even on failure — a suite run must leave `git status` unchanged.
- Prove logic with the suite, prove visuals with a frozen playtest. "It looks
  right" is not evidence.

## Documentation Rules

- Paths in docs are live paths. Move code and update the docs in the same
  commit; `tests/tools/test_framework_documentation_contract.gd` guards the kit
  README, `CHANGELOG.md` and `MIGRATION.md`.
- Put subsystem docs in `docs/{authoring,systems,rendering}/` and link them from
  `docs/README.md`. Do not add a new top-level doc without adding it to the index.
- Design history belongs in git history, not in `docs/`.

## Commit Style

Short imperative subjects with a prefix: `feat:`, `fix:`, `refactor:`,
`chore:`, `docs:`, `test:`. One logical change per commit. Before editing, check
for existing user changes and never revert unrelated work.
