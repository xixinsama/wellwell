# 水池与气体

两个演示房间：

- `water_hall`：两个水池、闸门、瀑布，加上三层气体。
- `gas_lab`：左墙三个喷口（每种气体一个）不断喷气，三排阶梯平台供 hero 站上去观察分层。

水与气体都是**房间扩展**（`WorldSession.register_room_extension`），和 `FogOfWar`、`CrumbleRuntime` 同构：进房 `bind_room_with_origin()`，换房 `clear_room()`。

- 水：`scripts/world/water/`
- 气体：`scripts/world/atmosphere/`（`gas_sim.gd` 调度，`gas_psi.gdshader` + `gas_sim.gdshader` 两步模拟，`fog_layer.gdshader` 渲染）
- 气体喷口：`scripts/world/atmosphere/gas_vent.gd`
- 气体（CPU 兜底）：`fog_grid.gd`，无 `RenderingDevice` 时使用
- 玩家：`game/player/player_water_motion.gd`
- 水花：`game/water/effects/water_splash.gd`
- 房间源场景：`scenes/levels/test/water_hall.tscn`、`scenes/levels/test/gas_lab.tscn`
- 生成器：`tools/build_water_room.gd`、`tools/build_gas_lab.gd`

## 运行方式

- 游戏内：主菜单 → 存档 → **Exploration Test World**（起始房间是水厅；气体实验室是同一世界的第二个房间）。
- 气体实验室直跑：运行 `scenes/levels/test/gas_lab_runner.tscn`（复制 test 世界并把起始房间改成 `gas_lab`）。
- 水厅直跑：运行 `scenes/levels/test/test_world_runner.tscn`。
- 编辑器预览：打开对应源房间按 F6。
- **设置 → 游戏 → 气体模拟** 可随时开关整套气体效果。

## 气体实验室

- 左墙（`x=10`）三个 `GasVent`：上黄（轻气体）、中青（中性）、下红（重气体），都朝 +X 喷。
- 三排平台自左下向右上排布（tile 行 18 / 15 / 12，跨 3..12、15..24、27..36），层间 24px，hero 站在上面就能看到红气下沉、青气横流、黄气上升。
- 房间用 `FogZone(Light)` 覆盖，探索雾不会压暗气体。

| GasVent 参数 | 默认 | 作用 |
| :--- | :--- | :--- |
| `channel` | Neutral | 喷哪种气体（Heavy / Neutral / Light） |
| `direction` | (1, 0) | 喷口朝向（指向房间内） |
| `radius` | 22 | 作用半径（px） |
| `rate` | 3.2 | 每秒注入的密度 |
| `jet_speed` | 460 | 喷流初速（px/s），会推动周围气体 |

## 房间作者指南

三个标记节点都放在 `RoomContent/Entities` 下，随房间一起烘焙；它们只在编辑器里画预览框，运行时是纯数据标记。

### WaterBasin / WaterGate

- `WaterBasin.size_cells`：池子矩形（8px 一格），**矩形上边 = 初始水面高度**。池底由 `SolidTiles` 自下而上扫描得到，抬高一层砖就形成溢流堰。
- `WaterGate`：覆盖的列在关闭时被标记为墙；`open_delay_seconds` 后升起并放水。

### FogLight / FogZone

- `FogLight`：气体光源（`radius` px、`energy`、`color`、`flicker`）。`Atmosphere` 按离 hero 的距离挑最多 3 个。
- 任何有水池/气体的房间都加一个覆盖全房的 `FogZone(mode=Light)`，否则探索雾会把它们压成黑带。

## 水模型

`WaterSimulation` 是一维浅水高度场：

- 每 8px 一列（和地形图块对齐），`mass` 单位 px²，深度 = `mass / 宽度`，水面 = `池底 - 深度 - 波动偏移`（y 向下）。
- 相邻列按水面高差转移体积，先算全部通量再统一应用，所以总体积精确守恒；`flow_rate / 120 <= 0.5` 保证显式扩散稳定。
- 表面另有一层纯视觉弹簧（`wave_stiffness/damping/spread`），入水冲击让它局部隆起再回落；抬升量参与水面查询，hero 会随波起伏。
- 静止后 `step()` 直接返回，几乎不耗 CPU。

渲染一张 quad：每列一个 texel 存"水面高度 + 池底高度"，shader 逐像素判断水下并画分层水色、1px 亮边、泡沫与水下光斑。溢流口另有独立的瀑布 quad，宽度 12px。

| WaterField 参数 | 默认 | 说明 |
| :--- | :--- | :--- |
| `max_depth` | 64 | 单列最大水深（px） |
| `flow_rate` | 54 | 列间传输系数；稳定上限是 `SIM_HZ / 2` |
| `splash_radius_base/scale` | 8 / 10 | 入水扰动半径 |
| `waterfall_min_drop` | 5 | 多高的落差才画瀑布 |

水面高度纹理最多每 60Hz 上传一次（模拟仍是 120Hz）；上传会强制 GPU 同步，所以不在每个物理帧都做。

## hero 在水里

`PlayerWaterMotion` 与 `LadderMotionComponent2D` 同一套组合方式：`PlayerController` 先问它，接管则跳过梯子和马达。

- 浮力按浸没比例生效，平衡点约 54% 身体在水下。
- 左右可游、上/下主动上浮下潜、贴水面按跳跳出。
- 入水瞬间按竖直速度追加下沉冲量并请求水花；速度越大沉得越深、水花越大。
- 水流会横向推动 hero；重生/锁定控制时复位。

## 气体模型：不可压流体（GPU）

**速度场不可压**：气体不是按"密度堆积"模拟的，而是用一个标量流函数 ψ 定义速度：

```
v = curl(ψ) = (∂ψ/∂y, -∂ψ/∂x)
```

这样速度的散度恒为 0（二维下混合偏导相消），也就是真正的**非压缩流体**：气体不能被"压"进角落或堆成层，只能绕着流。密度只是被这个无散速度搬运的被动标量。

每个固定步只跑 **2 个 GPU pass**（没有"迭代次数"）：

1. `gas_psi.gdshader`：用 `curl(ψ)+wind` 平流 ψ，并按三层密度的水平梯度扭转 ψ——重气让 ψ 产生一侧向下的涡、轻气反向，于是红气下沉、黄气上升、青气横流，形成卷曲的羽流。
2. `gas_sim.gdshader`：用 `curl(ψ_new)+wind+喷流+hero 推力` 平流三个密度通道，再做扩散、回填、喷口注入与 hero 抽稀。

| 通道 | 气体 | 行为 | 颜色 |
| :--- | :--- | :--- | :--- |
| R | 重气体 | 下沉，沿地面/水面铺开 | 锈红 |
| G | 中性气体 | 随风横流 | 亮青 |
| B | 轻气体 | 上升，聚在天花板 | 亮黄 |

两个字段各用一对 HDR `SubViewport` 做 ping-pong（Vulkan 禁止同一张纹理既当 framebuffer 又当 uniform）。`Atmosphere` 负责收集房间里的 `GasVent`、组织 8px 固体 + 水体掩码（气体不会沉进水池），并把 hero 位置换算成**房间局部坐标**后送进 shader。

渲染仍由 `fog_layer.gdshader`：按三层密度加权混色、每层不同尺度的噪声、4×4 Bayer 抖动、最多 4 个点光按 `energy * pow(1 - d/r, 1.6)` 照亮。世界坐标来自 quad 的 UV，**不要改回 `VERTEX + 偏移`**（片元里 `VERTEX` 不保证在局部空间）。

无 `RenderingDevice` 时退回 CPU `FogGrid`（仅 headless/预览用）。

## 气体调参

所有参数都在 `WorldRoot/Atmosphere`（模板预览里是 `PreviewOnly/Atmosphere`）：

| 参数 | 默认 | 作用 |
| :--- | :--- | :--- |
| `sim_hz` | 30 | **每秒步进次数（整体流速总开关）**，10–60 |
| `gas_wind` | (7, -1.5) | **水平风速，单位 px/s** |
| `gas_buoyancy` | (1.1, 0, 1.0) | 重/轻气体通过 ψ 产生的沉浮强度 |
| `gas_dissipation` | 0.6 | ψ 的衰减（越大涡旋越快消失） |
| `gas_diffusion` | 0.12 | 密度扩散 |
| `gas_refill` | 0.25 | 回填速度（越小尾迹留得越久） |
| `gas_ambient` | (0.28, 0.22, 0.32) | 三层气体的环境密度，越低越"通透" |
| `push_radius` | 34 | **hero 推开气体的半径，单位 px**（房间局部像素） |
| `push_strength` | 1.4 | hero 推开/抽稀气体的强度 |
| `heavy_color` / `neutral_color` / `light_color` | 锈红 / 亮青 / 亮黄 | 三层气体颜色 |
| `gas_alpha` | (0.5, 0.32, 0.4) | 每层的浓淡 |
| `base_alpha` / `light_alpha` | 0.6 / 0.9 | 未受光/受光时的整体透明度 |
| `noise_amount` | 0.45 | 絮状噪声强度 |
| `player_light_radius/energy` | 74 / 1.0 | hero 提灯 |

`push_radius` 的衰减是 `(1 - d/r)²`：以 hero 身体中心为圆心、`r` 像素内的气体被向外拖拽并按强度抽稀，留下尾迹而不是硬洞。

### 让气体流得更快

- **横向更快**：`gas_wind` 从 `(7, -1.5)` 调到 `(24, -4)`，约 3 倍速（px/s，线性）。
- **整体更快**：`sim_hz` 30 → 45/60；每步仍是 2 个 pass，代价很小。
- **羽流更有力**：调大 `gas_buoyancy`（红气下沉/黄气上升），或调大喷口的 `jet_speed` / `rate`。
- **hero 尾迹更明显**：`push_strength` 1.4 → 2.2；`push_radius` 34 → 44。
- **更通透、少雾蒙蒙**：降低 `gas_ambient` 与 `base_alpha`，同时调大喷口 `rate`，让颜色来自羽流而不是环境底雾。
- **稳定性**：单步位移要小于一格（4px），即 `gas_wind / sim_hz <= 4`；30Hz 上限约 120px/s，60Hz 下 240px/s。

## 性能

实测（GTX 1650，320×180 房间，window 1280×720，120fps 上限）：

| 项目 | 旧（CPU 密度雾） | 新（GPU 不可压气体） |
| :--- | :--- | :--- |
| 气体单步 CPU 时间 | 1.8–1.9 ms | **0.044 ms**（2 个 pass 的提交） |
| 每秒步进 | 30 | 30–60（`sim_hz`） |
| 帧时间 p95 / p99 / max（气体开） | 8.73 / 17.39 / 18.56 ms | 8.52 / 16.40 / 16.81 ms |
| 帧时间 p95 / p99 / max（气体关） | 8.51 / 8.63 / 8.81 ms | 8.46 / 8.95 / 9.23 ms |

CPU 侧开销基本消失。120fps（8.33ms 预算）下仍有约 1% 的帧因为气体渲染/步进掉一帧；把视频设置的帧率上限设为 60（预算翻倍）就没有可见抖动。

## 重新生成房间与截图

```powershell
godot --headless --path . -s res://tools/build_water_room.gd
godot --headless --path . -s res://tools/build_gas_lab.gd
```

两个房间都是生成器铺出来的独立场景（不继承模板），重跑会覆盖编辑器里对源场景的改动；改布局请改生成器。

截图（会打开窗口，自动保存到 `docs/design/`）：

```powershell
godot --path . --quit-after 700 res://tools/gas_capture.tscn
godot --path . --quit-after 600 res://tools/water_capture.tscn
```

## 测试

```powershell
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_water_simulation.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_water_buoyancy.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_atmosphere_fog.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_atmosphere_settings.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_water_room_contract.gd
```

五个测试也都在 `tests/runtime_suite.gd` 里。

## 已知限制

- 一维水模型不模拟密闭管道；水面被水花顶过池沿不会继续外溢。
- 池底按 `SolidTiles` 自下而上扫描，顶部悬空平台不影响结果，但"悬空的水"无法表达。
- 瀑布是按水面落差生成的视觉层，不参与流体计算。
- 气体的"不可压"来自 `curl(ψ)`：喷流和 hero 推力是局部的散度源，只在喷口/身体附近破坏严格不可压；这不是完整的 Navier–Stokes（没有压力投影与涡量方程），但视觉上不会出现密度堆积。
- 水体掩码按 8px 瓦片刷新（每 0.25s），水面变化的那几帧最多有 8px 的气体/水交界面误差。
- 无 `RenderingDevice` 时退回 CPU 气体（仅 headless/预览用），外观是单色雾。
