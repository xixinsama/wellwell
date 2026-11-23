# 一个房间是怎么被渲染出来的

这份文档回答三件事：**一帧画面经过哪些步骤**、**各种遮罩之间怎么叠**、
**怎么自己截每一层并量性能**。最后附今天这批美化项的位置索引。

所有数字都是在本机（GTX 1650 / Forward+ / Vulkan）320×180 设计分辨率下实测的。

---

## 1. 一帧的从下到上

```
WorldRoot (Node2D, 整个世界的容器)
  └─ SubViewport 322×182, canvas_item_default_texture_filter = NEAREST
       ├─ TerrainRoot   ← 每个房间一个节点，房间原点是 chunk*320×180
       │    └─ <room>/Background/BackdropPlate      z -1
       │    └─ <room>/Background/BackdropTileShadow z  0   (背景瓦片投影)
       │    └─ <room>/Terrain/BackTiles      z 0
       │    └─ <room>/Terrain/SolidTiles     z 0
       │    └─ <room>/Terrain/DetailTiles    z 0
       │    └─ <room>/Terrain/TerrainHighlight z 1         (描边)
       │    └─ <room>/Entities/...           z 0          (灯、喷口、迷雾区…)
       ├─ WorldRuntime / Player             z 0 / 10
       ├─ CrumbleRuntime 坍塌碎片        z 9（水花像素 z 跟随实例化它的节点）
       ├─ WaterField / WaterGrid            z 0 + 自带 shader
       ├─ Atmosphere/GasLayer               z 5   (blend_mix, 整房间 quad)
       ├─ ScreenBloom/BloomComposite        z 9   (additive 合成)
       ├─ LightField/LightShade             z 8   (把光图变暗部)
       ├─ LightField/LightGlow              z 9   (光图的高光)
       ├─ NormalField/NormalViewport        (不进画面，只产出纹理)
       ├─ BackdropShadow/ShadowViewport     (不进画面，只产出纹理)
       ├─ DustField                         z 9   (单像素灰尘)
       └─ FogOfWar/FogMask                  z 10  (迷雾)
  └─ SubViewportContainer (stretch, stretch_shrink 4, texture_filter nearest)
  └─ CanvasLayer 128 → CrtOverlay           屏幕最上层（像素对齐扫描线）
```

**排序规则**：`z_index` 对整个画布全局排序，同 z 再按树序。所以
`Background`（plate −1、投影 0）永远在 `Terrain`（瓦片 0）之前，
因为 0 相同、`Background` 在 `Terrain` 前面。
标了 `z_as_relative = false` 的（气体 5、光 8/9、尘埃 9、雾 10）直接对世界画布排序，
不受父节点影响。

## 2. 一帧的步骤（渲染侧）

| # | 步骤 | 谁做的 | 输出到哪 |
| :--- | :--- | :--- | :--- |
| 1 | **光照图**：黑底 + 3 个加色 PointLight（提灯核/晕/溢出）+ 每个房间灯 2 层 + 遮挡体阴影，渲进 320×180 子视口 | `LightField` | `LightViewport` 纹理，每帧更新 |
| 2 | **法线缓冲**：把 `BackTiles` + `SolidTiles`（或手画 `NormalTiles`）用**法线图集**克隆进子视口（背景在下、墙在上），渲一次就 `UPDATE_DISABLED` | `NormalField` | `NormalViewport` 纹理，换房才重渲 |
| 3 | **背景投影剪影**：`BackTiles` 克隆进子视口，画成白色剪影，渲一次 | `BackdropShadow` | `ShadowViewport` 纹理 |
| 4 | 房间内容照常画：背景板（漂移+对比度抖动）、背景投影、瓦片、实心瓦片、细节瓦片、实体、玩家、水、水花 | Godot 2D | 主视口 |
| 5 | **描边**：瓦片边缘、被光照图门控的 1px rim | `TerrainHighlight` | 主视口 z 1 |
| 5.5 | **气体**：整房间一张 quad；不透明度 = 三层密度 × 光照，按 blue-noise 阈值量化成 32 级；颜色额外朝主光源做 6 次体积自遮挡 | `Atmosphere/GasLayer` | 主视口 z 5 |
| 6 | **暗部**：有时法线浮雕；`alpha = 1 - (光 + 环境光 + 阴影回弹)`，像素抖动 | `LightShade` | 主视口 z 8 |
| 7 | **高光**：光图亮的地方加色，边缘向内收 1–2px | `LightGlow` | 主视口 z 9 |
| 8 | **泛光**：阈值+水平模糊 → 垂直模糊（都是半分辨率）→ 抖动加色合成 | `ScreenBloom` | 主视口 z 9 |
| 9 | **灰尘**：56 个 1×1 白点，画在光照 pass 之后，亮度按最近光源算 | `DustField` | 主视口 z 9 |
| 10 | **迷雾**：CPU 写每格 1 纹素的遮罩（a=不透明度, r=闪光, g=有符号距离），片元里做触须/呼吸/抖动切割 + 聚光灯 | `FogOfWar` | 主视口 z 10 |
| 11 | **放大**：322×182 → 1280×720，nearest，`stretch_shrink = 4` | `SubViewportContainer` | 窗口 |
| 12 | **CRT**：像素对齐扫描线 + 轻微色偏（亮度不变） | `CrtOverlay`（CanvasLayer 128） | 窗口最上层 |

## 3. 遮罩之间怎么叠（谁采样谁）

```
PointLight2D × N ──┐
LightOccluder2D ───┴─→ [LightViewport] ──纹理──┬─→ LightShade（乘暗）─→ 主视口
                                                ├─→ LightGlow （加亮）─→ 主视口
                     NormalViewport ──纹理──┬───┤  (shade/glow 采样法线做浮雕)
                                             │   ├─→ FogOfWar（推挤迷雾边缘 10px）
                                             │   ├─→ TerrainHighlight（门控描边）
                                             │   ├─→ WaterField/WaterGrid（水面反光）
                                             │   └─→ Atmosphere（气体受光）
                                             │
BackdropShadow.ShadowViewport ──纹理──→ BackdropTileShadow（乘在 plate 上，z 0）
主视口 ──(hint_screen_texture)──→ LightShade 的 derived 法线（模式 1）
FogOfWar mask(CPU) ──纹理──→ FogMask（片元生成边缘）──→ 主视口 z 10
```

关键点：

- **光照图只有亮度，没有方向**。方向是 shader 里对光图求**梯度**得到的，
  所以加浮雕不需要给 shader 传光源列表，逻辑灯光数量不变。
- **迷雾只加暗，不会开格子**：`light_push_px` 只是把抖动出来的边缘往回推，
  暗格子该黑还是黑。
- **背景投影是乘法**（`blend_mul`），只会压暗 plate，永远不会提亮。
- **聚光灯在 shader 里**（`focus_at()`），因为要跟主角每帧移动；写进遮罩会变成
  "每帧每格一次 fill_rect"。

## 4. 实体和房间是什么时候进来的

1. `WorldSession.start()` 校验世界数据 → 清空所有扩展（`clear_room`）。
2. 把目标房间的**烘焙场景实例化**到 `TerrainRoot` 下（`scenes/rooms/generated/<room>/runtime.tscn`），
   房间原点是 `origin_chunk * 320×180`。房间自带的实体（`RoomContent/Entities`：
   `RoomLight`、`GasVent`、`FluidRegion`、`FogZone`、`SavePoint`…）此刻就在树里了。
3. 依次调用扩展的 `bind_room_with_origin(room_data, room_content, origin_chunk)`：
   `WaterField` → `WaterGrid` → `Atmosphere` → `LightField` → `NormalField` →
   `BackdropShadow` → `DustField` → `FogOfWar`（顺序由场景树顺序决定，各扩展互不依赖，
   手递手通过 `set_light_field()` / `set_normal_field()` 完成）。
4. `world_ready` 信号 → `BackdropField` 给每个房间的 `Background` 铺 320×180 plate。
5. 玩家一直在 `WorldRoot` 里，不随房间重建；换房只重绑扩展 + 重开相机。

## 5. 性能

实测（lab 房间，320×180 视口，1280×720 窗口，关 vsync 不锁帧，best of 3）：

| 项 | 数值 |
| :--- | :--- |
| 整帧 | **1.7 – 2.2 ms/frame**（约 450–580 fps 的绘制能力） |
| 运行间噪声 | ±0.1 ms（同一配置两次跑能差 0.12 ms） |
| 光线图子视口 | 每帧一次 320×180，3+2×N 个 PointLight + 阴影 |
| 法线缓冲 / 背景投影 | 换房各渲一次，之后每帧 0 |
| 泛光链 | 两个 160×90 pass + 一次合成，≈0.2–0.6 ms |
| 灰尘 | 量化到 8 Hz 重绘后**低于噪声地板**（<0.1 ms） |

**不要相信"隐藏一个子树测 delta"**：在一帧内切换可见性会让渲染器重建批次，
开销比那个子树本身还大（实测 TerrainRoot 显示 14.8 ms / 隐藏 7.1 ms，纯属假象）。
正确做法是**分开跑两次**，用 `--hide` 参数对比整帧基线（见下）。

## 6. 检查工具：`tools/render_inspector.gd`

```powershell
# 整帧 + 每层 + 所有遮罩 + 层清单 + 性能
& $godot --path . --resolution 1280x720 `
    -s res://tools/render_inspector.gd `
    -- --out C:/tmp/shots

# 想量某个系统的代价：两次跑，比 "all systems on"
& $godot --path . --resolution 1280x720 `
    -s res://tools/render_inspector.gd -- --out C:/tmp/a --hide=DustField,ScreenBloom

# 看"被上层盖住的中间件"（默认把 BackTiles 压到 alpha 0.2 再截一张）
& $godot --path . --resolution 1280x720 `
    -s res://tools/render_inspector.gd -- --out C:/tmp/peek --peek
# 压哪几层、压多少：--peek-layers=BackTiles,SolidTiles --peek-alpha=0.35

# 换场景
... -- --scene res://scenes/levels/test_world/water_hall_runner.tscn --out C:/tmp/hall
```

输出（默认写到 `user://render_inspector`，`--out` 可指定绝对路径）：

| 文件 | 内容 |
| :--- | :--- |
| `full.png` | 完整一帧（和游戏里看到的一致） |
| `solo_<层>.png` | 只显示某个顶层系统（`player`、`watergrid`、`lightfield`、`fogofwar`…） |
| `stack_z-001.png` … `stack_z+010.png` | **z 阶梯**：`z <= N` 的所有东西，一格一格看"这一层加了什么" |
| `mask_fog_mask_*.png` | 迷雾遮罩（灰度=不透明度，红=闪光，绿=有符号距离） |
| `mask_light_map_*.png` | 光照图 |
| `mask_normal_buffer_*.png` | 法线缓冲（RGB 法线） |
| `mask_backdrop_mask_*.png` | 背景瓦片剪影 |
| `mask_gas_density_*.png` | 气体密度（80×45） |
| `mask_water_cells_*.png` | 水体单元（80×45，R 填充/G 深度/B 流动） |
| `inventory.txt` | 整棵树按绘制顺序的层清单：z、是否相对、可见、纹理尺寸、shader |
| `timings.txt` | 整帧时间（含噪声说明） |
| `peek.png` | **中间件**：把 `--peek-layers` 指定的层压暗后的那一帧（默认背景瓦片），
用来确认被上层盖住的效果（比如背景瓦片投影）|


注意：`solo_<层>` 只对"自己画的"层有效。`BackdropField` 的 plate 挂在
`TerrainRoot/<room>/Background` 下（不是它的子节点），所以 `solo_backdropfield`
是空的 —— 这时看 `stack_z-001` / `inventory.txt` 里的 `BackdropPlate`。

## 6.5 房间转场：瞬切 vs 滑动

房间切换默认是 **瞬切**，可以在 设置 → 游戏 → `房间转场滑动` 打开相机滑动。

- **瞬切**（默认）：`PixelCamera2D.set_smooth_room_transition(false)` 关掉 Godot 内置的
  `position_smoothing_enabled`，相机在 `set_room_bounds()` 里直接落到新房间；
  紧接着 `WorldSession` 调一次 `RenderingServer.force_draw(false)`。
  法线缓冲、背景投影剪影这类**一次性缓冲**本来要等下一帧才出内容，
  强制画一次之后 **切换后的第一帧就是完整的**，不会再出现"一帧平法线/没阴影"。
- **滑动**：保留原来的相机 glide。注意滑动期间相机还在看旧房间，而光照/泛光/气体/迷雾
  的 quad 已经绑到新房间的矩形上了，所以旧房间那半边会短暂地缺这些层。
  本项目的房间就是一屏（320×180），滑动没有可看的内容，这也是默认瞬切的原因；
  多 chunk 房间再开滑动。
- 两种模式共用同一套房间绑定流程，差别只有相机目标 + 是否强制渲染一帧，见
  `addons/platformer_kit/world/runtime/world_session.gd:_configure_camera_for_room()`。


## 7. 今天这批美化项在哪

| 效果 | 代码 | 可调参数 |
| :--- | :--- | :--- |
| 抖动背景板（只在有渐变处抖） | `game/shaders/backdrop_drift.gdshader` | `BackdropField.dither_strength / dither_levels` |
| 背景瓦片投影（固定朝左下 10 px、纯黑） | `game/world/backdrop_shadow.gd` + `backdrop_shadow*.gdshader` | `offset_direction / offset_px / strength / blur_px / shadow_tint` |
| 法线贴图（图集 + 烘焙工具） | `assets/images/primordial_tileset_normal.png`、`tools/bake_tileset_normals.gd` | 工具顶部常量；`LightField.relief_*` |
| 光照浮雕 | `game/shaders/light_overlay.gdshader`、`light_glow.gdshader` | `relief_normal_mode / relief_strength / authored_relief_gain` |
| 迷雾渐隐（暗区进出） | `addons/metroidvania_kit/map/discovery/fog_of_war.gd` | `zone_reveal_seconds / zone_reveal_stagger / zone_restore_*` |
| 迷雾聚光灯 | `fog_mask.gdshader` 的 `focus_at()` | `focus_radius_px / focus_falloff_px`、`FogZone.focus_*` |
| 前景灰尘 | `game/world/dust_field.gd` | `count / drift / sway_* / alpha / unlit_alpha` |
| 气体去雾（只留喷口） | `addons/fluid_kit/runtime/gas/atmosphere.gd` | `gas_ambient / gas_refill / gas_decay` |
| 气体卷曲（涡量约束） | `gas_velocity.gdshader` 的 `curl_at()` / `GasSim.vorticity` | `Atmosphere.gas_vorticity` |
| 气体细纹跟着流体走 | `gas_velocity.gdshader` 的蓝通道 tracer、`fog_layer.gdshader` 的 `detail_*` | `detail_amount / detail_contrast / detail_refresh / detail_hz` |
| 气体体积自遮挡 | `fog_layer.gdshader` 的 `volume_*` | `volume_shadow / volume_weight / volume_step_px` |
| 气体淡化用蓝噪声阈值 | `resources/textures/blue_noise_64.png`（`tools/bake_blue_noise.gd` 生成） | `stipple_mode / stipple_steps` |
| 水体波纹覆盖整条水 | `water_grid.gd(shader)` / `water_field.gd(shader)` | 自动测量；`ripple_*` |
| 屏幕泛光 | `game/world/screen_bloom.gd` + `bloom_*.gdshader` | `threshold / intensity / radius` |
| CRT | `scenes/ui/crt_overlay.tscn` + `crt_screen.gdshader` | `GlobalSettings.crt_enabled` |

## 8. 迷雾渐隐那次的 bug（留给以后）

- **翻方向会瞬移**：暗区淡出到一半又走出去时，旧实现拿"某一格"的当前不透明度当成
  整块的新起点，其余格子会跳到那个值上。现在每个格子各自记录起点（`from_cells`），
  实测最大单帧跳变从 0.094 降到 0.035（0.9 s 淡出本身的速率）。
- **边缘闪一下**：着色器原来用 `step(0.01, 不透明度)` 决定"要不要长触须"，
  格子跨过阈值那一刻触须整块出现/消失 → 闪烁。现在按 `1 - 不透明度` 线性淡入，
  没有阈值跳变。
- 同方向的淡入淡出**不会**被重复启动（贴着区域边缘来回走时不会重置波形）。

## 9. 气体那层的两条坑（都是量出来的）

- **有向抖动仍然是"格子"**：4×4 Bayer 的每一列是平衡的（这点早修过了），但雾淡到
  一半覆盖率时，它点亮的就是一张 2×2 棋盘格 —— 4× 放大后每一列都变成竖虚线，
  于是"点阵"看起来就是"竖条"。实测：同一份气体状态下，抖动的高频能量有 15.7%
  压在周期 2/4 的格点上，放大后竖直游程有 79.5% 正好是一个设计像素。换成 64×64
  蓝噪声贴图后是 0.12% 和 55.7%，平均不透明度只差 −1.1%。
- **别把第四个数塞进密度纹理的 alpha**：那几个 SubViewport 是透明的，canvas 会
  **预乘**写入的 alpha，而密度缓冲是乒乓的 —— 写在 alpha 里的细节会把气体**每步**
  砍一半。实测 172 步内平均密度从 0.022 掉到 0.0004。细节只好放进速度场（写
  alpha = 1.0）的蓝通道，见 `addons/fluid_kit/README.md` 的 "The detail tracer"。
