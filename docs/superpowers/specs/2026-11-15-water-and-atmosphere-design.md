# 水与雾气：设计

日期：2026-11-15
状态：已确认，进入实现

## 1. 目标

在 `wellwell`（Godot 4.7，320×180 像素平台游戏）里加入两套流体效果，并保证它们在
像素分辨率下够好看、够便宜：

1. 一个真实房间里有左右两个水池；进入房间后，高位池的水经溢流口流进低位池。
2. hero 能浮在水面上。
3. hero 入水的下沉深度、水面隆起高度和水花大小，随下落速度变化。
4. 空气里弥漫着可以被 hero 扰动、留下尾迹又缓慢回填的雾。
5. 雾受光源影响：hero 提灯与房间静态光会把雾照暖、照亮，暗处雾偏冷偏暗。

约束：像素风格；不引入逐格节点、常驻粒子和重型 2D 光照；所有逻辑可 headless 测试。

## 2. 需求与方案映射

| 需求 | 实现 |
| --- | --- |
| 1 两池流动 | 一维浅水高度场（4px 列）+ 通量守恒 + 溢流口/闸门 |
| 2 浮在水面 | 玩家侧 `PlayerWaterMotion`：浮力弹簧 + 阻尼 + 游泳输入 |
| 3 入水差异 | 入水速度 → 初始下沉冲量、局部水位隆起、水花档位、相机震动 |
| 4 可扰动雾气 | 8px 密度/速度场，hero 半径内排斥并挖空，离开后回填 |
| 5 雾受光照 | 最多 8 个点光，shader 内距离衰减，与 CPU 侧 `sample_light` 同公式 |

## 3. 架构与边界

依赖方向保持 `game → scripts/world → 无`，不修改 `addons/platformer_kit` 的行为契约。
新增系统通过已有的 `WorldSession.register_room_extension()` 接入，与 `FogOfWar`、
`CrumbleRuntime` 完全同构（`bind_room_with_origin` / `clear_room` / `bind_player`）。

新增文件：

```
scripts/world/water/
  water_simulation.gd     RefCounted，纯一维流体核心（可测试）
  water_field.gd          Node2D，房间扩展：地形采样、模拟驱动、渲染、水花
  water_basin.gd          @tool 标记：池范围与初始水位（编辑器预览）
  water_gate.gd           @tool 标记：闸门，进房延时开启
  water_surface.gdshader  高度纹理 → 水体分层、亮边、泡沫
scripts/world/atmosphere/
  fog_grid.gd             RefCounted，纯雾场核心（可测试）
  atmosphere.gd           Node2D，房间扩展：实心掩码、光源、渲染
  fog_light.gd            @tool 标记：静态光源
  fog_layer.gdshader      密度纹理 + 像素噪声抖动 + 点光散射
game/player/player_water_motion.gd
game/water/effects/water_splash.gd
tools/build_water_room.gd
scenes/levels/test/water_hall.tscn
```

修改的既有文件：`scenes/player/player.tscn`（挂 WaterMotion）、
`scripts/player/player_controller.gd`（组合水运动，方式同 `LadderMotion`）、
`scenes/runtime/world_root.tscn` + `scripts/app/main.gd`（注册两个房间扩展）、
`scenes/rooms/template/level_template.tscn` + `room_preview_controller.gd`（编辑器预览）、
`tests/runtime_suite.gd`（注册测试）、`resources/worlds/test_world.tres`（加入房间）。

## 4. 水

### 4.1 一维浅水模型（WaterSimulation）

- 每个 4px 列保存 `mass`（px²）、`floor_y`、`blocked`、波动 `offset/offset_velocity`。
- 深度 `depth = mass / column_width`，水面 `surface_y = floor_y - depth - offset`。
- 相邻列按水面高差转移体积：`q = flow_rate * (surface_i - surface_j) * width * dt`，
  受 `max_flow_speed`、源列一半存量、目标列剩余容量三重夹取；先算完所有通量再统一
  应用，保证总体积精确守恒且与遍历顺序无关。
- 波动层是纯视觉弹簧：向平衡位回归 + 邻列耦合 + 阻尼，静止时归零。
- 早期退出：不脏、无通量、无波动时 `step()` 直接返回（这是主要优化）。
- 池底高度由 `SolidTiles` 自下而上扫描得到：一个列的最低连续实心堆顶部即池底；整列
  实心即墙（不可蓄水、阻断通量）；顶部悬空平台不影响结果。溢流口就是"该列表面的
  池底更低"的列，水超过它自然溢出。闸门通过 `set_blocked()` 临时把溢流列标为墙。

### 4.2 房间扩展（WaterField）

- `bind_room_with_origin()` 时：找房间内 `water_basin` / `water_gate` 组节点，按池范围并集
  确定横向范围，扫描地形生成列，按 `initial_depth` 注入初始水量。
- 固定 60 Hz 更新（120 Hz 物理下每两帧一次），房间卸载时 `clear_room()` 复位。
- 渲染：一列一个 texel 的 RGBA 纹理（R=水面高度、G=池底高度，归一化到 0..1），
  单张 quad 的 shader 逐像素判断水下并着色；水面只在水体存在处绘制。
- 溢流处按通量阈值驱动一张瀑布动画 quad 与落点水花，避免一维模型画出悬空水柱。

### 4.3 玩家（PlayerWaterMotion）

组合方式与 `LadderMotionComponent2D` 一致：`step(context, intent, environment, profile, delta)`
返回是否接管本帧运动；`PlayerController` 在梯子之前调用它。

- 浸没比例 = 身体与水面重叠高度 / 身高。
- 浮力：`accel = buoyancy * submerged - drag * v`，上限为浮出水面后的自然跳起。
- 游泳：左右加速；上/下主动上浮/下潜；贴近水面按跳可跳出水面。
- 入水帧：按竖直速度计算初始下沉速度（速度越大沉得越深）、调用
  `WaterField.splash(x, speed)`、贴近水面时允许水面跳。
- 水流：叠加 `WaterField.get_flow_velocity_at(x)` 的横向推力。
- `respawn_at()` / `set_control_locked()` 时由控制器调用 `reset()`。

### 4.4 水花与反馈

- `water_splash.gd` 用 PixelFX BAKED 管线生成像素水花（复用现有角色特效的渲染路径），
  按速度分小/中/大三档：粒子数、初速、弧高、寿命随档位提升。
- 同时向模拟注入 `add_splash(volume, wave_impulse)`：局部水面隆起再振荡回落，形成
  "不同高度的变化"。
- 大档位触发 `PixelCamera2D.add_shake()`；水面出现短暂泡沫亮线。

## 5. 雾

### 5.1 密度/速度场（FogGrid）

- 8px 网格，密度与速度存在 `PackedFloat32Array`，30 Hz 更新。
- 每步：环境目标密度（hash 噪声缓慢起伏）→ hero 排斥与挖空 → 半拉格朗日平流 →
  扩散 → 速度阻尼 → 向目标回填 → 夹取到 [0,1]。
- 实心格掩码来自 `SolidTiles`，实心格密度恒为 0，雾不会进墙。
- 活跃判定与脏矩形：hero 静止且场稳定时跳过整步；渲染只上传变化子矩形。

### 5.2 光照

- 光源 = hero 提灯（跟随玩家）+ 房间内静态 `fog_light`（颜色/半径/强度/轻微闪烁）。
- shader 逐像素求 `sum(energy * pow(1 - d/radius, 1.6))`，同一公式在
  `FogGrid.sample_light()` 里实现供测试与调试；两处必须保持同步（代码注释标明）。
- 雾颜色 = 暗部冷色 ↔ 光部暖色的混合；光越强 alpha 越高，形成局部散射光晕。

### 5.3 渲染

- 单张覆盖房间的 quad，采样 8px 密度 texel，叠加两层缓慢流动的像素噪声与 Bayer 抖动，
  打散网格感；不新建任何逐格节点。
- 绘制顺序：角色之上、`FogOfWar` 之下，保证未探索区域仍然是黑的。

## 6. 房间与接入

- `water_hall` 为 `test_world` 中的真实房间（源场景 → `RoomBaker` 烘焙 → 生成
  `runtime.tscn`/`terrain.tscn`/`RoomData`），通过 `RoomEntrance` 与本世界其他房间连通。
- 房间布局：左上高位水箱（初始水位高）→ 中间溢流口 + 闸门 → 右下低位深池；
  进入房间 0.8 s 后闸门升起，水落下并逐渐使两池水位稳定；顶部有 2 个静态光源。
- 房间由 `tools/build_water_room.gd` 生成源场景（程序化铺砖），避免手改二进制
  `tile_map_data`；烘焙后提交生成物。
- `test_world` 的入口调整到 `water_hall`，让"进入房间"即可看到效果，同时保留通往
  原有雾/暗区测试房的连接。
- `world_root.tscn` 挂 `WaterField` 与 `Atmosphere` 并由 `main.gd` 注册；房间模板的
  `PreviewOnly` 也挂一份并由 `RoomPreviewController` 绑定，方便在编辑器里预览。

## 7. 性能预算

- 水：≤ 82 列 / 屏，60 Hz，活跃时约 5k 次列运算/秒；静止时 0。渲染 1 个 pass + 1 次
  纹理上传（≤ 82 texel）。
- 雾：≤ 40×23 = 920 格，30 Hz；静止时 0。渲染 1 个全屏 pass（320×180）+ 1 次小纹理上传。
- 水花：短命 PixelFX 特效，播完释放；无常驻粒子。
- 不使用 `Light2D` / `CanvasModulate`：不改动全局观感，也不需要法线与遮光体。

## 8. 错误处理与已知限制

- 房间无地形、无水池、无玩家：系统静默禁用，不报错不崩溃。
- 一维模型不模拟密闭管道压缩空气；水面被水花顶过池沿不会继续外溢。
- 房间切换/重生：清除水花与游泳状态，闸门与水位回到初始值。
- 雾在实心格内恒为 0；`FogOfWar` 关闭时本系统不受影响。

## 9. 测试

新增 headless 测试并注册进 `tests/runtime_suite.gd`：

- `tests/world/test_water_simulation.gd`：守恒、闸门开闭、两池平衡、水花衰减、容量夹取、早退。
- `tests/world/test_water_buoyancy.gd`：浸没上浮到水面、入水速度影响下沉深度、水面跳出。
- `tests/world/test_atmosphere_fog.gd`：扰动、尾迹、回填、实心格、光照单调性、早退。
- `tests/world/test_water_room_contract.gd`：房间契约、烘焙产物存在、世界引用一致。

另跑完整 `tests/run_runtime_suite.gd`、`tools/validate_project.gd`、
`tools/validate_framework_boundaries.gd`。

## 10. 交付

- 代码与测试如上。
- `docs/water-and-mist.md`（中文使用/调参/限制说明）+ `docs/extension-guide.md` 补一节。
- 房间截图若干（水面、入水水花、雾气扰动、灯光）。
