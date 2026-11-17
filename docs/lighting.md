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
| 9 | `LightGlow`: additive warm light |
| 9 | `LightBloom`: additive dithered halo around bright cores |
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
per end cap, however many tiles long it is (a 6 tile wall is 4 occluders). A light
is only blocked when `casts_shadows` is on, and the occluders are room-local, so a
room placed away from chunk `(0, 0)` keeps its shadows on the room.

`shadow_bounce` softens the result: the shade pass reads the brightest light
within `bounce_radius` and lets a share of it bleed into the shadow. A cast
shadow is therefore dark deep inside and lighter towards its silhouette, where the
lit surface next to it reflects.

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
over a pool cut by a wall, a lamp that ignores walls, six fireflies of four
glowing pixels each, and grid water in the pool. Open
`scenes/levels/test/light_lab_runner.tscn` to walk around in it: the runner binds
the light field, the fog and the water to the room in code.

## Consumers

| System | Reaction |
| :--- | :--- |
| `LightShade` | black with `alpha = 1 - (ambient + light)`, a plain brightness multiply (`dither_strength` 0 by default) |
| `LightGlow` | additive `glow_color * light * glow_gain` |
| `LightBloom` | gathers the map at `bloom_radius`, keeps only light above `bloom_threshold`, quantises with a 4x4 ordered dither |
| `FogOfWar` | `wobble += light * light_push_px`: the shadow recedes where it is lit, the mask itself never changes |
| `TerrainHighlight` | rim alpha `*= clamp(light + light_floor, 0, 1)`, so unlit walls keep a faint outline |
| `WaterField` / `WaterGrid` | the body mirrors the light under its surface (`water_reflection`), plus a pixel sparkle |
| `Atmosphere` | the mist takes `max(authored lights, map * map_weight)`: it keeps the wide soft falloff it had and gains the lantern shape and the shadows |

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
| `bloom_strength` / `bloom_radius` / `bloom_threshold` / `bloom_levels` | 0.55 / 7 / 0.45 / 5 | the halo pass; `bloom_strength` 0 turns it off |
| `dither_strength` | 0 | halftone on the shade; 0 is a plain multiply |
| `shadow_softness` / `shadows` | 2 / on | terrain shadows |
| `shadow_bounce` / `bounce_radius` | 0.45 / 10 | light bleeding into the shadow |
| `rim_jitter` | 0.045 | how far the rim of a light wobbles, as a share of its radius |
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
