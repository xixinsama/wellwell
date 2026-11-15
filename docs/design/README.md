Mockups and reference images for the exploration / map system design.

Design illustrations:

- `fog-attention-mockup.png` — fog model B: sealed pockets, authored dark
  zones, and screen-by-screen reveal in multi-chunk rooms. (The pulse/beacon
  part of this mockup was dropped by decision.)
- `maps-v2-mockup.png` — planned precise map (unexplored rooms are black
  silhouettes) and grid map (room brightness = exploration ratio). Not built yet.
- `crumble-mockup.png` — the two crumbling platform types and their timing.

Gameplay captures of the implemented test world:

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

Gameplay captures of the water hall (`water_hall`, the test world start room):

- `water-hall.png` — the two pools just after the sluice gate opens: the high
  tank drains over the spill lip into the low basin, the hero waits on the
  starting ledge, and the mist is lit warm by the harbor lamp and cool by the
  basin light.
- `water-hall-splash.png` — the hero entering the tank: the crown of droplets,
  the ring ripples and the locally raised surface.
- `water-hall-float.png` — the hero floating at the surface after the splash,
  with the gas pushed aside around the body.
- `water-hall-wake.png` — the hero running off the ledge: the gas wake behind
  the body, the three gas layers and the splash.
- `gas-lab.png` — the gas lab: three wall vents (yellow light gas rises, cyan
  neutral gas drifts, red heavy gas sinks) and three platform rows for the hero.
- `gas-lab-walk.png` — the hero walking along the gas lab floor, pushing a
  visible wake through the plumes.

See `docs/fog-zones-and-crumble.md` for the exploration rules and
`docs/water-and-mist.md` for the water and mist systems.
