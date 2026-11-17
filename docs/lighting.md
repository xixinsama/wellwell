# Lighting

`LightField` (`scenes/runtime/world_root.tscn`, a room extension like the fog)
owns the room's light and hands the same map to every system that needs it.

## Why a light map instead of per-shader lights

Godot's 2D lights cannot be sampled by a custom shader, and computing a falloff
again in every shader would mean five copies of the same math plus no shadows.
So the lights are rendered once into a room-sized `SubViewport`:

- black `CanvasModulate`, additive `PointLight2D` nodes and `LightOccluder2D`
  from the terrain: the engine gives falloff *and* real shadows on the GPU;
- a white, lit `ColorRect` under the lights turns that accumulation into a
  texture;
- nothing is read back on the CPU (a readback stalls the pipeline), so the map is
  only ever sampled. Every consumer just samples the same texture.

The map is room-local: a light at world `p` sits at `p - room_origin` inside the
viewport, so a consumer can map a room pixel to a texel with `(px + 0.5) / size`.

## Draw order

| z | item |
| :--- | :--- |
| 0 | terrain, water, gas |
| 1 | terrain outline |
| 8 | `LightShade`: multiplies the room down to `ambient + light` |
| 9 | `LightGlow`: additive warm light, `ScreenBloom`: additive screen-space bloom |
| 10 | fog, player |

The fog stays above the light on purpose: light may push the tendrils of the fog
back, but it must never open up an area that is still unexplored. The player
stays above the shade as well, so the hero is always readable.

## The lantern

Two rings on the hero: a `core_radius` (9 px) bright disc and a `halo_radius`
(26 px, 3.25 tiles) soft one, both driven by a procedurally generated radial
`GradientTexture2D` (no image files). The gradient plateaus over the first 42% of
its radius and then falls off with `falloff_power`, which is what makes the two
lights read as a disc plus a halo instead of one smooth blob.

## Shadows

Occluders are built from the `SolidTiles` collision shapes, merged into runs: a
straight wall costs one occluder for its top edge, one for its bottom edge and one
per end cap, however many tiles long it is (a 6 tile wall is 4 occluders). The
cells painted with `glass_tile_atlas` (atlas `0,3` by default) are skipped: glass
has collision but passes light, exactly like it passes sight in the fog.

Shadows are cast per light by the engine's 2D shadow map, so a shadow reaches as
far as its light does. That is why each light is built with a **reach**: the
lantern is a 9 px core, a 26 px halo and a dim `reach_radius` spill, and every
authored light gets a spill at `AUTHORED_REACH` times its radius. The spill is
what makes the shadow of a wall run across the room instead of stopping a few
pixels behind it, and why most of the space ends up lit.

`shadow_bounce` softens the result: the shade pass reads the brightest light
within `bounce_radius` and lets a share of it bleed into the shadow. A cast
shadow is therefore dark deep inside and lighter towards its silhouette.

## The fuzzy rim

Lights themselves stay clean: the falloff is a round `GradientTexture2D` with no
noise or dither in it. The fuzz is added on the lit side only, in the shade and
glow passes: each pixel takes a few samples at a noise-driven offset and keeps the
brightest, so light grows hair outward by up to `rim_fuzz` pixels and the dark
side never eats inwards. `rim_fuzz_scale` is the hair size (smaller is denser).

## Normals and relief

The light map only knows *how much* light a pixel gets, not which way the surface
faces: every wall and floor is shaded the same regardless of orientation. Relief
adds that direction back without touching the light map:

- **light direction** is the local gradient of the light map itself, a central
  difference over `relief_radius_px` pixels. The map rises towards its sources,
  so its gradient points from the shadow towards the lamp; a surface whose normal
  faces that way catches more light, one that faces away catches less. No Camera2D
  position, light list or second render pass is needed: the direction is already
  in the texture every consumer samples.
- **surface normal** comes from one of two sources, selected by
  `relief_normal_mode`.

### Derived normals (default, zero authoring)

`relief_normal_mode = 1` reads the world as it is just before the shade is drawn
(`hint_screen_texture`) and runs a small sobel on its luminance. The raw
gradient of the screen would mostly read the light falloff itself, which is the
same field the light direction comes from: the two would cancel into a uniform
brightness lift. The shader therefore subtracts the gradient measured
`relief_radius_px` away, keeping only the slopes the art has (brick edges, rims,
pixel detail). Brightness is treated as height, so the flank of a raised pixel
that faces the lamp brightens and the opposite flank darkens. Every existing
room gets this immediately; there is nothing to author.

### Authored normals (preferred when present)

Add a `TileMapLayer` named `NormalTiles` under `RoomContent/Terrain` (the baker
keeps it, and the runtime terrain puts it under `Terrain`) whose tiles are plain
RGB vectors: `r = x`, `g = y`, `b = z`, flat = `(128, 128, 255)`. Turn the layer
invisible (the eye icon) so the room does not draw the normals; `NormalField`
warns if it is visible but never mutates the owner's node.

`NormalField` (`scripts/world/normal_field.gd`) clones the layer into a
room-sized `SubViewport` (`tile_set` + `tile_map_data` copied, the authored node
is untouched), clears it to the flat normal and renders **once** per room, then
switches itself to `UPDATE_DISABLED`: a static room pays nothing per frame for
it. Set `relief_normal_mode = 2` to use the buffer; a room without a
`NormalTiles` layer falls back to the derived path instead of losing relief.
The buffer is handed to both overlay materials through
`LightField.set_normal_field()` (the normal-map twin of `set_light_field()`), and
the two field nodes can bind in either order. Removing the `NormalField` node
from `world_root.tscn` is a supported configuration: flat or derived lighting
keeps working.

### Cost

Both modes only run in the shade and glow fragments: derived normals add eight
screen taps, authored normals one texture fetch, and both add four light-map taps
for the gradient. On the light lab at 322x182 the whole world viewport measures
0.16-0.19 ms of GPU time, with no measurable difference between flat and derived
modes (the measurements are within run-to-run noise); the biggest measured wall
difference for authored normals was +0.10 ms per frame, well under the 0.4 ms
budget. The one-shot authored buffer costs nothing after its first frame.

## Authored lights

`RoomLight` (`scripts/world/room_light.gd`) is the light source to place:

| Property | Meaning |
| :--- | :--- |
| `radius` / `energy` / `color` | size, brightness and tint |
| `swing_pixels` / `swing_speed` / `swing_axis` | pendulum motion (the swinging lamp) |
| `wander_pixels` / `wander_speed` | drifting, for fireflies |
| `flicker` / `flicker_speed` | energy wobble |
| `casts_shadows` | turn off for a light that ignores walls (fireflies, a halo) |

The older `FogLight` nodes are still collected, because the mist uses their wide
soft falloff.

Every light rims are procedural (`_radial_texture`): the circle is pushed in and
out by `rim_jitter` (4.5% of the radius by default) so no light is a perfect
circle.

## The demo room

`scenes/levels/test/light_lab.tscn`, built by
`tools/build_light_lab.gd`:

```
godot --headless --path . -s res://tools/build_light_lab.gd
```

It has a swinging lamp over a slab (its shadow sweeps the floor), a second lamp
over a pool behind a **glass** wall (the light passes through), a lamp that
ignores walls entirely, six fireflies of four glowing pixels each, and grid water
in the pool. The runner also builds the terrain outline, so the 1 px rim is lit
only where the light reaches. Open `scenes/levels/test/light_lab_runner.tscn` to
walk around in it: the runner binds the light field, the fog, the water and the
outline to the room in code.

Measured on that room (322x182 viewport, 28 occluders, 3 lantern lights, two
2-light lamps, a glow lamp, six fireflies, grid water, fog and the outline):
**1.25 ms per frame** with the whole stack, 1.19 ms with the light overlays
hidden, so the lighting costs well under a millisecond at design resolution.

## Consumers

| System | Reaction |
| :--- | :--- |
| `LightShade` | black with `alpha = 1 - (ambient + light)`, a plain brightness multiply (`dither_strength` 0 by default) |
| `LightGlow` | additive `glow_color * light * glow_gain` |
| `ScreenBloom` | screen-space bloom: threshold the bright pixels of the world viewport, blur horizontally then vertically, add back (see below) |
| `FogOfWar` | `wobble += light * light_push_px`: the shadow recedes where it is lit, the mask itself never changes |
| `TerrainHighlight` | rim alpha `*= clamp(light + light_floor, 0, 1)`, a single bright pixel (`rim_width` 1) |
| `WaterField` / `WaterGrid` | a *surface* reflection: the crest pixel takes the light and a couple of hard dithered rows under it, no glow filling the body |
| `Atmosphere` | the mist takes `max(authored lights, map * map_weight)`: it keeps the wide soft falloff it had and gains the lantern shape and the shadows |

## Bloom

`ScreenBloom` is the usual screen-space chain, not a halo of the light map:

1. **bright** — read the world viewport texture, keep only pixels above
   `threshold` (with a `knee`), and blur them horizontally in the same pass
   (thresholding each tap is the same as thresholding once, because the blur is
   linear, so the two passes merge into one texture read);
2. **blur** — the vertical half of the same separable gaussian;
3. **composite** — add the result back over the world with an ordered dither, so
   the glow lands on the pixel grid instead of becoming a smooth gradient.

Both buffers run at half resolution (`DOWNSCALE` 2), and the world texture is read
one frame late because a viewport cannot sample itself while it is being drawn.

## Parameters

`LightField`

| Property | Default | Meaning |
| :--- | :--- | :--- |
| `halo_radius` / `core_radius` | 26 / 9 | the two lantern rings in pixels |
| `halo_energy` / `core_energy` | 0.75 / 1.1 | their brightness |
| `falloff_power` | 1.7 | how fast the outer part of a ring fades |
| `light_color` | warm white | lantern tint |
| `ambient` | 0.55 | light that reaches everything, added on top of the map |
| `glow_gain` / `glow_color` | 0.5 | the additive warm pass |
| `threshold` / `knee` / `intensity` (ScreenBloom) | 0.62 / 0.12 / 1 | what blooms and how hard |
| `radius` / `strength` / `levels` (ScreenBloom) | 6 / 0.85 / 6 | blur size, how much is added back, dither steps |
| `dither_strength` | 0 | halftone on the shade; 0 is a plain multiply |
| `shadow_softness` / `shadows` | 2 / on | terrain shadows |
| `glass_tile_atlas` | `0,3` | glass: solid but transparent to light |
| `reach_radius` / `reach_energy` | 170 / 0.35 | the lantern's room-scale spill: long shadows, lit corners |
| `shadow_bounce` / `bounce_radius` | 0.45 / 10 | light bleeding into the shadow |
| `rim_fuzz` / `rim_fuzz_scale` | 2 / 2.2 | outward-only hair on the lit rim, and its size in pixels |
| `relief_normal_mode` | 1 | 0 flat (old look), 1 derived from the screen, 2 authored `NormalTiles` (falls back to 1) |
| `relief_strength` | 0.35 | how hard a facing/away normal lifts/sinks the light; 0 turns relief off |
| `relief_radius_px` | 2 | step of the light-map gradient, and of the derived normal's band-pass |
| `relief_softness` | 0.3 | pushes the effect towards the steep faces instead of every gentle slope |
| `use_authored_lights` | on | collect every `FogLight` in the room |
| `shade_order` / `glow_order` | 8 / 9 | draw order of the two overlays |

`FogOfWar`: `light_push_px` (10) and `light_gain`.
`TerrainHighlight`: `light_floor` (0.55) and `light_gain`.
`WaterField` / `WaterGrid`: `water_reflection` (0.8).

## Verification

`tests/world/test_light_field.gd` covers the room binding, both lantern rings,
the occluder run merging, the hand-off of the map to the fog and the outline, and
room switching / clearing. Measured on `room_03_00` with the default ambient, the
dark part of the room keeps 58% of its brightness and the lit part keeps 100%.

`tests/world/test_normal_field.gd` covers the normal field: binding with and
without an authored `NormalTiles` layer, the clone keeping the authored cells,
atlas and tile set (and the authored node staying untouched), the hand-off and
the uniforms on both overlay materials, the authored -> derived fallback, both
binding orders and room rebinding. On the light lab with the animated systems
frozen, derived normals change 14.3% of the world pixels while keeping the mean
luminance within 0.05%, and authored normals change 2.5% of the pixels (only the
solid tiles carry normals) with the mean within 0.03%; the dark half of the map
does not move at all.
