# Testing

The suite is plain GDScript: no plugin, no scene tree setup required. Each test
is a `Node` script exposing `run() -> Array[String]`; an empty array means
success and each string is a failure message.

## Run It

```powershell
# Everything (exit code 0 = green)
godot --headless --path . -s res://tests/run_runtime_suite.gd

# One owner folder while iterating
godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=world

# Several owners at once
godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=player,ui

# One script, while writing it
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_killzone.gd
```

The runner prints `runtime suite [scope]: N tests, M failures`. `--group` takes a
folder name under `tests/`; `platformer_kit` covers nested folders such as
`platformer_kit/abilities`.

## Layout: One Folder per Owner

| Folder | Owns |
| --- | --- |
| `tests/platformer_kit/` | Kit contract, character, platforms, interaction, save, world contracts; nested `abilities/` and `combat/` |
| `tests/platformer_debug/` | Debug HUD, TAS input source and hotkeys |
| `tests/metroidvania_kit/` | Progression conditions, map discovery/rendering/persistence, fog contract |
| `tests/input_mapping/` | Rebind model, service and UI |
| `tests/authoring/`, `tests/world_editor/` | Room/world bake, partition, canvas, editor commands and boundaries |
| `tests/game/` | Project composition: collectibles, pickups, ability loadout, interaction |
| `tests/world/` | World runtime, streaming, fog/crumble, light, water/gas, tilesets, terrain |
| `tests/player/` | Player rules, motion effects, hero animation |
| `tests/puzzle/` | Board rules, pieces, void sliders, gamepad selection |
| `tests/save/` | Save codec, storage, slots, realtime save |
| `tests/ui/` | Menu, settings pages, world select, prompts, collection screen |
| `tests/tools/` | Meta tests: script hygiene, framework boundaries, documentation contract, suite registration |

Add a test folder when you add an owner, not when you add one test.

## Merged Suites

Small tests live together so an owner has a handful of readable files instead of
dozens of 30-line ones. A merged file contains one inner class per original test:

```gdscript
extends Node

class KillzoneCase extends Node:
	## the original test body, untouched

func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(KillzoneCase.new()))
	...
	return failures

func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	...
```

Rules:

- Each class keeps its own consts and helpers, so merging never shares state.
- New test for an existing feature: add a class to that suite. A new feature or a
  test that needs specialised fixtures: its own `test_<feature>.gd` file.
- A class that outgrows its suite (roughly 400+ lines) gets its own file.
- The suite runner counts files, not inner classes; `runtime suite [world]: 15
  tests` means 15 registered files.

## Adding a Test

1. Put `tests/<owner>/test_<feature>.gd` next to the tests for that owner.
2. `extends Node`, expose `run() -> Array[String]`, collect failures locally.
3. Register it in `tests/runtime_suite.gd` — `tests/tools/test_suite_registration.gd`
   fails when a `test_*.gd` file is missing from the suite, and when the suite
   lists a missing file.
4. Use typed locals and explicit return types (see `AGENTS.md`). Unused callback
   parameters get a `_` prefix, never deletion.
5. Run `--group=<owner>` while writing, then the full suite before committing.

Tests may instantiate scenes and add nodes to themselves. Free what you create
(`queue_free()` for nodes, `free()` for RefCounted-free immediates) so the suite
does not leak RIDs at exit.

## Fixtures Must Not Dirty the Repository

- Put every fixture under `user://`.
- If a test has to write into `res://` (the world editor only imports worlds from
  `res://resources/worlds/`), delete it in a `finally`-style cleanup that runs
  even on failure. `DirAccess.remove_absolute()` does **not** remove a non-empty
  directory: walk it first (see `_remove_directory()` in
  `tests/authoring/test_room_partition_workflow.gd`).
- A suite run must leave `git status` unchanged. That is the acceptance test for
  fixture hygiene.

## What the Meta Tests Enforce

| Test | Failure means |
| --- | --- |
| `tests/tools/test_script_hygiene.gd` | A script shadows an engine member or a built-in function. Rename the identifier. |
| `tests/tools/test_framework_boundaries.gd` | An addon references `res://game/`. Move the logic into game code or invert the dependency. |
| `tests/tools/test_framework_documentation_contract.gd` | `addons/platformer_kit/README.md`, `CHANGELOG.md` or `MIGRATION.md` lost a required section, version or path mapping. |
| `tests/tools/test_project_validation.gd` | The shipped world/terrain contract is broken (empty room paths, stale fingerprints, missing placements). |
| `tests/tools/test_suite_registration.gd` | A test file is not registered, or the suite points at a missing file. |
| `tests/tools/test_project_layout.gd` | A script appears outside `game/`, `addons/`, `tests/` or `tools/`, or the retired `scripts/` root is referenced again. |

## Deterministic Gameplay Verification

Unit tests prove logic; they do not prove a scene feels right. For anything
visible, use the editor bridge:

1. `godot_editor_edit run` with `frozen=true`.
2. Drive setup with `godot_exec`, then `godot_game_time step` with inputs.
3. Read `godot_runtime_state digest` for values, and take a screenshot only for
   appearance.

Claiming "it works" needs the suite exit code, a clean boot log
(`godot --headless --path . --quit-after 120` with no `ERROR`/`WARNING`), and a
screenshot or digest for the behaviour you changed.
