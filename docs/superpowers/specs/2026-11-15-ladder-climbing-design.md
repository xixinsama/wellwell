# 楼梯自由攀爬、连续跳跃与 Hero 动画设计

**日期：** 2026-11-15

**分支：** `level0`

**状态：** 更新设计已确认，等待最终文档审阅

## 1. 目标与范围

在 `wellwell` 模板中完善楼梯和 Hero 表现：玩家进入楼梯 Area 后可以上下左右自由移动且不受重力，可以连续跳跃快速向上；W/S 分别向上、向下爬并播放 climb 动画；S + 跳跃退出攀爬并持续快速落地。

用户已在 `resources/tilesets/primordial_tileset.tres` 添加源坐标 `(0,7)`：备选 0 为原始样式，备选 1 使用 transpose。两者都没有实体碰撞多边形。`room_01_00.tscn` 中已有用户放置的楼梯瓦片。

Hero 资产来自用户指定的 `D:\Godot4\GodotProject\wellwell-b\assets\generated\hero.png`。源图为 80×100，Hframes = 8、Vframes = 10，因此每帧为 10×10。实现时复制到项目的 `assets/generated/hero.png`，不修改源项目资产。

不修改普通地面移动、土狼时间、跳跃缓冲、Dash、碰撞参数、已有地图布局或调试系统。

## 2. 已确认方案

采用“独立攀爬组件 + 瓦片自动建区域 + AnimatedSprite2D 动画驱动”。

- `LadderMotionComponent2D` 负责区域检测、攀爬速度、连续跳跃、快速下落选择和动画事件。
- `LadderZone` 只提供触发区域，不包含角色移动逻辑。
- `LadderTileAreaBuilder` 把 `(0,7)` 的任意备选瓦片自动转换为 `LadderZone`。
- 普通 `CharacterMotor2D` 保持现有地面与空中规则，只有不使用攀爬控制时才执行。
- `HeroAnimationController` 使用独立状态优先级驱动 `AnimatedSprite2D`，不把动画分支堆进角色移动控制器。

不采用把楼梯强行并入 grounded 的方案，也不为本帧图引入 AnimationPlayer 骨骼/镜头系统。

## 3. 文件与职责

### 3.1 可复用 Platformer Kit 组件

- `addons/platformer_kit/character/ladder/ladder_motion_component_2d.gd`
  - 创建与玩家碰撞形状一致的检测 Area。
  - 只接受 `ladder_zone` 组，忽略其他 trigger。
  - 在普通 Motor 之前决定本帧由攀爬处理还是交给普通 Motor。
  - 发出动画状态事件并提供区域状态查询。
- `addons/platformer_kit/world/entities/ladder_zone.gd/.tscn`
  - 默认 8×8 Area，加入 `ladder_zone` 组，使用 trigger 层值 4，不阻挡角色。

### 3.2 输入与调校

- `character_intent.gd` 新增 `vertical_axis := 0.0`，默认输入源继续返回 0，兼容现有测试和 AI 输入。
- `player_input_source.gd` 新增 `move_up_action`、`move_down_action`，默认分别为 `move_up`、`move_down`，用 `Input.get_axis()` 生成垂直轴。
- `movement_profile.gd` 新增导出 `climb_speed := 72.0`，由 `PlayerTuning` 继承，不要求修改现有 `.tres`。
- 普通 `fast_fall` 仍读取 `move_down`；S 单独按下在楼梯内表示向下爬，只有 S + 跳跃形成的下落锁存才强制快速下落。

### 3.3 游戏瓦片接入

- `scripts/world/ladder_tile_area_builder.gd`
  - 放在 `RoomContent/Terrain/LadderAreaBuilder`，运行时扫描同级所有 TileMapLayer。
  - 匹配 `source_id == 0` 且 `get_cell_atlas_coords() == Vector2i(0,7)` 的单元格。
  - 不检查备选 ID，因此原始、transpose 和后续翻转备选共享行为。
  - 按 `map_to_local()` 和 TileSet 单元格尺寸创建区域，正确处理图层与扫描器的全局变换。
  - 不作为 `@tool` 在编辑时生成节点，避免把运行时区域写入源场景或烘焙资源。
- `scenes/rooms/template/level_template.tscn`
  - 只追加扫描器脚本引用和节点，保留已有调试内容。

完成后通过现有 RoomBaker 流程重新烘焙 `room_01_00`，不手工编辑生成场景，不批量重写其他房间。

### 3.4 Hero 资产与动画驱动

- `assets/generated/hero.png`：用户提供的 80×100 帧图，使用最近邻采样。
- `resources/player/hero_sprite_frames.tres`：按 10×10 网格定义全部 20 帧和动画。
- `game/player/hero_animation_controller.gd`：根据移动、攀爬、输入方向、静止计时和朝向选择动画。
- `scenes/player/player.tscn`
  - 保留旧 Block/眼睛占位节点但隐藏，便于追溯，不再作为默认视觉。
  - 在 `SpriteRoot` 下新增 `HeroAnimation` 和 `AnimatedSprite2D`。
  - 新增 `LadderMotion` 节点，保留已有能力和粒子节点。

动画行映射固定为：

| 行 | 动画 | 帧数 | 建议播放 |
| --- | --- | --- | --- |
| 0 | `idle` | 2 | 2 fps 循环，呼吸 |
| 1 | `walk` | 4 | 8 fps 循环 |
| 2 | `run` | 4 | 12 fps 循环 |
| 3 | `jump` | 2 | 上升时播放并停在末帧；每次新跳跃重播 |
| 4 | `fall` | 2 | 6 fps 循环 |
| 5 | `climb` | 2 | 8 fps 循环 |
| 6 | `look_up` | 1 | 静止朝上 |
| 7 | `look_down` | 1 | 静止朝下 |
| 8 | `look_left` | 1 | 静止朝左 |
| 9 | `look_right` | 1 | 静止朝右 |

`AnimatedSprite2D` 以底部中心对准玩家脚底，10×10 帧下节点位置为 `(0,-5)`。原角色碰撞形状不变。

## 4. 区域检测与组件协作

攀爬组件创建一个 Area2D 检测区，复制玩家 `CollisionShape2D` 的形状与相对位置。检测区 mask 为 4，并筛选 `ladder_zone` 组，避免把存档点等其他 trigger 误认为楼梯。

每个物理帧的顺序为：

1. 获取玩家输入和环境快照。
2. 攀爬组件读取当前有效重叠区域。
3. 如果组件处理本帧，它直接写入 `MovementContext.velocity` 与 `just_jumped`，跳过普通 Motor。
4. 如果组件不处理本帧，控制器照常调用普通 Motor。
5. 后续能力覆盖、`move_and_slide()`、落地、粒子与动画状态更新沿用明确顺序。

楼梯中的角色通常不满足 `is_on_floor()`，因此不会误触跑步和落地灰尘；每次新跳跃仍使用现有跳跃反馈。

## 5. 已确认的移动规则

### 5.1 自由攀爬

- 有效区域重叠且未处于下落锁存时，进入自由攀爬控制。
- 无输入时 `velocity = Vector2.ZERO`，角色悬停，不应用重力。
- 水平与垂直输入共用 `climb_speed`；输入向量长度大于 1 时归一化，避免斜向加速。
- W 对应 `vertical_axis < 0`，向上爬；S 对应 `vertical_axis > 0`，向下爬并播放 climb。
- 不自动吸附到瓦片中心，不使用 `fast_fall`，也不要求 `is_on_floor()`。
- 自由攀爬期间旧 `jump_buffer_remaining` 与 `coyote_remaining` 保持为 0，避免离梯后触发残留旧跳跃。

### 5.2 区域内连续跳跃

- 每次新的 `jump_pressed` 且未同时按 S 时，设置 `velocity.y = profile.jump_speed`、清除跳跃缓冲和土狼计时，并设置 `context.just_jumped = true`。
- 新跳跃不要求落地，不消耗仅一次的空中跳跃次数。
- 持续按住跳跃且仍在上升时，按 `profile.gravity * delta` 推进上升速度，保留上升弧线。
- 上升过程中再次按下跳跃，会重新把垂直速度设为 `jump_speed`，实现连续跳跃快速攀爬。
- 松开跳跃后恢复自由攀爬；按 W 可继续爬升，无输入则悬停。
- 从空中跳入区域后，可以立即获得一次新的跳跃，不受进入前空中状态影响。

### 5.3 S + 跳跃持续快速落地

- S 单独按下只负责向下爬，不再直接退出攀爬。
- 在楼梯内同时按 S 和跳跃时，进入下落锁存：取消向上速度、清除本帧跳跃请求和跳跃计时，让普通 Motor 处理移动。
- 下落锁存期间强制 `fast_fall = true`，即使随后松开 S 或跳跃也继续快速下落，避免组合键只生效一帧。
- 锁存期间不进入自由攀爬，也不播放 climb；动画按 airborne 状态选择 jump/fall。
- 落地、离开所有楼梯区域、按 W 主动重新攀爬或重生时解除锁存。
- 落地后普通地面输入与跳跃规则恢复，不把锁存带到下一段楼梯。

### 5.4 离开、重生与控制锁定

- 离开所有楼梯区域后，下一物理帧恢复普通 Motor、重力和既有跳跃规则。
- 重生清除旧的跳跃、下落锁存、动画状态和静止计时，检测区在传送后重新计算重叠。
- `control_locked` 继续由控制器提前处理，不在锁定期间发出攀爬移动或动画推进；进入锁定时发送一次 `active = false` 并重置 Hero 为合适静止状态。

## 6. Hero 动画接口与优先级

`PlayerController` 保留公共接口：

```gdscript
signal climb_animation_requested(active: bool, direction: Vector2)
func is_on_ladder() -> bool
```

- `is_on_ladder()` 表示是否与有效楼梯区域重叠。
- `active = true` 表示自由攀爬状态，包括 W 上爬、S 下爬和无输入楼梯待机。
- `direction` 为归一化输入方向，无输入为 `Vector2.ZERO`。
- 新跳跃及持续跳跃上升、下落锁存、离开区域和重生时发出 `active = false`。
- 只有 active 或 direction 改变时才发信号，避免每帧重复触发。

HeroAnimationController 接收该状态和玩家移动快照，按以下优先级选择动画：

1. **自由攀爬且 W/S 有输入**：`climb`，不管竖直速度正负。
2. **离地或处于楼梯跳跃/下落锁存**：`velocity.y < 0` 用 `jump`，否则用 `fall`。
3. **地面按 W/S**：分别 `look_up`、`look_down`。
4. **实际水平移动**：速度达到 85 px/s 用 `run`，低于该阈值用 `walk`；只有输入但被墙挡住时不空播走路。
5. **静止不足 2 秒**：根据 facing 使用 `look_left` 或 `look_right`。
6. **静止达到 2 秒**：切换 `idle` 呼吸。

静止计时在任何有效方向输入、实际移动、跳跃、攀爬或状态切换时清零。楼梯内无 W/S 且没有跳跃时也参与同一静止计时，不会错误显示 fall。

普通循环动画通过 `AnimatedSprite2D.flip_h` 处理朝向；`look_left`、`look_right` 使用专门帧，不再翻转。`SpriteRoot.scale` 保持正 X，仅用于既有挤压恢复，避免与 look 帧发生双重翻转；`facing` 继续供移动、Dash 和粒子使用。

## 7. 异常与资源管理

- 没有有效区域时，攀爬组件完全交还普通 Motor。
- 非 `ladder_zone` 的 trigger 不参与检测。
- 扫描器跳过空 TileSet、非 TileMapLayer 子节点和其他坐标；重建时只清理自己生成的区域。
- 每块楼梯瓦片一个轻量 Area，不引入复杂区域合并。
- Hero 帧图复制后独立导入，不引用 `wellwell-b` 的绝对路径，保证项目可迁移。
- 缺帧或动画名称不匹配时由资源测试失败指出，不在运行时静默退回错误行。
- 用户的图片、TileSet、源房间和地图修改保持原样；已有未提交文件不会被整文件纳入本功能提交。

## 8. 测试与验收

### 8.1 楼梯单元与集成测试

新增 `tests/platformer_kit/character/test_ladder_motion.gd` 与 `tests/world/test_ladder_tiles.gd`，注册进运行时测试套件，并使用已有 `tests/run_test_script.gd` 单独运行。

覆盖：

1. 无输入悬停、上下左右速度、斜向归一化。
2. 新跳跃、连续跳跃重置、按住跳跃的上升重力、松开后恢复攀爬。
3. 跳跃进入区域后可再次跳跃，离开区域后恢复普通重力。
4. S 向下爬；S + 跳跃取消上升并持续快速下落；落地、离梯、W 和重生正确解除锁存。
5. 真实 Area 检测只接受 `ladder_zone`，其他 trigger 不误判。
6. 动画接口的 active/direction、去重和重生清理。
7. 原始备选 0、transpose 备选 1 都生成位置与尺寸正确的区域，其他坐标不生成。
8. 模板和 `room_01_00` 烘焙地形均包含扫描器，预览与运行时行为一致。

### 8.2 Hero 动画测试

新增 `tests/player/test_hero_animation.gd`：

- 20 个 AtlasTexture 帧的坐标、尺寸、行归属、帧数和循环设置正确。
- W/S 攀爬优先于普通 airborne；垂直速度正确选择 jump/fall，连续跳跃会重播 jump。
- 地面 W/S look、walk/run 阈值、朝向和 flip_h 正确，look 帧不翻转。
- 静止 2 秒才进入 idle，任意输入或移动会退出并重置计时。
- 楼梯无输入不会误选 fall，重生会清除旧动画和静止计时。
- 旧占位节点隐藏，新 Hero 精灵使用正确 SpriteFrames 和脚底锚点。

### 8.3 运行与回归验证

- 在 `room_01_00` 源场景按 F6，验证攀爬、连续跳跃、S 下爬、S + 跳跃快速落地和各行动画。
- 重新烘焙该房间并验证正式世界运行时结果一致。
- 运行现有 Motor、输入、粒子、Killzone、房间烘焙测试及完整套件。
- 已知的 `SavePoint/VisualRoot` 与 `Visual` 基线错误单独报告，不顺带修改。
- 检查最终 diff，确保没有改动用户瓦片内容、其他房间或无关系统。

## 9. 完成定义

- `(0,7)` 原始和横置备选瓦片在源房间及烘焙运行时都自动形成可用楼梯。
- 角色可自由攀爬、悬停、连续跳跃；W/S 正常上下爬，S + 跳跃可持续快速落地。
- Hero 使用用户提供的 10×10 帧图，动画优先级、方向、2 秒呼吸和连续跳跃重播符合设计。
- 公共攀爬动画接口保留，无外部绝对资源路径依赖。
- 新测试、相关回归测试和实际房间验证通过；完整套件不出现本功能新增失败。
