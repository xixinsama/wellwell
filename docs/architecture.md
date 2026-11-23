# Architecture: One Template, Many Mechanics, Many Worlds

This repository keeps a reusable 2D platformer template, optional mechanics,
authored worlds, and the editor tooling in one project while preventing them
from depending on each other.

## Layers

- **Template core** — `addons/platformer_kit/` owns character motion, sensors,
  platform components, room streaming, save data, camera, and world data
  contracts. It must not preload project worlds, puzzle code, examples, or
  game-specific content.
- **Optional mechanics** — abilities, combat, ladder motion, and the sliding
  puzzle live outside the core. Compose them per player or per room instead of
  adding global state to Platformer Kit.
- **Worlds** — `resources/worlds/*.tres` contain `WorldData` only. The menu
  reads `resources/worlds/world_catalog.tres`; room resources own their own
  geometry and source fingerprint.
- **Authoring** — `addons/world_editor/` edits worlds and rooms, bakes
  runtime/terrain scenes, and reports diagnostics to the editor Output panel.
- **Game composition** — `game/`, `scripts/player/`, and `scenes/` assemble the
  template, mechanics, and current worlds. Game content may depend on the kit;
  the kit never depends on game content.

## Isolation Rules

- A world may only reference room IDs defined in that world. Do not share a
  room ID between two worlds with different content; give the variant its own
  ID and generated resource path.
- A mechanic is enabled by scene composition (nodes, components, resources),
  not by a global flag in the template.
- Mechanics may promote generic fixes back into the template. Examples already
  in this project: shared collision-rectangle merging, ladder contact refresh
  on respawn, and the one-shot rider air jump in the movement context.
- World-specific tuning and art live with the world or game content, not in
  Platformer Kit.
- New collision areas should merge adjacent cells. Ladder zones and puzzle void
  bodies use the shared `CellRectMerger`; do not emit one Area or shape per
  painted cell.

## Branch and Worktree Policy

- Keep one active integration branch and one main worktree for day-to-day work.
- Use short-lived branches for mechanics, worlds, and art experiments. Archive
  finished or abandoned visual experiments instead of keeping duplicate
  worktrees open.
- Merge mechanics through their tests and the world catalog; do not copy an
  entire project directory to start a variant.
- When a mechanic exposes a template weakness, fix the template and add a
  regression test there before depending on the fix from the mechanic.
