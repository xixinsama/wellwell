# Fog Zones, Crumble Tiles, Doors, and the Exploration Test World

This slice covers the room fog, its authored zones and attention effects, the
crumbling platforms, doors as sight occluders, and the editable test world.

## Three tile layers

The room template has three TileMapLayers. Every interactive tile lives in the
middle layer; the tile itself decides its behaviour.

| Layer | Role |
| :--- | :--- |
| `BackTiles` | background, no collision |
| `SolidTiles` | playfield: walls, glass, one-way platforms, crumble tiles, ladders |
| `DetailTiles` | front decoration, no collision |

Older rooms may still carry `GlassTiles`, `VisionBlockTiles`, `MarkerTiles`,
`CrumbleTiles` or `CrumbleOneWayTiles`. They are accepted and rendered for
backwards compatibility (the fog still reads the legacy sight layers), but the
template no longer creates them. Re-baking an old source scene drops them, so
move their tiles into `SolidTiles` first.

Tile behaviour comes from the TileSet:

| Tile | Behaviour |
| :--- | :--- |
| atlas `0,3` | glass: solid collision, but sight passes through |
| one-way physics polygon | pass through from below, stand on top |
| atlas `3,0` | crumble solid: blocks every direction and blocks sight |
| atlas `3,4` | crumble one-way: crumbles like a one-way platform |
| atlas `0,7` | ladder: `LadderTileAreaBuilder` turns the painted cells into a ladder area |

The middle layer is the only place the author needs to paint.

## Fog Model B

The room is revealed when the player can see it:

- The reveal region is the current **camera view**, expanded by one cell and
  clipped to the room. A 1x1 room lights up as one screen; a 2x1 room lights up
  screen by screen as the camera moves.
- Visibility is an **eight-direction** flood fill from the player cell. A
  one-cell diagonal crack is see-through on purpose: corners are not sealed by
  the fog, and level design keeps sealed spaces far enough apart that the player
  cannot peek through them. A blocker cell is visible itself but stops
  propagation.
- Revealed cells stay revealed for the rest of the visit and are persisted per
  room (`room:x,y`).

Three things stay black:

1. cells outside the camera view (multi-chunk rooms),
2. sealed pockets the fill cannot reach,
3. authored **dark zones** that have not been revealed yet.

### Blockers

| Tile | Blocks sight | Why |
| :--- | :---: | :--- |
| solid collision in `SolidTiles` | yes | real wall |
| crumble solid (`3,0`) | yes | breaking it opens sight |
| glass (`0,3`) | no | transparent on purpose |
| one-way / crumble one-way | no, unless the setting below is on | platform |
| ladders, decorations, entities | no | |

### One-way platforms occluding sight

Game setting **One-way Platforms Block Sight** (`one_way_occludes_sight`,
default on, Game settings tab). When on, sight does not continue downwards
through a one-way platform cell: standing on top of a platform makes the space
below it a sealed pocket. The platform cell itself stays visible. Sight upwards
and sideways through the platform still works.

## Fog Zones

`scenes/world/fog_zone.tscn` is a `Node2D` placed under `RoomContent/Entities`.
It is a rectangle in cells, positioned in room pixels.

| Property | Meaning |
| :--- | :--- |
| `mode` | `Dark` hides the area; `Light` always lights it |
| `size_cells` | rectangle size, 8 px per cell |
| `zone_id` | stable persistence key; keep it unique inside the room |
| `reveal_on_enter` | Dark only: light the zone when the player enters it |
| `restore_on_exit` | Dark only: re-darken the zone when the player leaves |
| `focus_room` | Dark only: while inside, darken the rest of the room |
| `focus_seconds` | focus fade in/out time (0.35 s default) |
| `focus_alpha` | how dark the rest of the room gets (0.92 default) |

- **Light zone**: lights its cells even when they are sealed behind solid walls.
  The cells are recorded as explored.
- **Zone membership uses the hero body**, not the feet point: the fog tests the
  player's 10x10 body rect (export `hero_body_rect` on `FogOfWar`) against the
  zone rectangle.
  - **Overlap** (the hero is partly inside) lights the dark zone, so the body is
    never cut in half by the fog. Standing between two zones lights both.
  - **Fully inside** is required for `focus_room`; a hero on the boundary is
    treated as between areas, so the outside stays lit.
  - **Fully outside** is required for `restore_on_exit`; while the hero still
    overlaps the zone it stays lit and only goes dark after a complete exit.
- **Dark zone + reveal_on_enter**: lights the zone and persists that it was seen.
- **restore_on_exit**: the zone goes black again when the player is completely
  outside. Explored cells are **not** removed, so the map keeps showing the
  area. This is the "attention returns to the main path" effect.
- **focus_room**: the "dark room focus". While the hero is completely inside,
  the rest of the room fades to dark, closing in towards the player; the zone
  itself stays lit. Light zones dim too, so the focus wins. Leaving (including
  stepping onto the boundary) releases the focus and restores the normal reveal
  (combine with `restore_on_exit` to also re-darken the zone).
- Light wins over dark if the two overlap.
- `revealed` (currently lit) and `seen` (ever lit) are runtime state; the editor
  draws the rectangle with `D`/`L`, plus `R` for restore, `F` for focus and `*`
  when it was seen.

Persistence: zone keys are stored as `room_id:zone_id` in the save module.
Restore zones are remembered as seen but are not forced lit when reloaded.

## Fog rendering: the animated edge

The fog is not drawn cell by cell any more. `FogOfWar` writes a mask texture and
a single `Sprite2D` child (`FogMask`) draws it through
`addons/metroidvania_kit/map/discovery/fog_mask.gdshader`, so the border can be
organic instead of following the 8 px grid and a settled room costs nothing per
frame on the CPU.

The mask holds one texel block per cell, three channels:

| Channel | Contents |
| :--- | :--- |
| alpha | fog opacity of the cell: 1 = fog, 0 = revealed, in between while it evaporates or is dimmed by a focus zone |
| red | reveal flash, drawn as a 1 px outline inside the cell for a moment |
| green | signed distance to the border, encoded around 0.5 (the reach is `MASK_DISTANCE_PIXELS`, 32 px) |

The distance is a two-pass 3-4 chamfer transform over the cell grid, so the
shader can sample it bilinearly between cell centres and place the cut on any
pixel instead of on a cell edge. On top of that the shader adds three noise
layers to the cut:

1. **tendrils** — domain-warped fbm, so tongues of shadow grow out of the border
   and bite into it, drifting slowly,
2. **breathing** — one very low frequency swell that moves the whole silhouette
   in and out, which reads as the shadow inhaling,
3. **pixel grain** — a 4×4 ordered dither that only applies where the cut is in
   flight, so the last pixels break into hard 1 px chunks while the fog interior
   stays clean.

A cell that is fogged, fading or dimmed always keeps exactly its own opacity, so
the reveal wave and the focus spotlight stay truthful; only a fully revealed cell
can be covered by a tongue, and that one is solid at the cut and thins out
towards its tip.

The mask is only rewritten when the revealed set changes, while a reveal wave is
evaporating, or while the focus spotlight fades. Everything else is animated by
the shader from `TIME`, so a settled room uploads nothing.

### Edge parameters (`FogOfWar`)

| Property | Default | Meaning |
| :--- | :--- | :--- |
| `tendril_pixels` | 7 | how far noise may push the border out or in, in pixels; this is the tongue depth |
| `edge_softness` | 1.6 | anti-alias width of the cut; 0 gives a hard pixel edge |
| `edge_noise_scale` | 13 | size of the coarse lobes; smaller means busier |
| `edge_noise_grain` | 3.2 | size of the fine grain layer |
| `edge_noise_speed` | 0.55 | drift speed; 0 freezes the border |
| `edge_noise_warp` | 0.65 | how strongly the lobes are bent, which turns blobs into tongues |
| `breath_pixels` | 3 | how far the whole border swells |
| `breath_scale` | 46 | size of the swell lobes; big values move the whole silhouette |
| `breath_speed` | 0.16 | swell speed |
| `dither_strength` | 0.6 | blend towards the ordered dither, 0 to 1 |
| `dither_scale` | 1 | size of one dither cell in pixels |

Set `tendril_pixels`, `breath_pixels` and `dither_strength` to 0 to get the old
cell-aligned border back.

## Crumble Tiles

Paint the crumble tiles in `SolidTiles`:

| Tile atlas | Behaviour |
| :--- | :--- |
| `3,0` | cracked blue block: solid in every direction, blocks sight |
| `3,4` | cracked plank: one-way, can be passed from below |

`CrumbleRuntime` (a WorldRoot room extension, like `FogOfWar`) drives them:

1. The player is `is_on_floor` and a crumble cell sits under the feet.
2. The cell shakes for 0.25 s.
3. It is erased from `SolidTiles` (visual and collision), a debris sprite falls,
   and the fog refreshes (so the wall no longer blocks sight).
4. After 1.5 s it is written back.

Leaving the room, dying, or binding another room restores every broken cell. The
cracked tiles identify themselves through `crumble_solid_atlas` /
`crumble_one_way_atlas` on the runtime; legacy crumble layers are still driven
if present.

## Doors

`scenes/world/fog_door.tscn` is a 1x2 (configurable) door placed under
`RoomContent/Entities`:

- While closed it is a `StaticBody2D` on the world layer (blocks movement) and a
  fog occluder (blocks sight), so the space behind it stays dark.
- Interact (`E` / pad `X`) within its sensing area toggles it. Opening removes
  both the collision and the sight blocker, so the room behind lights up.
- The node joins the `fog_occluder` group; the fog reads
  `is_occluding()`/`get_world_rect()`. Any future occluder only needs those two
  methods and the group.
- Door state is runtime-only; it resets when the room reloads.
- `size_cells`, `blocks_sight`, `interactive` and `door_id` are exported.

## Sliding puzzle pieces

Sliding blocks participate in the fog with no extra wiring:

- `PuzzlePiece` / `PuzzleTilePiece` join the `fog_occluder` group at runtime.
- Their `wall_shape` cells block sight; `one_way_shape` cells follow the one-way
  platform setting; void pieces do not occlude at all.
- The cells are converted from the piece's current global position, and the
  piece calls `request_refresh` on the fog whenever its position changes, so a
  block opens or seals a pocket as it slides (including during the board tween).
- Pieces sitting in unexplored cells are covered by the fog like any other room
  content; because exploration is persistent, a slider that uncovers a new
  pocket makes it light up, while already explored cells stay known.

## Test World

`resources/worlds/test_world.tres` (catalog name **Exploration Test World**) has
two editable source rooms:

- `scenes/levels/test/test_fog_start.tscn`
  - glass box (lit through glass) and a sealed solid box with a light zone
  - sealed solid pocket (stays black, no door)
  - floor-level dark zone with `focus_room` + `restore_on_exit`
  - one-way crumble bridge and a solid crumble ledge
  - small chamber closed by a door, with a `?` marker inside
  - ladder, spawn `start`, entrance `to_east`
- `scenes/levels/test/test_fog_wide.tscn`
  - 2x1 chunks, screen divider with a low passage
  - glass box, crumble bridge/ledge, ladder
  - right-side dark zone with `restore_on_exit` and a light zone
  - spawn `from_west`, entrance `to_west`

To iterate:

1. Open a source room and paint the middle layer.
2. Drop `scenes/world/fog_zone.tscn` or `scenes/world/fog_door.tscn` under
   `RoomContent/Entities`.
3. Save, then bake the room (World main screen → Bake / Bake Stale).
4. Run `scenes/levels/test/test_world_runner.tscn` — it starts the test world
   directly in the 320x180 game viewport without the main menu (session-only
   persistence). The world is also selectable from the normal world menu.

## Tests

- `tests/world/test_fog_visibility.gd` — sight blockers (solid, glass, one-way,
  crumble), diagonal cracks, the one-way occlusion setting, sealed pockets vs
  light zones, dark zone reveal/restore/focus, doors, mask and saved
  exploration.
- `tests/world/test_crumble_runtime.gd` — shake/break/respawn timing, both
  crumble tiles, non-crumble tiles, room-switch restore, clear-room restore.
- `tests/world/test_fog_door.gd` — occlusion flag, world rect, collision toggle.

Run:

```text
godot --headless --path . -s res://tests/run_runtime_suite.gd
```
