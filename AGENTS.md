# Repository Guidelines

## Project Structure & Module Organization

`wellwell` is a compact Godot 4 pixel-platformer template. The main scene is `res://scenes/main.tscn`, with gameplay routed through `scenes/game.tscn` and player content in `scenes/player/`. GDScript lives under `scripts/`: keep movement code in `scripts/player/`, save/settings code in `scripts/save/`, world triggers and fog systems in `scripts/world/`, camera logic in `scripts/camera/`, and debug-only helpers in `scripts/tools/`. Reusable resources belong in `resources/`, including player tuning at `resources/player/default_player_tuning.tres`. Tests are grouped by feature under `tests/save/` and `tests/world/`; add new test scripts to `tests/runtime_suite.gd`.

## Build, Test, and Development Commands

- `godot --path .`: open/run the project locally using `project.godot`.
- `godot --path . res://scenes/main.tscn`: run the main scene directly.
- `godot --headless --path . -s res://tests/run_runtime_suite.gd`: run the runtime test suite and return a nonzero exit code on failure.

Use the Godot editor for `.tscn`, `.tres`, and project setting changes when practical, since serialized files are easy to corrupt by hand.

## Coding Style & Naming Conventions

Use GDScript with typed variables, explicit return types, and small focused methods. Match the existing naming style: `snake_case` for files, methods, variables, input actions, and test files; `PascalCase` for `class_name` values such as `PlayerController`. Prefer exported `Resource` tuning values over hard-coded constants for gameplay feel. Keep physics authority in `_physics_process()` and preserve float positions/velocities; pixel clarity is handled by viewport scaling, texture settings, and camera rounding.

## Testing Guidelines

Runtime tests are plain GDScript nodes exposing `run() -> Array[String]`, where an empty array means success and each string describes a failure. Name tests by feature, for example `tests/world/test_fog_visibility.gd`. After adding a test file, preload it in `tests/runtime_suite.gd`. Run the headless suite before submitting movement, save, scene-contract, or world-system changes.

## Commit & Pull Request Guidelines

Recent history uses short subjects with prefixes such as `feat:`, `fix:`, and `docs:`. Keep commit messages imperative and scoped, for example `fix: preserve coyote time after platform exit`. Pull requests should include a concise behavior summary, commands run, linked issues or tasks, and screenshots or short captures for visible gameplay, scene, camera, or debug-HUD changes.

## Agent-Specific Instructions

Before editing, check for existing user changes and avoid reverting unrelated work. Keep additions aligned with `docs/extension-guide.md`: compose new mechanics around the player controller, place world behaviors in `scripts/world/`, and avoid broad game-specific systems until the template foundation is stable.
