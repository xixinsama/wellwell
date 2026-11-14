# 楼梯自由攀爬与连续跳跃设计

**日期：** 2026-11-15

**分支：** `level0`

**状态：** 已确认设计，等待文档审阅

## 1. 目标与范围

在 `wellwell` 模板中完善楼梯功能：玩家进入楼梯 Area 后可以上下左右自由移动且不受重力，可以连续跳跃快速向上，也可以按住下结束攀爬并快速落地。横向外观的楼梯与竖向楼梯使用完全相同的移动规则。

用户已在 `resources/tilesets/primordial_tileset.tres` 添加源坐标 `(0,7)`：备选 0 为原始样式，备选 1 使用 transpose。两者都没有实体碰撞多边形，适合作为触发区域来源。`room_01_00.tscn` 中已有用户放置的楼梯瓦片。

本次只提供 Hero 攀爬动画接口，不制作动画资源。不修改普通地面移动、土狼时间、跳跃缓冲、Dash、碰撞参数、已有地图布局或调试系统。

## 2. 已确认方案

采用“独立攀爬组件 + 瓦片自动建区域”，而不是把楼梯强行并入普通 Motor 的 grounded 状态，也不要求每个房间手动重复摆放 Area。

- `LadderMotionComponent2D` 负责区域检测、攀爬速度、连续跳跃、快速下落选择和动画事件。
- `LadderZone` 只提供触发区域，不包含角色移动逻辑。
- `LadderTileAreaBuilder` 把 `(0,7)` 瓦片自动转换为 `LadderZone`，任意备选 ID 都接受。
- 普通 `CharacterMotor2D` 保持现有地面与空中规则，只有不使用攀爬控制时才执行。

## 3. 文件与职责

### 3.1 可复用 Platformer Kit 组件

- `addons/platformer_kit/character/ladder/ladder_motion_component_2d.gd`
  - 创建与玩家碰撞形状一致的检测 Area。
  - 只接受 `ladder_zone` 组中的区域，忽略存档点等其他 trigger Area。
  - 在普通 Motor 之前给出“本帧由攀爬处理”或“本帧使用普通 Motor”的选择。
  - 发出动画状态事件，并提供区域状态查询。
- `addons/platformer_kit/world/entities/ladder_zone.gd`
  - `Area2D` 标识组件，加入 `ladder_zone` 组。
  - 使用现有 trigger 碰撞层值 4，可被角色检测区识别，不阻挡角色。
- `addons/platformer_kit/world/entities/ladder_zone.tscn`
  - 默认 8×8 的矩形触发区，供扫描器和手动作者复用。

### 3.2 输入与调校

- `character_intent.gd` 新增 `vertical_axis := 0.0`，默认输入源继续返回 0，保持现有测试和 AI 输入兼容。
- `player_input_source.gd` 新增 `move_up_action`、`move_down_action`，分别默认为 `move_up`、`move_down`，用 `Input.get_axis()` 生成垂直轴。
- `fast_fall` 继续读取 `move_down`，普通离梯移动行为不变；攀爬组件只在区域内优先处理垂直输入。
- `movement_profile.gd` 新增导出 `climb_speed := 72.0`，供 `PlayerTuning` 继承，不要求修改现有 `.tres` 文件。

### 3.3 游戏瓦片接入

- `scripts/world/ladder_tile_area_builder.gd`
  - 放在 `RoomContent/Terrain/LadderAreaBuilder`。
  - 在运行时扫描同级所有 `TileMapLayer`。
  - 匹配 `source_id == 0` 且 `get_cell_atlas_coords() == Vector2i(0,7)` 的使用中单元格。
  - 不检查备选 ID，因此原始、transpose 和后续翻转备选共享行为。
  - 按瓦片地图的 `map_to_local()` 结果和 TileSet 单元格尺寸创建区域，并正确处理图层与扫描器的全局变换。
  - 不作为 `@tool` 在编辑时生成节点，避免把运行时区域误写入源场景或烘焙资源。
- `scenes/rooms/template/level_template.tscn`
  - 只追加扫描器脚本引用和 `LadderAreaBuilder` 节点，保留当前已有调试节点与设置。
- `scenes/player/player.tscn`
  - 追加 `LadderMotion` 节点，保留已有能力、粒子和角色内容。

完成实现后，通过现有 RoomBaker 流程重新烘焙用户修改过的 `room_01_00`。不手工编辑生成场景，不批量重写其他房间。

## 4. 区域检测与组件协作

玩家下的攀爬组件创建一个 Area2D 检测区，复制玩家 `CollisionShape2D` 的形状与相对位置。检测区 mask 为 4，并从重叠 Area 中筛选 `ladder_zone` 组，避免把其他 trigger 误认为楼梯。

每个物理帧的顺序为：

1. 获取玩家输入和环境快照。
2. 攀爬组件读取当前有效重叠区域。
3. 如果组件处理本帧，它直接写入 `MovementContext.velocity` 与 `just_jumped`，跳过普通 Motor。
4. 如果组件不处理本帧，控制器照常调用普通 Motor。
5. 后续能力覆盖、`move_and_slide()`、落地与粒子逻辑沿用现有顺序。

楼梯中的角色通常不满足 `is_on_floor()`，因此不会误触跑步和落地灰尘；每次新跳跃仍会使用现有跳跃反馈。

## 5. 已确认的移动规则

### 5.1 自由攀爬

- 只要有效区域重叠且未按住下，就进入自由攀爬控制。
- 无输入时 `velocity = Vector2.ZERO`，角色悬停，不应用重力。
- 水平与垂直输入共用 `climb_speed`；输入向量长度大于 1 时归一化，避免斜向加速。
- 不自动吸附到瓦片中心，因为需求明确允许区域内上下左右自由移动。
- 不使用 `fast_fall` 重力，也不要求 `is_on_floor()`。
- 自由攀爬期间将旧 `jump_buffer_remaining` 与 `coyote_remaining` 保持为 0，避免离梯后触发进入区域前残留的旧跳跃。

### 5.2 区域内连续跳跃

- 每次新的 `jump_pressed` 都设置 `velocity.y = profile.jump_speed`、清除跳跃缓冲和土狼计时，并设置 `context.just_jumped = true`。
- 新跳跃不要求落地，不消耗“仅一次”的空中跳跃次数；区域内没有此限制。
- 持续按住跳跃且仍在上升时，按 `profile.gravity * delta` 推进上升速度，保留普通跳跃的上升弧线。
- 上升过程中再次按下跳跃，会重新把垂直速度设为 `jump_speed`，因此可以连续跳跃快速攀爬很长的竖向楼梯。
- 松开跳跃后恢复自由攀爬；按住上可继续爬升，无输入则悬停。
- 从空中跳入区域后，可以立即获得一次新的跳跃，不受进入前的空中状态影响。

### 5.3 按住下快速落地

- `vertical_axis > 0.0` 时，向下输入优先于攀爬和区域内跳跃。
- 若垂直速度仍向上，先将其截为 0，再让普通 Motor 处理本帧。
- `move_down` 同时设置现有 `fast_fall`，所以角色立即进入普通重力和快速下落。
- 按住下期间不会重新进入攀爬；松开后若仍在区域内，可恢复自由攀爬。

### 5.4 离开、重生与控制锁定

- 离开所有楼梯区域后，下一物理帧恢复普通 Motor、重力和既有跳跃规则。
- 重生清除旧的跳跃/动画状态；检测区由物理引擎在传送后重新计算重叠。
- `control_locked` 继续由控制器提前处理，不在锁定期间发出攀爬移动或动画推进；进入锁定时会发送一次 `active = false`，避免旧攀爬动画滞留。

## 6. Hero 动画接口

`PlayerController` 提供：

```gdscript
signal climb_animation_requested(active: bool, direction: Vector2)
func is_on_ladder() -> bool
```

- `is_on_ladder()` 表示当前是否与有效楼梯区域重叠，供游戏逻辑查询。
- `active = true` 表示处于自由攀爬状态，适合显示爬楼梯或楼梯待机动画。
- `direction` 为归一化输入方向；上为 `(0,-1)`，下为 `(0,1)`，左右为 `(±1,0)`，无输入为 `Vector2.ZERO`。
- 新跳跃及按住跳跃上升、按住下快速下落、离开区域和重生时，发出 `active = false`。
- 只有 active 或 direction 发生变化时才发送信号，避免每帧重复触发动画。

Hero 后续可连接信号，将上爬、下爬、横爬和楼梯待机映射到具体 `AnimatedSprite2D` 或 `AnimationPlayer`。本任务不替用户选择动画节点名称或资源。

## 7. 异常与资源管理

- 没有有效区域时，攀爬组件完全交还普通 Motor，不产生动画循环。
- 非 `ladder_zone` 的 trigger 不参与检测。
- 扫描器跳过空 TileSet、非 TileMapLayer 子节点和不含楼梯坐标的单元格。
- 重建扫描结果时只清理扫描器自己生成的区域，不删除瓦片或其他实体。
- 每块楼梯瓦片一个轻量 Area；先保持简单可靠，不在本任务引入复杂区域合并。
- 用户的图片、TileSet、源房间和地图修改保持原样；已有未提交文件不会被整文件纳入本功能提交。

## 8. 测试与验收

### 8.1 单元与集成测试

新增 `tests/platformer_kit/character/test_ladder_motion.gd` 与 `tests/world/test_ladder_tiles.gd`，注册进现有运行时测试套件，并使用已有 `tests/run_test_script.gd` 单独运行。

覆盖：

1. 无输入悬停、上下左右速度、斜向归一化。
2. 新跳跃速度、连续跳跃重置、按住跳跃的上升重力、松开后恢复攀爬。
3. 跳跃进入区域后可再次跳跃，离开区域后恢复普通重力。
4. 按住下取消上升并触发快速下落，松开后可恢复攀爬。
5. 真实 Area 检测只接受 `ladder_zone`，其他 trigger 不误判。
6. 动画信号的 active/direction、去重和重生清理。
7. 原始备选 0、transpose 备选 1 都生成位置与尺寸正确的区域，其他坐标不生成。
8. 模板和 `room_01_00` 烘焙地形均包含可用的扫描器，预览与运行时行为一致。
9. 现有角色 Motor、输入、跳跃/落地粒子和 Killzone 测试不回归。

### 8.2 运行验证

- 在 `room_01_00` 源场景按 F6，验证上下左右、悬停、连续跳跃和按住下快速落地。
- 重新烘焙该房间并验证正式世界运行时结果一致。
- 运行 `godot --headless --path . -s res://tests/run_runtime_suite.gd`；实施前已存在的 `SavePoint/VisualRoot` 与 `Visual` 基线错误单独报告，不顺带修改。
- 检查最终 diff，确保没有改动用户瓦片内容、其他房间或无关系统。

## 9. 完成定义

- `(0,7)` 原始和横置备选瓦片在源房间及烘焙运行时都自动形成可用楼梯。
- 角色在区域内可自由攀爬、悬停、连续跳跃，按住下可快速落地，离开后恢复普通移动。
- Hero 获得稳定、去重的攀爬动画接口，但无强制动画资源依赖。
- 新测试、相关回归测试和实际房间验证通过；完整套件不出现本功能新增失败。
