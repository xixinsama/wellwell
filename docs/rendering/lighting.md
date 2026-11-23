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
| -1 | backdrop plate |
| 0 | terrain, entities, water |
| 1 | terrain outline, water surface |
| 3 | water splash / crumble debris |
| 5 | gas (the mist is shaded by the pass below, it is not drawn on top of the light) |
| 8 | `LightShade`: multiplies the room down to `ambient + light` |
| 9 | `LightGlow`: additive warm light, `ScreenBloom`: additive screen-space bloom, dust |
| 10 | backdrop tile shadow, player, fog |

The full stack, with every layer and who owns it, is in [art-layers.md](art-layers.md);
this table only covers the light-related part of it.

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

`NormalField` (`game/world/normal_field.gd`) clones the layer into a
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

`normal_tileset` lets the field build that buffer from the room's own
`SolidTiles` instead, which is how the generated atlas lights rooms nobody
re-authored; the next section covers it, including why the shipped scene still
runs the derived mode.

### The generated atlas: authored normals in every room, with no re-authoring

`assets/images/primordial_tileset_normal.png` (32x72, one 8x8 normal per tile) and
`resources/tilesets/primordial_tileset_normal.tres` are baked from the albedo atlas
by `tools/bake_tileset_normals.gd`. The normal TileSet mirrors the albedo
tileset cell for cell (same coordinates, same alternatives in the same order, same
flip/transpose flags), because `NormalField` clones a room layer by copying raw
`tile_map_data`: cells and alternative ids are never remapped.

`NormalField.normal_tileset` (`world_root.tscn`) points at it and
`source_layer_names (default ["BackTiles", "SolidTiles"]) says which terrain
layers to mirror and in which order. Both are listed: the background tiles carry
their own normal map (they are half of what a room shows) and are cloned first,
while the solid tiles are the walls and are cloned after them, so a wall wins
wherever both paint the same cell. That is how a room that never authored normals
gets them from the tiles it already has; a room that does carry a `NormalTiles`
layer keeps priority.

Re-bake after adding or repainting tiles. The tool bakes every tile of the PNG, so
a new tile (like the spike added at `0:8`) needs no script change, and it only
rewrites the PNG when the result actually changed:

```
godot --headless --path . -s res://tools/bake_tileset_normals.gd
```

The height model (luminance as height, a one-pixel bevel from the alpha
silhouette, a periodic height field so tiles tile with themselves, one 3x3
smoothing pass, central-difference gradient) is documented at the top of the tool,
together with the one thing this atlas cannot do: `TileData` has no
`texture_region` in Godot 4.7, so an alternative tile cannot point at its own slot
of the sheet and the renderer's flip mirrors the normal instead of negating its
x/y. Alternatives therefore read correctly in position and shading depth but with
a mirrored tilt sign.

Authored vs derived, measured on `light_lab` and `water_hall` (322x182 capture,
every animated system frozen, byte-identical between two runs of the same mode,
noise floor 0 pixels):

| | derived (1) | authored (2) |
| :--- | :--- | :--- |
| pixels changed | 4.6% / 6.8% | 0.5% / 0.2% |
| of those, on a pixel that has a normal | 19% / 8% | 100% / 100% |
| peak change | 28/255 / 20/255 | 17/255 / 7/255 |
| mean luminance shift | -0.08% / -0.03% | -0.005% / -0.006% |
| busiest band, columns over 1/255 | 35/320 and 31/320 | 2/320 and 0/320 |

The authored normals are the *correct* ones (every change lands on a surface;
derived also "relieves" the water, the gas, the fog and open air) and they are
continuous across tile seams: the baked buffer's normal step across a seam between
two identical tiles is 0.079 (light lab) and 0.137 (water hall) against 0.062 /
0.097 inside a tile, so there is no per-tile grid.

They are also much subtler. `relief_strength` masks the relief by
`smoothstep(0.02, 0.35, light)` and clamps `light * (1 + relief)` to 1, so in a
room whose light map is mostly black or saturated only a narrow band of pixels can
move at all: with the current `relief_strength` (0.35) the authored path shifts
0.5% of the screen and, in its busiest band, moves columns by less than one 8-bit
level (2 of 320 columns over 1/255, against 35 for derived). Switching
`relief_normal_mode` to 2 today would read as "relief off", so `world_root.tscn`
keeps the default `1`; the atlas and the install path are in place, and enabling
authored mode is that one property plus, if the owner wants the same amount of
relief, a much higher `relief_strength` (the derived normals reach roughly
edge-on 60-75 degree tilts on the same art edges, the baked ones 20-45).

`tests/world/test_tileset_normals.gd` covers the atlas, the mirror and the install
path, including a sweep that binds every baked room.

### Cost

Both modes only run in the shade and glow fragments: derived normals add eight
screen taps, authored normals one texture fetch, and both add four light-map taps
for the gradient. On the light lab at 322x182 the whole world viewport measures
0.16-0.19 ms of GPU time, with no measurable difference between flat and derived
modes (the measurements are within run-to-run noise); the biggest measured wall
difference for authored normals was +0.10 ms per frame, well under the 0.4 ms
budget. The one-shot authored buffer costs nothing after its first frame.

## Authored lights

`RoomLight` (`game/world/room_light.gd`) is the light source to place:

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

`scenes/levels/test_world/light_lab.tscn`, built by
`tools/build_light_lab.gd`:

```
godot --headless --path . -s res://tools/build_light_lab.gd
```

It has a swinging lamp over a slab (its shadow sweeps the floor), a second lamp
over a pool behind a **glass** wall (the light passes through), a lamp that
ignores walls entirely, six fireflies of four glowing pixels each, and grid water
in the pool. The runner also builds the terrain outline, so the 1 px rim is lit
only where the light reaches. Open `scenes/levels/test_world/runners/light_lab_runner.tscn` to
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

## 光晕里的"玻璃球"：成因、修法、以及保留的那一个

前几轮给光照加法线浮雕时，lab 里出现了一个意外效果：光圈内部看起来像有一个立体的、
会折射的玻璃球，球的一半亮一半暗。

**成因**：浮雕用的光方向是"光照图的梯度"。在一个灯的光圈内部，梯度处处指向灯心，
也就是**径向**的。而烘焙法线图给每个瓦片都描了一圈倒角（silhouette bevel），
这些倒角的法线又都朝瓦片外侧——两者一乘，整个光圈里就出现了一圈圈沿径向排布的明暗，
读起来就是穹顶/玻璃球。当时为了让手绘法线"看得出来"把 `authored_relief_gain` 抬到了
2.6，等于把这个图案又放大了近三倍。

**修法**（现在就绪）：

1. light_overlay.gdshader 在 authored 模式下先做**法线高通**：减去
   `relief_average_px`（默认 4 px）邻域内的平均法线，只保留"这块面相对周围凸起/凹陷"的部分。
   一面平墙（哪怕它整块是斜的）不再被当成穹顶来着色；瓦片边缘、倒角、缺口仍然有立体感。
2. `authored_relief_gain` 从 2.6 降到 **1.4**，浮雕回归正常强度。

**保留的那一个**：`RoomLight` 新增 `lens_radius` / `lens_strength`，
`LightField` 会把**第一个**带这两个参数的灯送进 shade pass 的单一 lens 槽：

   球面法线 = vec3((p - center)/radius, sqrt(1 - r²))
   明暗     = dot(球面法线.xy, 固定光向 (1.6, -1)) * 0.8 - 边缘暗化
   最终     = lit * (1 + 明暗 * lens_strength)

注意它作用在 `lit` **加上环境光之后**：光圈中心本来就饱和到 1，早一步调制会被 clampa 吃掉，
球就看不见了。lab 里已经把 `PoolLamp` 设成 `lens_radius = 58`、`lens_strength = 1.0`，
实测下半球 **−41 / 255**、正下方 **−29 / 255**，而上半球、灯心、边缘都是 0 变化 ——
就是一个只压暗不曝光的玻璃球。想给别的灯也加，改那个灯的这两个数；同一时刻只有一盏生效。
## 法线强度的实测标定（不是拍脑袋）

### 用一个"已知物体"量

往 `LightField.set_normal_field()` 直接塞一张**半球法线图**（球心房间 (160,90)、半径 70，
其余全平），然后把 relief 开/关两张图逐点对比。结论很重要：

- 球面法线在**大范围内平滑变化**，而浮雕现在先做 6 px 邻域的高通 —— 平滑的大尺度变化会被当成
  "整体倾斜"减掉，所以**一个光滑的球几乎不会被浮雕**（实测各方向 ±0.4~2.5/255）。
- 这说明高通尺度是"瓦片倒角"级别的：8 px 的瓦片、1–2 px 的倒角刚好保留，几十像素的弧度被抹掉。
  背景瓦片/实心瓦片正是前者，所以这个尺度是对的。

### 参数扫描（真实 lab 房间，relief 开 vs 关，逐像素）

| `relief_average_px` | `authored_relief_gain` | 受影响像素 | 平均 |Δ| | 有符号均值 |
| --- | --- | --- | --- | --- |
| 2 | 1.4 | 42.8% | 3.7/255 | −0.13 |
| 4 | 1.4 | 56.9% | 5.2/255 | −0.37 |
| 8 | 1.4 | 59.4% | 6.4/255 | −0.30 |
| 4 | 2.2 | 64.6% | 7.4/255 | −0.09 |
| **6** | **2.0** | **68.2%** | **8.3/255** | **+0.08** |
| 10 | 2.0 | 67.8% | 9.7/255 | −0.04 |

有符号均值接近 0，说明浮雕是**方向性**的（亮了也暗了），不是整体提亮。峰值那一列被 lab 里
`PoolLamp` 的玻璃球（下面一节）污染了，不作为依据。

**定下来的默认值**：`relief_average_px = 6`、`authored_relief_gain = 2.0` —— 扫描里受影响面积最大、
平均强度适中、有符号均值最接近 0 的一组。想要更"重"的浮雕就往上调 `authored_relief_gain`；
调到 10/2.2 以上开始出现成片的提亮，会盖掉暗部。
