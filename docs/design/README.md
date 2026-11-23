Mockups and reference images for the exploration / map system design.

Design illustrations:

- `fog-attention-mockup.png` — fog model B: sealed pockets, authored dark
  zones, and screen-by-screen reveal in multi-chunk rooms. (The pulse/beacon
  part of this mockup was dropped by decision.)
- `maps-v2-mockup.png` — the original design sketch for the two map styles.
- `crumble-mockup.png` — the two crumbling platform types and their timing.

Gameplay captures:

- `test-world-room.png` — test room with the three-layer template: glass box,
  light zone inside a sealed box, sealed dark pocket, floor dark zone, crumble
  bridge and ledge, and the door-closed chamber on the floor.
- `focus-zone.png` — dark-room focus: the player stands fully inside the
  authored dark zone, the zone stays lit and the rest of the room closes in
  towards it.
- `zone-partial.png` — the hero straddling the zone boundary: the whole zone
  lights so the body is never cut in half, and focus is not applied yet.
- `door-open.png` — the door opened, exposing the chamber and its marker.
- `test-world-crumble.png` — the one-way crumble bridge after the player broke
  two cells.
- `test-world-wide.png` — two-screen room at the divider; only the camera view
  is lit, the far screen stays black.
- `map-precise.png` — the generated precise map at the fitted zoom (the player
  marker grows with the zoom here).
- `map-precise-zoomed-out.png` — the same map zoomed out: the player marker
  keeps its minimum size so it stays visible.
- `map-grid.png` — the grid map: room brightness follows the exploration ratio
  (100% / 80% / 46% / 0% visible side by side).
- `loop-entry.png` / `loop-split.png` / `loop-gallery.png` / `loop-relay.png` —
  the four rooms of the Loop Cistern world, captured with the debug overlay on.
- `minimap-grid.png` / `minimap-precise.png` — the corner minimap in both
  styles.

See `docs/systems/fog-zones-and-crumble.md` for the exploration rules, `docs/systems/map.md` for
the map and `docs/systems/loop-world.md` for the loop world. The fluid showcase lives in
`examples/fluid_demos/` (runnable scenes, no images kept).
