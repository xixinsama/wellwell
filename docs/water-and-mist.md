# 水池与气体

两个演示房间：

- `water_hall`：两个水池、闸门、瀑布，加上三层气体。
- `gas_lab`：左墙三个喷口（每种气体一个）不断喷气，三排阶梯平台供 hero 站上去观察分层。

水与气体都是**房间扩展**（`WorldSession.register_room_extension`），和 `FogOfWar`、`CrumbleRuntime` 同构：进房 `bind_room_with_origin()`，换房 `clear_room()`。

- 水：`addons/fluid_kit/runtime/water/`
- 气体：`addons/fluid_kit/runtime/gas/`（`gas_sim.gd` 调度 Navier-Stokes 管线，4 个 shader：`gas_velocity` / `gas_pressure` / `gas_project` / `gas_density`，渲染在 `fog_layer.gdshader`）
- 气体喷口：`addons/fluid_kit/runtime/gas/gas_vent.gd`
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
- 三排平台自左下向右上排布（tile 行 18 / 15 / 12，跨 3..12、15..24、27..36），层间 24px。
- 房间用 `FogZone(Light)` 覆盖，探索雾不会压暗气体。

| GasVent 参数 | 默认 | 作用 |
| :--- | :--- | :--- |
| `channel` | Neutral | 喷哪种气体（Heavy / Neutral / Light） |
| `direction` | (1, 0) | 喷口朝向（指向房间内） |
| `radius` | 22 | 作用半径（px） |
| `rate` | 3.2 | 每秒注入的密度 |
| `jet_speed` | 460 | 喷流加速度（px/s²），会推动周围气体 |

## 气体效果演示（三个场景）

`addons/fluid_kit/demos/gas_effects_demo.tscn`：窗口运行，循环播放三个场景。

| 场景 | 怎么做的 | 演示场景 |
| :--- | :--- | :--- |
| 气体快速喷出 | `refresh_vents()` 把三个喷口的 `rate`×4、`jet_speed`×3 后重新收集 | 同上 |
| 某点爆炸 | `trigger_explosion()`：一次性径向冲量 + 密度闪光，0.18s 内淡出 | 同上 |
| 柱子扫动湍流 | `set_gas_mover()`：8×32px（1×4 格）竖柱左右扫过羽流，拖动并排开气体 | 同上 |

三个效果也可以直接放进游戏：给任意实体挂一个 `GasInteractor`（Push / Emit / Blast 三种模式），或调用 `Atmosphere` 的运行时 API。

运行时的 `Atmosphere` API：

```gdscript
# 以世界坐标触发一次爆炸
atmosphere.trigger_explosion(world_position, 34.0, 190.0, 1.1)
# 一个移动障碍物（中心、半尺寸、速度，都是世界坐标 / px/s）
atmosphere.set_gas_mover(world_center, Vector2(4.0, 16.0), world_velocity)
atmosphere.clear_gas_mover()
# 改了 GasVent 的 rate / jet_speed 之后让模拟重新读取
atmosphere.refresh_vents()
```

爆炸的冲量进入速度场后由压力投影变成无散的向外冲击 + 涡环；柱子的 `mover` 是**气体里的力区域**（拖动 + 排开 + 在它内部把气体挖空），不是 mask 里的实心障碍，所以它不会和 hero 碰撞。要真正的实心移动障碍，需要每步重建 mask 再上传，成本更高。

## 气体尾迹实验室（消散）

`gas_trail` 房间：**初始没有任何气体**，一个 1×1 格（8×8 px）的实体沿 150×78 的正方形路径循环行走，每帧在自身位置注入气体、并给这股气体一个**向后**的初速度，于是拖出一条尾迹；尾迹随时间逐渐消散。

- **消散**：密度 shader 里的 `decay` 项 `density *= max(0, 1 - decay * delta)`，按秒指数衰减；房间用 `refill = 0` 不再补气，所以只剩"旧气变淡"。
- **无初始气体**：房间里的 `GasField` 标记（`ambient = 0`）在 `Atmosphere` 绑定时覆盖全局 `gas_ambient`。
- **尾迹**：`GasTrailWalker` 每帧调用 `atmosphere.set_gas_emitter(位置, 半径, 速率, -方向 * 后退速度, 通道)`；速度 shader 在发射半径内把气体速度混合到那个向后速度，所以尾迹落在实体身后而不是跟着它走。

| GasField 参数 | 默认 | 作用 |
| :--- | :--- | :--- |
| `ambient` | (0,0,0) | 房间初始气体密度；全 0 就是空房间 |
| `decay` | 0.5 | 每秒指数衰减（0.5 ≈ 1.4s 半衰期） |
| `diffusion` | 0.25 | 扩散 |
| `refill` | 0.0 | 回填速度（0 = 不补气） |

| GasTrailWalker 参数 | 默认 | 作用 |
| :--- | :--- | :--- |
| `square_size` | (150, 78) | 正方形路径边长（px） |
| `speed` | 70 | 行走速度（px/s） |
| `emit_radius` | 13 | 注气半径（px） |
| `emit_rate` | 6.0 | 每秒注入密度 |
| `backward_speed` | 105 | 尾迹初速度（px/s，方向与行走相反） |
| `channel` | Neutral | 尾迹用哪种气体 |

运行：`addons/fluid_kit/demos/gas_trail_demo.tscn`。

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

渲染一张 quad：每列一个 texel 存"水面高度 + 池底高度"，shader 逐像素判断水下并画分层水色、1px 亮边、泡沫与水下光斑。溢流口不再用独立瀑布贴图，也不用粒子：每一处落差画一根**水柱 quad**（`water_fall.gdshader`，池水同色、带向下流动的水纹和底部泡沫）。最多 4 处落差各有一根；位置在堰口之后的开放列里、宽度最多两个格子，所以不会压到碰撞体；高度就是上下两个水面的真实落差。水量本身仍由高度场瞬时守恒地转移。

| WaterField 参数 | 默认 | 说明 |
| :--- | :--- | :--- |
| `max_depth` | 64 | 单列最大水深（px） |
| `flow_rate` | 54 | 列间传输系数；稳定上限是 `SIM_HZ / 2` |
| `splash_radius_base/scale` | 8 / 10 | 入水扰动半径 |
| `waterfall_min_drop` | 5 | 多大的落差才画落水柱（px）；最多同时画 4 处 |

水面高度纹理每 30Hz 上传一次（模拟仍是 120Hz）；上传会强制 GPU 同步，持续流动的三池级联在 60fps 下也能保持稳定。

## hero 在水里

`PlayerWaterMotion` 与 `LadderMotionComponent2D` 同一套组合方式：`PlayerController` 先问它，接管则跳过梯子和马达。

- 浮力按浸没比例生效，平衡点约 54% 身体在水下。
- 左右可游、上/下主动上浮下潜、贴水面按跳跳出。
- 入水瞬间按竖直速度追加下沉冲量并请求水花；速度越大沉得越深、水花越大。
- 水流会横向推动 hero；重生/锁定控制时复位。

## 气体模型：完整 2D Navier-Stokes（GPU）

按 Stam 的 *Stable Fluids* / GPU Gems 38 实现，每个固定步依次执行：

```
u*  = advect(u) + f·dt        半拉格朗日自平流 + 外力（浮力/喷流/hero 推力）
u*  = mix(u*, avg(4邻域))     粘滞扩散（gas_viscosity，显式、带稳定钳制）
div = ∇·u*                     散度（后向差分）
p   = solve(∇²p = div)         压力泊松，Jacobi 迭代（默认 16 次，热启动）
u   = u* - ∇p                  投影，得到无散速度（不可压）
d   = advect(d, u) + 源/汇     三层密度作为被动标量
```

每个 pass 独占一个 HDR `SubViewport`，只采样别的 viewport（Vulkan 不允许同一张纹理既当附件又当 uniform）。整条链在场景树里按 pass 顺序创建，渲染器按依赖顺序执行。

**离散一致性**：散度用**后向差分**、投影用**前向差分**——两者复合正好等于 Jacobi 求解的紧凑五点拉普拉斯算子，所以投影后的离散散度严格为 0（中心差分对会留下 O(1) 残差，实测只能消掉约 1/3）。solid 格速度置 0（不可穿透），压力在墙边取中心值（零梯度），壁面邻近格会保留少量残差，这是无通量边界的正常表现。

**压力求解**：默认 16 次 Jacobi + 上一帧收敛压力作为初始猜测（`gas_copy.gdshader` 保存）。实测 16 次与 200 次的压力场几乎相同，说明已收敛，再增加迭代没有收益；`pressure_iterations` 仍可调。

**验证**：在气体实验室采样投影后的速度场（排除墙壁/平台邻近格），散度从 `mean|div(u*)| = 0.049` 降到 `mean|div(u)| = 0.0036`（**消除 92.7%**），相对速度尺度（mean|v| ≈ 4.3 cells/s）约 0.1%。

| 通道 | 气体 | 行为 | 颜色 |
| :--- | :--- | :--- | :--- |
| R | 重气体 | 下沉，沿地面/水面铺开 | 锈红 |
| G | 中性气体 | 随风横流 | 亮青 |
| B | 轻气体 | 上升，聚在天花板 | 亮黄 |

浮力作为**力**进入速度场（`gas_buoyancy`，单位 px/s²），再由投影转成无散的旋转/羽流，所以红气不是"掉下去堆起来"，而是下沉后沿地面铺开、被卷回。密度只被速度搬运，扩散/回填只是低速的源汇，不参与压力求解。

渲染由 `fog_layer.gdshader` 完成：按三层密度加权混色、每层不同尺度的噪声、4×4 Bayer 抖动、最多 4 个点光按 `energy * pow(1 - d/r, 1.6)` 照亮。世界坐标来自 quad 的 UV，**不要改回 `VERTEX + 偏移`**。

无 `RenderingDevice` 时退回 CPU `FogGrid`（仅 headless/预览用）。

## 气体调参

所有参数都在 `WorldRoot/Atmosphere`（模板预览里是 `PreviewOnly/Atmosphere`）：

**默认房间里没有气体**：`gas_ambient = (0, 0, 0)`、`gas_refill = 0`，`Atmosphere` 绑定时只铺一层空场，整间房的"雾蒙蒙"效果已经去掉。可见的气体由 `GasVent` 喷嘴喷出（实测 light_lab：喷口 60px 内密度 0.7–1.0，全屏只有 ~7% 的格子密度够到可见阈值）。想要旧的雾感，给房间放一个 `GasField` 标记并把 `ambient` 调回 (0.28, 0.22, 0.32)，或者直接改 `gas_ambient`。

| 参数 | 默认 | 作用 |
| :--- | :--- | :--- |
| `sim_hz` | 30 | **每秒步进次数（整体速度总开关）**，10–60 |
| `pressure_iterations` | 16 | 每步压力 Jacobi 迭代次数（4–64） |
| `gas_wind` | (7, -1.5) | **水平风速，单位 px/s**（叠加在无散速度上，仍是不可压的） |
| `gas_buoyancy` | (240, 0, 300) | 重/轻气体的浮力加速度（px/s²） |
| `gas_dissipation` | 0.4 | 速度耗散（1/s），越大羽流越快平息 |
| `gas_viscosity` | 0.0 | **粘滞系数**（1/s）：气体越"稠"，羽流越缓、越圆滑；显式扩散，超过 ~10 会像糖浆 |
| `gas_decay` | 0.12 | **指数消散**（1/s），0.5 ≈ 1.4s 半衰期；喷口气体靠它慢慢散掉而不是积成雾 |
| `gas_diffusion` | 0.25 | 密度扩散 |
| `gas_refill` | 0.0 | 回填速度（把密度拉回 `gas_ambient`；只有非零 ambient 时才有意义） |
| `gas_ambient` | (0, 0, 0) | 三层气体的环境密度；**默认 0 = 房间里没有气体雾**，只留 `GasVent` 喷嘴喷出的气体 |
| `push_radius` | 34 | **hero 推开气体的半径，单位 px**（房间局部像素） |
| `push_strength` | 1.4 | hero 推力强度 |
| `heavy_color` / `neutral_color` / `light_color` | 锈红 / 亮青 / 亮黄 | 三层气体颜色 |
| `gas_alpha` | (0.5, 0.32, 0.4) | 每层的浓淡 |
| `base_alpha` / `light_alpha` | 0.6 / 0.9 | 未受光/受光时的整体透明度 |
| `noise_amount` | 0.45 | 絮状噪声强度 |
| `player_light_radius/energy` | 74 / 1.0 | hero 提灯 |

`push_radius` 的衰减是 `(1 - d/r)²`：以 hero 身体中心为圆心、`r` 像素内的气体被向外拖拽并按强度抽稀，留下尾迹而不是硬洞。

### 让气体流得更快

- **横向更快**：`gas_wind` 从 `(7, -1.5)` 调到 `(24, -4)`，约 3 倍速（px/s，线性）。
- **整体更快**：`sim_hz` 30 → 45/60；每步仍是 20 个 pass（16 次压力 + 4 个场 pass）。
- **羽流更有力**：调大 `gas_buoyancy`（红气下沉/黄气上升），或调大喷口的 `jet_speed` / `rate`。
- **hero 尾迹更明显**：`push_strength` 1.4 → 2.2；`push_radius` 34 → 44。
- **更通透、少雾蒙蒙**：降低 `gas_ambient` 与 `base_alpha`，同时调大喷口 `rate`。
- **稳定性**：单步平流位移要小于一格（4px），即 `gas_wind / sim_hz <= 4`；30Hz 上限约 120px/s，60Hz 下 240px/s。

## 性能

实测（GTX 1650，320×180 房间，window 1280×720，120fps 上限，80×45 网格，20 pass/步）：

| 项目 | 旧（CPU 密度雾） | 新（GPU Navier-Stokes） |
| :--- | :--- | :--- |
| 气体单步 CPU 时间 | 1.8–1.9 ms | **0.062 ms**（20 个 pass 的提交） |
| 每步 GPU pass | — | 16 压力 + 平流/投影/密度/拷贝 = 20 |
| 帧时间 p95 / p99 / max（气体开） | 8.73 / 17.39 / 18.56 ms | 8.75 / 15.74 / 16.19 ms |
| 帧时间 p95 / p99 / max（气体关） | 8.51 / 8.63 / 8.81 ms | 8.42 / 8.46 / 8.54 ms |

CPU 侧开销基本消失；120fps 下约 1% 的帧掉一帧，把帧率上限设 60 就没有可见抖动。

## 重新生成房间与演示

```powershell
godot --headless --path . -s res://tools/build_water_room.gd
godot --headless --path . -s res://tools/build_gas_lab.gd
godot --headless --path . -s res://tools/build_gas_trail.gd
```

三个房间都是生成器铺出来的独立场景（不继承模板），重跑会覆盖编辑器里对源场景的改动；改布局请改生成器。

演示场景（可直接 F6 运行，不再往项目里保存图片）：

- `addons/fluid_kit/demos/water_demo.tscn`
- `addons/fluid_kit/demos/gas_plumes_demo.tscn`
- `addons/fluid_kit/demos/gas_effects_demo.tscn`
- `addons/fluid_kit/demos/gas_trail_demo.tscn`

插件说明（参数、交互实体、生成方式）：`addons/fluid_kit/README.md`。

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
- 落水柱是按水面落差生成的水体渲染（池水同色），水量本身由高度场转移；水柱宽度限制在开放列内，最多两个格子。
- 气体压力求解器是 Jacobi（16 次 + 热启动）。开放区域散度消除 92.7%，但**壁面邻近格保留残差**（无通量边界的正常结果）；要更严格的不可压可以加多重网格，代价是更多 pass。
- 密度不是守恒量：环境回填、喷口注入、hero 抽稀都是源汇，这是为了游戏可读性（房间不会把气抽空），不是严格的质量守恒。
- 水体掩码按 8px 瓦片刷新（每 0.25s），水面变化的那几帧最多有 8px 的气体/水交界面误差。
- 无 `RenderingDevice` 时退回 CPU 气体（仅 headless/预览用），外观是单色雾。
