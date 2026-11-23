# World Editor, Fog, And Camera Design

## Goal

Complete the next platformer-template capability slice without editing authored
room scenes or tile placement: make World editing interactive, make fog room-local
with a usable per-frame mask, and support free and room-locked cameras.

## Decisions

- `VisionBlockTiles` is the only visibility blocker. Physical `SolidTiles` and
  `GlassTiles` do not block sight unless the same cell is also authored in the
  dedicated vision layer.
- Visibility is cardinal flood-fill from the player's cell, bounded by the active
  room. Blocking cells are visible, but propagation stops at them. The default
  propagation distance remains unlimited; a finite radius can be added later.
- `FogOfWar` exposes the current `ImageTexture`, mask origin, and mask size. The
  mask is rebuilt when visibility changes and updated every frame when a texture
  already exists, so post-processing can consume a stable texture reference.
- Free camera preserves current player-follow behavior. Room-locked camera follows
  the player only inside multi-chunk room bounds; a one-chunk room is centered and
  does not move.
- World editor selection and hover are state on the center canvas. Room movement
  remains integer chunk snapping and never edits source scenes.

## Boundaries

Runtime room changes configure both fog and camera from `WorldData`. The editor
reports preview/resource errors through its existing status channel. Authored
scenes, tile maps, `docs/todo.md`, and generated room placement data are not
rewritten by this feature.

## Verification

Automated tests cover flood-fill blocker semantics, mask metadata, camera modes and
room bounds, and canvas selection/cancel behavior. The user performs the visual
Godot-editor check for zoom, focus, grid guides, terrain preview, and camera feel.
