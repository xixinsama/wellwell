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
- **Zone fades**: a dark zone never switches on or off in one frame. Entering
  dissolves it with a per-cell wave that travels from the hero outwards, leaving
  fades back in as the darkness that creeps back in from the zone border. The
  wave is driven by `zone_reveal_seconds` / `zone_reveal_stagger` and
  `zone_restore_seconds` / `zone_restore_stagger` on `FogOfWar` (0.9 + 0.02 and
  0.8 + 0.02 by default, so a 5-cell radius takes ~1 s). The fade is written into
  the mask, so the tendrils keep eating into it while it moves.
- **restore_on_exit**: the zone goes black again when the player is completely
  outside. Explored cells are **not** removed, so the map keeps showing the
  area. This is the "attention returns to the main path" effect.
- **focus_room**: the "dark room focus". While the hero is completely inside, the
  rest of the room fades to dark and the authored zone stays lit natively. The
  spotlight is a **shader term** (see below), so the lit bubble is centred on the
  hero body and follows it every frame instead of sitting where the focus
  started; the darkness ramps in over `focus_falloff_px` (34 px) and the bubble
  starts wide and closes onto the hero while `focus_seconds` runs. Leaving
  (including stepping onto the boundary) releases the focus and restores the
  normal reveal (combine with `restore_on_exit` to also re-darken the zone).
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
| alpha | fog opacity of the cell: 1 = fog, 0 = revealed, in between while it evaporates or while an authored zone fades |
| red | reveal flash, drawn as a 1 px outline inside the cell for a moment |
| green | signed distance to the border, encoded around 0.5 (the reach is `MASK_DISTANCE_PIXELS`, 32 px) |

The distance is a two-pass 3-4 chamfer transform over the cell grid, so the
shader can sample it bilinearly between cell centres and place the cut on any
pixel instead of on a cell edge. The opacity is interpolated the same way.

**The border's depth is a range, not a sum.** Two numbers place it; everything
else only decides where inside that range the edge sits:

    offset = clamp(edge_center_px + shape + breath + surge,
                   edge_center_px - tendril_pixels,
                   edge_center_px + tendril_pixels)

`edge_center_px` is where the edge sits on average (negative = pushed *into* the
fog, which reveals more of the room and makes the picture brighter) and
`tendril_pixels` is half the swing. The shipped `-2 / 4` therefore runs the edge
from **-6 px (thinnest) to +2 px (thickest)**; measured on `test_fog_start` over ten
frames the border's offset from the cell edge is min -7, max +1, mean -2.2. That
replaced a sum of five one-signed terms that could only ever grow the fog: the
depth was impossible to reason about and there was no way to ask for "a bit
brighter".

* **shape** — domain-warped fbm (the lobes) plus the fine grain, `lobe_depth` of the
  swing (0.75).
* **breath** — the slow inhale: a sine whose phase is offset by a low-frequency
  field, so one wall breathes a beat behind another instead of the room pulsing as
  one block. `breath_pixels` 1.2, one breath every ~6 s (`breath_speed` 0.16).
* **surge** — the swell that *travels along* the border (two octaves of value noise
  translated over time), which is what turns a pulse into movement: 15 px
  wavelength, 1.8 px deep, `surge_speed` 0.5. The second octave exists because a
  single 15 px lobe leaves long flat stretches where the edge sits still and the
  breathing reads as a stutter.
* **pixel grain** — a 4×4 ordered dither that only applies where the band is in
  flight, so the last pixels break into hard 1 px chunks while the fog interior
  stays clean.

The two temporal terms are signed (they thin and thicken); what makes the breathing
visible is that they sweep *through* the range.

**The inward half is guarded by thickness.** A retreat may not cut *through* a thin
strip of fog, or a ring of thin bands comes apart into separate patches: measured on
`test_fog_start`, the number of large fog blobs went from 2 to 9 when the range moved
from `-2..+2` to `-6..+2` without a guard. The shader takes the gradient of the
distance field (two extra cell samples), probes the field at 2x and 3x the retreat
along it, and scales the retreat away where the fog would not survive it. A thick
mass retreats normally; a 12 px band keeps its shape. In the loop world the fog is
one 57k px mass, so the retreat applies at its border and the room stays a single
blob (measured: 1 blob, 99.3 % coverage).

Measured cost of the range on `test_fog_start`: fogged area 29.9 % -> 15.2 %, mean
opacity 0.252 -> 0.151 (the picture is materially brighter), while the breathing kept
a median 4 px / p90 6 px of contour travel over 4 s.

The per-cell opacity is read **bilinearly** and then sharpened
(`smoothstep(0.30, 0.70, body)`): the mask stores one value per cell, so reading it
per pixel with `filter_nearest` painted every fading cell as a hard 8 px square and
made a cell that was still evaporating next to cleared ones look like a floating
block with a visible edge. A cell that is fogged (or fading) keeps its own opacity,
but only *inside the band*; the revealed side of the band is full strength, which is
the fringe itself.

Measured on `test_fog_start` with `scripts/tools/fog_diagnostic.gd` (`--room
test_fog_start`), before and after this change:

| Metric | Before | After |
| :--- | :--- | :--- |
| fogged area of the room | 19.9 % | 25.8 % (the fringe) |
| detached fog blobs > 12 px | 2..7 | 2..3 |
| hard per-cell plateaus (share of a fading cell sitting on one alpha) | 0.68 | 0.59 |
| recess around the hero, north / south / west / east | — (light only, so floor only) | 6.0 / 7.8 / 5.9 / 6.4 px, the west side at light = 0.000 |

The mask is only rewritten when the revealed set changes, while a reveal wave is
evaporating, or while an authored zone fade is in flight. Everything else is
animated by the shader from `TIME`, so a settled room uploads nothing.

### The focus spotlight lives in the shader

`focus_room` darkens the rest of the room, and it used to be painted into the
mask — one `fill_rect` per cell of the whole room, every frame, which is why it
could not follow the hero and had no gradient worth the name. It is now four
uniforms (`focus_center_px`, `focus_rect_px`, `focus_strength`, `focus_alpha`,
plus `focus_radius_px` / `focus_falloff_px` on `FogOfWar`) and one `focus_at()`
function in `fog_mask.gdshader`:

    lit distance = min(distance outside the authored zone rect,
                       distance from the hero body - the bubble radius)
    alpha        = smoothstep(0, falloff, lit distance) * strength * focus_alpha

The zone itself is therefore lit for free, the darkness ramps in over the falloff
so there is no rectangular seam, and the bubble closes onto the hero as
`focus_seconds` runs. Cost: no mask repaint at all. A 320×180 lab room measured
inside the pocket 204, and 196 / 138 / 60 / 18 / 16 at 10 / 20 / 30 / 40 px
outside it (falloff 34 px, `focus_alpha` 0.92).

### `FogOfWar` parameters

| Property | Default | Meaning |
| :--- | :--- | :--- |
| `edge_center_px` | -2 | where the border sits on average (- = into the fog, brighter picture) |
| `tendril_pixels` | 4 | half the swing; with the centre above the edge runs -6..+2 px |
| `edge_softness` | 1.6 | anti-alias width of the cut; 0 gives a hard pixel edge |
| `edge_noise_scale` | 13 | size of the coarse lobes; smaller means busier |
| `edge_noise_grain` | 3.2 | size of the fine grain layer |
| `edge_noise_speed` | 0.55 | drift speed; 0 freezes the border |
| `edge_noise_warp` | 0.65 | how strongly the lobes are bent, which turns blobs into tongues |
| `breath_pixels` | 1.2 | how far the slow inhale moves the border inside the swing |
| `breath_scale` | 46 | size of the inhale lobes; big values move the whole silhouette |
| `breath_speed` | 0.16 | inhale speed in Hz (~6 s per breath) |
| `surge_pixels` | 1.8 | how far the travelling swell moves the border |
| `surge_scale` | 15 | wavelength of that swell in pixels |
| `surge_speed` | 0.5 | how fast it travels |
| `dither_strength` | 0.6 | blend towards the ordered dither, 0 to 1 |
| `dither_scale` | 1 | size of one dither cell in pixels |
| `hero_push_px` | 5 | how far the mist leans away from the hero, on every side |
| `hero_push_radius_px` | 44 | radius over which that recess fades out |
| `light_push_px` | 3 | extra recess where the lantern lights a surface |
| `zone_reveal_seconds` | 0.9 | how long a dark zone takes to dissolve after the hero enters |
| `zone_reveal_stagger` | 0.02 | extra delay per cell of distance from the hero |
| `zone_restore_seconds` | 0.8 | how long a `restore_on_exit` zone takes to close again |
| `zone_restore_stagger` | 0.02 | extra delay per cell, counted inwards from the border |
| `focus_radius_px` | 34 | lit bubble around the hero while a focus zone is active |
| `focus_falloff_px` | 34 | width of the lit → dark ramp of the focus spotlight |

Set `tendril_pixels` and `dither_strength` to 0 to get the old cell-aligned border
back, and `hero_push_px` / `light_push_px` to 0 to take the recess out entirely.
The shader's `debug_view` uniform (1 = distance sign, 2 = value / band / opacity,
3 = band / value / recess share) is what the captures in the table above were taken
with; `fog_diagnostic.gd --uniform=debug_view=3` reads the recess field directly.

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
