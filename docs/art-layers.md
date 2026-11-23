# 渲染层级总表：一帧画面从底到顶

这份文档只回答一个问题：**屏幕上这一帧是按什么顺序叠出来的，每一层是什么、为什么在那儿**。
它是索引，不是全部细节 —— 每层都指向一份更细的文档。

数字都来自本机（GTX 1650 / Forward+ / Vulkan）320×180 设计分辨率下的实测，或直接读代码得到。

---

## 0. 怎么用这份文档

1. 想弄清楚"某个像素是哪一层画的" → 看第 2 节的表，然后用第 7 节的 `render_inspector` 单独截那一层。
2. 想改某一层 → 表里最后一列指向它的分文档；分文档里有参数、原理和实测效果。
3. 想加一个新层 → 先看第 3 节（顺序规则）和第 4 节（系统该放哪、房间该放什么），别直接往房间场景里塞。

---

## 1. 一帧分成两半：先算四张图，再按 z 画

画面上的层大多不是"自己算自己"，而是**先离屏算出四张图**，再被若干层共享。这四张图是理解整个渲染的前提：

| 离屏产物 | 谁产出 | 尺寸 | 更新频率 | 谁在消费 |
| :--- | :--- | :--- | :--- | :--- |
| **光照图** | `LightField` 里的 `LightViewport`（黑底 + 加色 `PointLight2D` + 瓦片遮挡体） | 房间尺寸（一屏 320×180，2×2 房间 640×360） | `UPDATE_ALWAYS` | 暗部、高光、泛光、气体、灰尘、背景投影 |
| **法线缓冲** | `NormalField` 里的 `NormalViewport`（`BackTiles` 在下、`SolidTiles` 在上，用法线图集克隆） | 房间尺寸 | 换房间时渲一次后 `UPDATE_DISABLED` | 暗部的浮雕、法线调试视图 |
| **背景瓦片剪影** | `BackdropShadow` 里的 `ShadowViewport`（CPU 从 `BackTiles` 合成） | 房间尺寸 | 换房间 / 房间内容变化 | 背景瓦片投影那一层 |
| **气体场** | `Atmosphere` 里 20 个求解 pass（速度/压力/密度），+ 速度场蓝通道当细节 tracer | `房间像素 / 4`（一屏 80×45，可调 `gas_cell_pixels`） | 每秒 `sim_hz` 步 | 气体层（密度 + 细节） |

这四张图都是**房间尺寸或房间相关**的，所以它们跟着房间绑定重建，而不是跟着摄像机。

---

## 2. 从最底层开始，逐层

z 由小到大，就是绘制顺序。`z_index` 对整个画布**全局排序**，同一个 z 里再按**树序**决定先后。

| # | 层 | z | 谁负责（脚本） | 画的是什么 | 关键参数 | 分文档 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | **背景板** `BackdropPlate` | −1 | `scripts/world/backdrop_field.gd` | 每个房间一张纯色/渐变底板，逐行轻微漂移 + 有序抖动量化，让"空"的背景有空气感 | `shimmer`、`dither_strength`、`dither_levels` | [backdrop-and-dust.md](backdrop-and-dust.md) |
| 2 | **地形瓦片** `BackTiles` / `SolidTiles` / `DetailTiles` | 0 | `world_terrain_runtime.gd` + 房间烘焙产物 | 背景瓦片（不碰撞、Layer 上 `collision_enabled = false`）、实心瓦片（碰撞 + 挡光 + 挡气 + 挡视线）、细节瓦片（纯装饰，`SolidTiles` 之后画；没有任何系统按名字读它）。注意**梯子放在 `SolidTiles`**，靠图集坐标 `(0,7)` 认，不靠层名 | 图集 `primordial_tileset.tres` | [layers/terrain-tiles.md](layers/terrain-tiles.md) |
| 3 | **房间实体** `Entities` | 0 | 房间烘焙产物 | 灯、喷口、水盆、迷雾区、传送点 —— 都是"标记 + 少量自绘"（`_draw` 的编辑器图形运行时关闭） | 每个节点的导出参数 | 各自分文档 |
| 4 | **水** `WaterField` / `WaterGrid` + `WaterGridSurface` | 0 / 1 | `addons/fluid_kit` | 水面 quad + 细胞流体表面（波纹、泡沫、深浅） | `water_*`、`ripple_*` | [water-and-mist.md](water-and-mist.md) |
| 5 | **地形描边** `TerrainHighlight` | 1 | `scripts/world/terrain_highlight.gd` | 瓦片边缘 1px 的勾边，被光照图门控（暗处不亮） | `edge_alpha`、`lit_gain` | [terrain-highlight.md](terrain-highlight.md) |
| 6 | **气体** `Atmosphere/GasLayer` | **5** | `addons/fluid_kit` 的 `atmosphere.gd` + `fog_layer.gdshader` | 一张覆盖整房间的 quad：三层气体密度 → 不透明度/颜色，加细节 tracer、体积自遮挡，最后用蓝噪声阈值量化成 32 级 | `gas_cell_pixels`、`gas_alpha`、`stipple_mode`、`volume_weight` | [layers/gas-layer.md](layers/gas-layer.md) |
| 7 | **暗部** `LightShade` | **8** | `scripts/world/light_field.gd` + `light_overlay.gdshader` | 把整帧乘暗到 `ambient + 光图`，带法线浮雕（斜面的受光差） | `ambient`、`relief_strength`、`dither_strength` | [lighting.md](lighting.md) |
| 8 | **高光** `LightGlow` | **9** | `light_glow.gdshader` | 光图亮的地方**加色**，边缘向内收 1–2px，做出灯芯的溢出光 | `glow_gain`、`rim_shrink` | [lighting.md](lighting.md) |
| 9 | **泛光** `ScreenBloom/BloomComposite` | **9** | `scripts/world/screen_bloom.gd` | 半分辨率阈值 + 水平/垂直模糊，再抖动加色合成（160×90 缓冲） | `threshold`、`intensity`、`radius` | [lighting.md](lighting.md) |
| 10 | **灰尘** `DustField` | **9** | `scripts/world/dust_field.gd` | 56 个 1×1 白点，亮度按最近光源算，在光柱里才亮 | `count`、`drift`、`sway_*`、`lit_gain` | [backdrop-and-dust.md](backdrop-and-dust.md) |
| 11 | **水花 / 坍塌碎片** | **9** | `scripts/world/crumble_runtime.gd`、`game/water/effects/water_splash_pixels.tscn` | 坍塌平台碎成的小贴图块（每块 `z_index = 9`）；水花的像素粒子由水的代码在撞击点实例化，z 跟随父节点 | 粒子数量、`debris_life` | [fog-zones-and-crumble.md](fog-zones-and-crumble.md) |
| 12 | **背景瓦片投影** `BackdropTileShadow` | **10** | `scripts/world/backdrop_shadow.gd` | `BackTiles` 的剪影按主光源方向偏移、模糊，画成"瓦片投在背景板上的影子"；shader 自己把被瓦片盖住的区域挖掉 | `offset_px`、`key_extent`、`fill_erase`、`max_darkness` | [backdrop-and-dust.md](backdrop-and-dust.md) |
| 13 | **玩家** `Player` | **10** | `scenes/player/` | 角色本体 + 动作特效 | — | `docs/player-effects.md` |
| 14 | **迷雾** `FogOfWar/FogMask` | **10** | `addons/metroidvania_kit` + `fog_mask.gdshader` | 未探索格子上的雾，边缘长触须、被灯光推开、带聚光灯 | `zone_reveal_*`、`focus_*` | [fog-zones-and-crumble.md](fog-zones-and-crumble.md) |
| 15 | **调试** `DebugOverlay/Visualizer` | 120 | `addons/platformer_debug` | 碰撞框、区域、法线调试视图（默认关） | `set_enabled` | [render-pipeline.md](render-pipeline.md) |
| 16 | **CRT** `CrtOverlay` | CanvasLayer 128 | `scripts/ui/crt_overlay.gd` + `crt_screen.gdshader` | 在**窗口像素**上做扫描线、荫罩竖条、色散、暗角、磷光泛光 | `GlobalSettings.crt_enabled` | [layers/crt.md](layers/crt.md) |

第 15、16 层已经不在世界 SubViewport 里了：120 在世界画布里，CRT 在世界**放大之后**的窗口上。

---

## 3. 顺序里最容易忘的三处

**气体在暗部之下（z 5 < 8）**：雾不是"发光的贴纸盖在光照上"，它和地形一样被光照图压暗、被泛光照亮。所以气体层里自己算了一遍"受光"（用同一张光图），但最终的明暗仍然由 z 8 的暗部统一决定。

**先乘暗（8）再加光（9）**：物理上光是先被介质衰减、再叠加的，所以乘色的暗部必须在前、加色的高光/泛光/灰尘在后。反过来会出现"高光被压暗"或"暗部被加亮"。

**背景瓦片投影 z=10，却看起来在瓦片下面**：它必须在加色层之后，否则会被高光/泛光洗掉；而它"看起来在瓦片下"是靠 shader 里的 `free = 1 - smoothstep(0.05, 0.75, tile_coverage)` 自己把瓦片区域挖掉实现的，不是靠 z。改这个 shader 时别删掉那项，否则整面墙都会被压暗。

---

## 4. 为什么这些系统不放在模板关卡里

一句话：**系统是"一个世界一份"的单例，房间只是数据**。光照图视口、法线缓冲、泛光缓冲、气体求解器、迷雾遮罩这些东西如果放进每个房间，烘焙一次就多一份缓冲区和一个求解器，同屏会有 N 份在互相覆盖。

所以分工是：

* `scenes/runtime/world_root.tscn`（运行时框架，整个世界一份）持有系统：`BackdropField`、`BackdropShadow`、`TerrainHighlight`、`LightField`、`NormalField`、`ScreenBloom`、`DustField`、`FogOfWar`、`Atmosphere`、`WaterField`、`WaterGrid`、`CrumbleRuntime`、`Player`、`PixelCamera2D`。
* `scenes/rooms/template/level_template.tscn`（房间模板，作者编辑的东西）只放**房间内容**：`RoomContent/{Background, Terrain(三层瓦片), Entities, Foreground}`，外加标记（`SpawnPoint`、`RoomLight`、`GasVent`、`GasField`、`WaterBasin`、`FogZone`…）。
* 模板里的 `PreviewOnly/`（Player、Camera、WaterField、Atmosphere、FogOfWar、DebugOverlay）是**只给编辑器预览用的副本**，烘焙器不会把它们烘进房间（只打包 `RoomContent`）。所以在编辑器里预览房间能看到气体，不等于"气体系统住在房间里"。

机制、绑定流程和"作者能放什么"的完整清单见 [layers/scene-structure.md](layers/scene-structure.md)。

---

## 5. 哪些"资产"不是手绘的

容易忘的一类事实：项目里几张关键图**是算出来的**，不是手绘资产，改美术时要跟着重新生成。

| 东西 | 来源 | 重新生成的命令 | 谁来保证它没走样 |
| :--- | :--- | :--- | :--- |
| **法线图集** `primordial_tileset_normal.tres` + `assets/images/primordial_tileset_normal.png` | 由反照率图集 `primordial_tileset.png` 烘焙（亮度=高度，剪影做斜角） | `godot --headless --path . -s res://scripts/tools/bake_tileset_normals.gd` | `tests/world/test_tileset_normals.gd` |
| **蓝噪声阈值贴图** `resources/textures/blue_noise_64.png` | 64×64 void-and-cluster，确定性种子 | `godot --headless --path . -s res://scripts/tools/bake_blue_noise.gd` | `tests/world/test_blue_noise.gd` |
| **光照图** | 运行时 `LightField` 每帧渲染（灯 = 程序生成的径向渐变，不是图片） | — | `tests/world/test_light_field.gd` |
| **法线缓冲 / 背景剪影** | 运行时把瓦片克隆进子视口渲染一次 | — | `tests/world/test_normal_field.gd`、`tests/world/test_backdrop_shadow.gd` |

**政策：法线不接受手绘。** 理由（详见 [layers/generated-assets.md](layers/generated-assets.md)）：一个房间有几十种瓦片、还带翻转变体，手绘法线要么漏、要么在接缝处不连续；烘焙器从剪影+亮度直接推，保证"同一块瓦片放在哪都长一样"，并且新增瓦片是零作者成本。想改变某块瓦片的立体感 → 改反照率的明暗或形状，然后重烘，而不是单独画一张法线。

---

## 6. 房间作者清单

**可以放**（被系统收集/使用）：三层瓦片、`SpawnPoint`、`RoomEntrance`、`RoomLight`、`GasVent`、`GasField`、`FluidRegion`、`WaterBasin`、`WaterGate`、`FogZone`、`GasInteractor`、`GasBrush`、以及任何纯自绘的装饰节点。

**不要放**：`LightField`、`NormalField`、`ScreenBloom`、`DustField`、`FogOfWar`、`Atmosphere`、`BackdropField`、`BackdropShadow` 的运行时实例 —— 这些在 `world_root.tscn` 里已经有一份，房间再放会重复。编辑器预览需要的那几个放在模板的 `PreviewOnly/` 下，且不会被烘焙。

**放完记得**：改了图集 → 重烘法线；改了房间 → 重烘房间（`scripts/tools/rebake_room.gd`）。

---

## 7. 怎么自己看

```powershell
$godot = "D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"

# 整帧 + 每层单独一帧 + z 阶梯 + 各系统的遮罩 + 层清单
& $godot --path . --resolution 1280x720 `
    -s res://scripts/tools/render_inspector.gd -- `
    --scene res://scenes/levels/test_world/runners/light_lab_runner.tscn --out C:/tmp/layers

# 被上层盖住的层（默认把 BackTiles 压暗；比如看背景瓦片投影）
... --out C:/tmp/layers --peek
```

输出里最有用的是三样：

* `inventory.txt`：整棵树按绘制顺序的层清单（z、是否相对、可见、纹理尺寸、shader）—— 本文第 2 节就是它的可读版；
* `stack_z+N.png`：所有 `z <= N` 的东西，两两对比就知道"这一层加了什么"；
* `solo_<层>.png`：只显示某个顶层系统。

**注意**：`render_inspector` 截的是世界 SubViewport（320×180），所以它**不含 CRT**（CRT 在放大之后的窗口上）。要看 CRT 得用 `scripts/tools/gas_diagnostic.gd` 的 `window_*.png` / `window_nocrt_*.png`（它截真实窗口）。

---

## 8. 文档地图

| 文档 | 讲什么 |
| :--- | :--- |
| 本文 | 层级顺序、系统放哪、哪些资产是算的 |
| [render-pipeline.md](render-pipeline.md) | 一帧的 12 个步骤（渲染侧），以及渲染工具的用法 |
| [lighting.md](lighting.md) | 光照图、暗部、高光、泛光、法线/浮雕、参数与实测标定 |
| [layers/terrain-tiles.md](layers/terrain-tiles.md) | 三层瓦片各自是什么、谁在消费它们 |
| [layers/gas-layer.md](layers/gas-layer.md) | 气体层的渲染：密度→不透明度、tracer、体积自遮挡、蓝噪声阈值 |
| [backdrop-and-dust.md](backdrop-and-dust.md) | 背景板、背景瓦片投影、前景灰尘 |
| [fog-zones-and-crumble.md](fog-zones-and-crumble.md) | 迷雾/暗区、坍塌平台、水花 |
| [water-and-mist.md](water-and-mist.md) | 水的两种实现、气体求解器与房间作者指南 |
| [layers/crt.md](layers/crt.md) | 窗口空间的 CRT 后处理 |
| [layers/scene-structure.md](layers/scene-structure.md) | 世界框架 / 房间模板 / 预览副本 / 标记，和绑定流程 |
| [layers/generated-assets.md](layers/generated-assets.md) | 哪些图是烘焙出来的、命令、测试、为什么法线不接受手绘 |
| [terrain-highlight.md](terrain-highlight.md) | 地形描边 |
