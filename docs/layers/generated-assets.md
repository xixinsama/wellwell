# 哪些"资产"是算出来的（法线 / 蓝噪声 / 光照图）

项目里有几样东西看起来像美术资产，其实**是工具或运行时算出来的**。这份文档把它们列清楚：
从哪来、怎么重算、谁保证它没走样、以及为什么某些东西坚持不接受手绘。

---

## 1. 一览

| 东西 | 性质 | 来源 | 重算方式 | 守卫 |
| :--- | :--- | :--- | :--- | :--- |
| `assets/images/primordial_tileset.png` | **手绘** | 作者画的反照率图集 | — | — |
| `assets/images/primordial_tileset_normal.png` + `resources/tilesets/primordial_tileset_normal.tres` | **烘焙** | 由上表推出（亮度=高度，剪影做斜角） | `scripts/tools/bake_tileset_normals.gd` | `tests/world/test_tileset_normals.gd` |
| `resources/textures/blue_noise_64.png` | **烘焙** | 64×64 void-and-cluster，固定种子 | `scripts/tools/bake_blue_noise.gd` | `tests/world/test_blue_noise.gd` |
| 光照图（`LightViewport`） | **运行时** | 加色 `PointLight2D` + 瓦片遮挡体；灯的渐变是程序生成的 `GradientTexture2D` | 每帧由 `LightField` 渲染 | `tests/world/test_light_field.gd` |
| 法线缓冲（`NormalViewport`） | **运行时** | 把 `BackTiles`+`SolidTiles` 用法线图集克隆进去渲一次 | 绑房间时渲一次后 `UPDATE_DISABLED` | `tests/world/test_normal_field.gd` |
| 背景瓦片剪影（`ShadowViewport`） | **运行时** | CPU 从 `BackTiles` 合成为白色剪影 | 绑房间时 | `tests/world/test_backdrop_shadow.gd` |
| 气体密度 + 速度场 | **运行时** | 20 个求解 pass | 每秒 `sim_hz` 步 | `tests/world/test_gas_solver.gd` |
| 背景板（`BackdropPlate`） | **贴图 + 参数** | `assets/images/backdrop_well.png` 做底板，`backdrop_drift.gdshader` 加漂移和抖动 | — | — |
| CRT / 描边 / 泛光 / 暗部 | **纯着色器** | 没有图片资产 | — | 各自的测试 |

**历史遗留，不要用**：`resources/tilesets/tilemap8_8*.png`、`tileset8_8.tres`、`tilemap8_8.tres` —— 早期迭代留下的，现役图集是 `primordial_tileset.tres`（模板和 `world_root.tscn` 都只引用它）。

---

## 2. 法线图集：为什么不接受手绘

### 它是什么

`bake_tileset_normals.gd` 读**反照率**图集，逐像素推一个法线，写出
`assets/images/primordial_tileset_normal.png`，并按反照率图集的**结构**重建
`resources/tilesets/primordial_tileset_normal.tres`（同样的图集坐标、同样的 alternative 顺序、同样的翻转标志）。

高度模型只有两步：

1. **亮度 = 高度**（美术是带斜角的像素块，亮的地方是凸起的）；
2. **剪影变成斜角**：透明像素往下掉 `SILHOUETTE_BEVEL_DEPTH`，于是轮廓内侧的一圈像素朝缝隙倾斜 —— 台阶、斜坡、藤蔓、新加的尖刺才会读成"圆边"，而不是一张平贴纸。

然后平滑一次、中心差分求梯度，编码成 `n * 0.5 + 0.5`（RGB），alpha 沿用反照率的 alpha（空格子保持平坦透明，让法线缓冲的底色透出来）。

### 为什么这样做"可以"（四条理由）

1. **每块瓦片是它自己像素的纯函数。** 不读跨瓦片数据，所以同一块瓦片放在房间任何位置、跟谁相邻，法线都完全一样 —— 这正是瓦片图集被使用的方式。
2. **跨瓦片是周期的。** 边缘像素的邻居取瓦片自己的对边，所以一整面同样的墙不会在接缝处出现 1px 断裂。反过来（复制边缘）会因为美术不对称而在每条缝上留下一道网格 —— 这是烘焙器注释里明确写下的取舍。
3. **新增瓦片是零作者成本。** 反照率加一块（比如尖刺），重跑一次就自动有法线；没有任何"每块瓦片手工配置"的步骤，也就不会漏。
4. **翻转变体的限制是已知的。** Godot 4.7 的 `TileData` 没有 `texture_region`，alternative 只能翻转贴图区域，不能取反法线的 x/y，所以 `flip_h` 的 alternative 会有"位置镜像、法线未取反"的瑕疵。现有 alternatives 只用在对称的块和边角上，瑕疵看不出来；这一点在 `docs/lighting.md` 里有同样的记录。

所以政策是：**想要某块瓦片更立体 → 改它的明暗或形状，然后重烘；不要单独画一张法线贴图。** 手绘法线在这条管线里会被下一次烘焙覆盖，而且和"每块瓦片纯函数"的假设冲突（会引入接缝）。

### 三种浮雕模式（`LightField.relief_normal_mode`）

| 值 | 名字 | 用法线从哪来 | 什么时候用 |
| :--- | :--- | :--- | :--- |
| 0 | Flat | 不用 | 完全不要浮雕（省一点开销） |
| 1 | Derived | 屏幕空间 Sobel（零作者成本） | 没有烘焙图集时的默认值（`light_field.gd` 的导出默认是 1） |
| 2 | Authored | 上面烘焙出来的法线图集 | **现役**：`world_root.tscn` 里显式设成 2 |

模式 2 也不是"读手绘资产"，它读的就是烘焙产物。浮雕强度 = `relief_strength × authored_relief_gain`（默认 0.35 × 2.0），实测标定见 `docs/lighting.md` 的"法线强度的实测标定"。

### 现在的一个真实例子（写这份文档时的状态）

反照率图集在编辑器里被改过（32×72 → 48×72，加了列），而 `primordial_tileset_normal.png` 还是 32×72，于是
`tests/world/test_tileset_normals.gd` 直接报：

```
normal atlas is (32, 72) but the albedo is (48, 72)
```

这不是"渲染坏了"，而是**守卫在提醒你：法线该重烘了**。修法就一条命令：

```powershell
& $godot --headless --path . -s res://scripts/tools/bake_tileset_normals.gd
```

它幂等、可重复跑，且会把新增/删除的瓦片、alternatives、翻转标志一起同步过去。

---

## 3. 蓝噪声阈值贴图

气体层把不透明度量化成 32 级，用一张 64×64 的蓝噪声当阈值（`fog_layer.gdshader` 的 `stipple_at()`，`stipple_mode = 1`）。
贴图是烘焙的（void-and-cluster，固定种子，可平铺），不是找来的素材：换它就等于换整个雾的颗粒感。

```powershell
& $godot --headless --path . -s res://scripts/tools/bake_blue_noise.gd
```

`tests/world/test_blue_noise.gd` 守的东西：直方图均匀、每个字节值都被用到、没有行列偏置、
周期 2/4 格点上的能量比有序抖动低 1000 倍以上、低频环能量接近零、25% 覆盖率下最近邻距离是白噪声的 1.4 倍以上。

---

## 4. 运行时算出来的（不落盘）

这些每帧或每次换房间重算，磁盘上没有对应文件，**改美术的方式是改参数或改瓦片**：

* **光照图**：黑底 + 提灯三层（径向渐变是程序生成的）+ 房间灯 + 瓦片遮挡体。房间尺寸，`UPDATE_ALWAYS`。
* **法线缓冲**：房间尺寸，绑房间时渲一次。
* **背景瓦片剪影**：房间尺寸，绑房间时合成。
* **气体密度/速度场/细节 tracer**：`房间像素 / gas_cell_pixels`，每 `1/sim_hz` 秒一步。

验证它们没有捷径，用 `scripts/tools/render_inspector.gd` 把遮罩导出来看（`mask_light_map_*`、
`mask_normal_buffer_*`、`mask_backdrop_mask_*`、`mask_gas_density_*`），或者直接读代码里的断言测试。

---

## 5. 真正手绘的只有这些

* `assets/images/primordial_tileset.png`（反照率图集，是所有瓦片内容的唯一来源）
* `assets/images/backdrop_well.png`（背景底板贴图）
* 角色/精灵帧（`build_hero_sprite_frames.gd` 生成资源，但美术源是手绘）
* 其余全部是着色器 + 参数：描边、暗部、高光、泛光、气体、水、雾、灰尘、CRT
