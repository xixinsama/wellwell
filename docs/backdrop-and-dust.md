# 背景层阴影与前景灰尘

这两个都是纯视觉层，各自一个节点、各自一个开关，挂在 `scenes/runtime/world_root.tscn` 上，
通过 `register_room_extension` 跟房间绑定（和 `LightField` / `NormalField` 一样）。
删掉节点就是关掉功能，不需要改任何房间场景。

## 背景瓦片投影（`BackdropShadow`）

### 为什么要有这一层

背景板（`BackdropField` 铺的 `backdrop_well.png` 320×180 plate）位于 z −1，
背景瓦片层 `BackTiles` 位于 z 0。两层之间原来什么都没有，所以背景板看起来就是
"另一张图片"，而不是"瓦片背后的空间"。给瓦片加一层投影之后，背景板立刻变成有距离的背墙。

### 怎么做

1. 绑定房间时把 `Terrain/BackTiles` **克隆**一份（`tile_set` + `tile_map_data` 拷贝，
   原节点不动）塞进一个房间大小的 `SubViewport`，用
   `scripts/shaders/backdrop_shadow_mask.gdshader` 把它画成**白色剪影**（只有 alpha 有意义）。
   渲染一次（`UPDATE_ONCE`），两帧后显式切到 `UPDATE_DISABLED`，所以静态房间每帧 0 开销。
2. 在这层剪影上画一个整房间的 quad（`Sprite2D`，父节点是房间的 `Background` 容器），
   `z_index = 0`：它排在 plate（−1）之后、`BackTiles`（0）之前，
   所以阴影只落在背景板上、被瓦片自己盖住 —— 读起来就是瓦片投影到了背墙上。
3. `scripts/shaders/backdrop_shadow.gdshader`（`render_mode blend_mul`）：
   采样剪影时按 `offset_px` 偏移、用 16 个黄金角采样点做高斯模糊，然后
   `mix(1.0, shadow_tint, coverage * strength)` 乘到背景板上。乘算保证它只会压暗、永远不会提亮。

### 投影方向

每帧取**离主角最近的光源**（`room_light` / `fog_light` 组，没有的话就用主角提灯），
把剪影往光源的**反方向**推：

    offset = -normalize(anchor - light) * min(|anchor - light| * follow_ratio, max_offset_px)

`follow_ratio` 默认 0.5（小于 1，所以它只是"偏一点"，不会变成第二个瓦片层），
`max_offset_px` 默认 6 px 兜底，免得远处的灯把整块阴影甩出画面。

| 参数 | 默认 | 作用 |
| :--- | :--- | :--- |
| `strength` | 0.55 | 阴影最大压暗程度 |
| `blur_px` | 2.5 | 软边半径（像素） |
| `max_offset_px` | 6 | 位移上限 |
| `follow_ratio` | 0.5 | 位移 = 灯距离 × 这个比例（< 1） |
| `shadow_tint` | (0.52, 0.6, 0.78) | 阴影最深处的乘算颜色（偏冷，避免发灰） |
| `layer_path` | `Terrain/BackTiles` | 被投影的背景瓦片层 |

实测（隔离场景，板 155 灰、瓦片块 x16…96、灯在右边 x=300）：
阴影在 x≈6 处开始、x≈94 结束，也就是**往左偏了约 6–10 px**，平台区压暗 −34.1
（155.6 → 121.5，约 22%），软边跨 4–8 px；改参数后整帧只有 10.6% 的像素变化。

## 前景灰尘（`DustField`）

- **单像素**：不是贴图、不是粒子节点，`_draw()` 给每颗灰尘盖一个 `pixel_size × pixel_size`
  （默认 1×1）的 `draw_rect`，所以在 320×180 设计分辨率下永远是恰好一个像素。
- **确定性**：位置由 `spawn_seed` 的 `RandomNumberGenerator` 生成，同一个房间永远是同一片灰尘；
  没有随机过程，测试可以断言位置。
- **飘动**：基础漂移 `drift`（默认 (4.5, −1.6) px/s）× 每颗自己的速度倍率，叠一个正弦摆动，
  出房间边界就从对面绕回来（`fposmod`），所以一片灰尘能一直飘下去。
- **亮度**：`z_index = 9`，画在光照 pass 之后（否则会被压暗两次），因此它自己按"最近光源"
  算亮度：`lerp(unlit_alpha, 1.0, 1 - dist/radius)`，光源来自 `room_light` / `fog_light`
  和主角提灯（`lantern_radius`）。`unlit_alpha` 是"完全黑暗里保留多少"，默认 0.35 ——
  暗角里的灰尘很淡但不会消失，灯下最亮。

| 参数 | 默认 | 作用 |
| :--- | :--- | :--- |
| `count` | 56 | 一个房间的灰尘数量 |
| `drift` | (4.5, −1.6) | 基础漂移速度 px/s |
| `sway_px` / `sway_speed` | 2.4 / 0.28 | 摆动幅度与频率 |
| `pixel_size` | 1 | 一颗灰尘的边长 |
| `alpha` | 0.62 | 峰值不透明度 |
| `twinkle` | 0.35 | 忽明忽暗的幅度 |
| `unlit_alpha` | 0.35 | 无光处保留的不透明度 |
| `lantern_radius` | 90 | 主角提灯照亮灰尘的半径 |

实测（隔离场景，155 灰的板面、默认 `alpha`）：每颗灰尘都是**孤立单像素**，
40 颗里 40 颗孤立、亮度 216–240（板面 155），即清晰可见的白色亮点；
在真实 lab 房间里用"逐像素对比 + 暂停世界"的方式验证绘制路径本身没有丢
（把 `alpha` / `pixel_size` 拉满时整帧出现 1815 个变化像素，
说明 SubViewport + CRT 之后灰尘确实进了画面）。

## 测试

- `tests/world/test_backdrop_shadow.gd`：无背景瓦片的房间不报错、剪影与 quad 的构建、
  quad 的父节点与 z 顺序（plate 之后、瓦片之前）、shader 参数、最近光源的方向与上限、
  灯换边后阴影翻转、`clear_room` 清干净。
- `tests/world/test_dust_field.gd`：种子数量、像素对齐、长时间漂移后仍在房间矩形内（绕回）、
  一秒内位移上限（"缓慢"的定量约束）、同种子同布局、`clear_room`。
