# 组件使用教程

> 写给在房间里搭机关的作者：怎么搭、怎么调、不动的时候查哪里。
> API 速查见 `addons/platformer_kit/README.md`，设计理由见 `docs/superpowers/specs/`。
> 想直接抄一份能跑的例子：`scenes/levels/test_world/components_gallery.tscn`（见
> `docs/components-gallery.md`），每个组件一个站点，复制节点即可。

## 0. 三种组件，三种挂法

| 你想做的事 | 用什么 | 挂在哪 |
| :--- | :--- | :--- |
| 平台来回移动 / 坠落 / 升降 / 传送带 | `WaypointMotionComponent2D`、`FallMotionComponent2D`、`ElevatorMotionComponent2D`、`ConveyorSurfaceComponent2D` | `PlatformBody2D` 的**直接子节点** |
| 玩家站上去才触发 | `RiderTriggerComponent2D` | 平台的直接子节点（一个 `Area2D`） |
| 挡住迷雾视野 | `FogOccluderComponent2D` | 任何有 `CollisionShape2D` 的刚体下面 |
| 一扇能开合的门 | `DoorComponent2D` + `FogOccluderComponent2D` | 门实体的根节点下 |
| 看起来是墙、其实能穿 | `PhantomWallComponent2D` | 一个 `TileMapLayer` 上 |

**两条硬规则**

1. 运动组件必须是 `PlatformBody2D` 的直接子节点。宿主每帧只扫 `get_children()`，把组件塞进一个中间 `Node` 里就找不到，平台会一动不动。
2. 组件之间不互相 `import`，靠 `NodePath` + 约定方法沟通：`activate()`（触发）、`set_blocking()`（遮挡）。所以换预制体时，路径要跟着改。

## 1. 平台

### 1.1 先搭一个平台

```text
MovingPlatform (AnimatableBody2D)        script = platform_body_2d.gd
├── CollisionShape2D                     RectangleShape2D，平台大小
├── Visual (Polygon2D / Sprite2D)        随便画，跟着平台走
└── WaypointMotion (Node)                script = waypoint_motion_component_2d.gd
```

1. 新建 `AnimatableBody2D`，挂 `addons/platformer_kit/platforms/platform_body_2d.gd`。
2. 加 `CollisionShape2D` 和视觉节点（`Polygon2D`、`Sprite2D`、`AnimatedSprite2D` 都行）。
   视觉必须是平台的子节点，否则平台动了它不动。
3. 加运动组件（直接子节点）。
4. 单向平台：勾 `CollisionShape2D.one_way_collision`，不需要任何脚本。
5. 给 `platform_id` 填一个稳定名字（诊断和存档用），例如 `room0200:moving`。

`PlatformBody2D` 只有两个导出项：`platform_id`、`autoplay`（默认开，
`_physics_process` 每帧调 `advance_motion()`）。`sync_to_physics` 在 `_ready` 里
强制关掉，不要手改。

### 1.2 往返移动：`WaypointMotionComponent2D`

```text
WaypointMotion
waypoints = PackedVector2Array(0, 0, 128, 0)   # 相对平台初始位置的偏移
travel_speed = 51.2
arrival_pause_seconds = 0.5
loop_mode = PING_PONG                          # 或 CYCLE
```

| 导出项 | 含义 |
| :--- | :--- |
| `waypoints` | 路径点，**第一个必须是 `(0, 0)`**，且相邻点不能重复 |
| `travel_speed` | 像素/秒 |
| `arrival_pause_seconds` | 每次到点的停顿 |
| `loop_mode` | `PING_PONG` = 1,2,3,2,1；`CYCLE` = 1,2,3,1 |
| `autoplay` | 关掉后只能手动 `advance_motion()` |

信号 `waypoint_reached(index)` 可以接音效/机关。

**不会动？** 先查 `is_route_valid()`：`waypoints[0]` 不是零、少于两个点、
相邻点相同、`travel_speed <= 0`，任何一条都会让平台静默停下，不报错。

### 1.3 踩上去坠落：`FallMotionComponent2D` + `RiderTrigger`

```text
FallingPlatform (AnimatableBody2D)         script = platform_body_2d.gd
├── FallMotion (Node)                      script = fall_motion_component_2d.gd
├── RiderTrigger (Area2D)                  script = rider_trigger_component_2d.gd
│   └── CollisionShape2D                   盖住平台顶面
├── CollisionShape2D
└── Visual
```

`RiderTrigger` 的固定写法，照抄即可：

| 属性 | 值 | 说明 |
| :--- | :--- | :--- |
| `collision_layer` | `0` | 触发器自己不参与碰撞 |
| `collision_mask` | `2` | 2 是玩家所在层 |
| `target_paths` | `[NodePath("../FallMotion")]` | 要激活的组件 |
| `trigger_once` | `false` | `true` 表示本次进房间只触发一次 |
| `required_group` | 留空 | 留空 = 任何 `CharacterBody2D` 都能触发；填 `player` 则只让玩家触发（玩家控制器会把自己加进 `player` 组） |

`FallMotion` 的关键项：`gravity`（默认 900）、`terminal_velocity`、
`activation_delay`（踩上后延迟多久才掉）、`start_active`（不用触发就一直掉）、
`collision_mode`（`STOP_ON_COLLISION` 落地停住；`IGNORE_COLLISIONS` 直接穿下去）。

想让平台复位：`PlatformBody2D.reset_platform()` 会回到 `_ready` 时记录的位置，
并同时重置坠落状态和触发器。

### 1.4 升降机：`ElevatorMotionComponent2D`

```text
Lift (AnimatableBody2D)                    script = platform_body_2d.gd
├── ElevatorMotion (Node)                  travel = (0, -112)
├── RiderTrigger (Area2D)                  target_paths = ["../ElevatorMotion"]
├── CollisionShape2D
└── Visual
```

- `travel` 是相对初始位置的位移，向上为负 y；`speed`、`top_wait_seconds`、
  `bottom_wait_seconds` 控制节奏。
- 没人踩时停在原地；被触发后升到 `travel`、停一会儿、自己下来。
- 平台在途中时再次触发会被忽略（`activate()` 返回 false）。
- 到顶/到底有 `arrived_top` / `arrived_bottom` 信号。

### 1.5 传送带：`ConveyorSurfaceComponent2D`

```text
Belt (AnimatableBody2D)                    script = platform_body_2d.gd
├── ConveyorSurface (Node)                 surface_velocity = (70, 0)
├── CollisionShape2D
└── Visual
```

它每物理帧把 `surface_velocity` 写进父节点的 `constant_linear_velocity`，
所以运行时改速度立刻生效。父节点必须是带这个属性的刚体
（`AnimatableBody2D` / `StaticBody2D`）。

### 1.6 组合

速度是**相加**的：`WaypointMotion` + `FallMotion` = 一边横移一边坠落的平台。
`RiderTrigger.target_paths` 可以填多个组件，一次激活一堆机关。

只有 `FallMotion` 会要求宿主做移动碰撞（`blocks_on_collision()`）。纯 waypoint
平台不做碰撞检测，会直接穿过墙——这是设计如此，不是 bug。

### 1.7 平台自检表

| 症状 | 大概原因 | 处理 |
| :--- | :--- | :--- |
| 平台完全不动 | 组件不是直接子节点；或 `waypoints[0]` 不是 `(0,0)`；或 `travel_speed <= 0` | 见 1.2 的 `is_route_valid()` |
| 平台穿过地形 | 只有 `FallMotion` 会做碰撞移动 | 需要挡墙就用坠落模式的平台，或自己写 `blocks_on_collision()` |
| 玩家站上去不被带着走 | 平台没有 `CollisionShape2D`，或玩家没真正站上去（只是擦边） | 检查形状与 `one_way_collision` |
| 坠落平台踩了不掉 | `RiderTrigger` 的 `collision_mask` 不是 2、形状没盖住平台顶面、`target_paths` 为空 | 见 1.3 的表 |
| 复位后机关不重新触发 | 只调了 `position` 没调 `reset_platform()` | 用 `reset_platform()`，它会重置子组件 |

## 2. 视野（迷雾）

迷雾只认一个约定：节点在 `fog_occluder` 组里，并且实现了
`is_occluding() -> bool` 和 `get_world_rect() -> Rect2`（或者
`get_occluder_cells()`）。遮挡组件已经把这两件事包好了。

### 2.1 给平台/箱子加影子：`FogOccluderComponent2D`

```text
FallingPlatform (AnimatableBody2D)
├── FogOccluder (Node2D)                   script = fog_occluder_component_2d.gd
├── FallMotion
├── CollisionShape2D
└── Visual
```

- 不用配尺寸：轮廓默认取宿主所有 `CollisionShape2D` 的并集，改碰撞形状就自动改遮挡。
- 编辑器里选中它会出现青色 `OCC` 框；没有框说明 `body_path` 找错了或者宿主没有形状。
- 只在轮廓跨过 8px 格时请求迷雾重建，移动平台不会每帧刷。
- `blocks_sight = false`：保持注册但透光（比如玻璃平台）。
- `size_override` / `footprint_offset`：宿主没有形状、或者只想遮一部分时用。

**注意**：迷雾的探索是"看过就记住"。遮挡只能阻止格子**第一次**被照亮；已经看过的
区域不会因为平台重新挡回来而变黑（和门的开合表现一致）。

### 2.2 门：`DoorComponent2D`

最省事：直接实例 `scenes/world/fog_door.tscn`。要自己做一扇：

```text
Door (Node2D)
├── Body (StaticBody2D)                    collision_layer = 1
│   └── CollisionShape2D                   RectangleShape2D
├── Door (Node2D)                          script = door_component_2d.gd
│                                           body_path = ../Body
│                                           sense_path = ../Sense
│                                           occluder_paths = [../FogOccluder]
├── FogOccluder (Node2D)                   body_path = ../Body
└── Sense (Area2D)                         collision_layer = 0, collision_mask = 2
    └── CollisionShape2D
```

| 导出项 | 含义 |
| :--- | :--- |
| `size_cells` | 门板尺寸（格）；会改写 `Body` 的 `RectangleShape2D` 和感应区 |
| `closed` | 初始开合状态（运行时状态，不存档） |
| `blocks_sight` | 关着时是否挡视野（关掉就是"实心但透光"的门） |
| `interactive` | 是否响应交互键 |
| `interaction_action` | 默认 `interact`；工程里没有这个动作就静默无效 |
| `solid_collision_layer` | 关门时恢复的碰撞层，默认 1 |
| `occluder_paths` | 要随门开关的遮挡组件 |

信号：`door_opened`、`door_closed`。方法：`set_closed(bool)`、`toggle()`、`is_closed()`。

`size_cells` 只对 `RectangleShape2D` 生效；门板绘制是程序化的，想换美术就在外面盖
`Sprite2D` 并把 `Door` 节点隐藏。

### 2.3 幻影墙：`PhantomWallComponent2D`

1. 把 `scenes/world/phantom_wall.tscn` 拖到 `RoomContent/Entities`。
2. 选中实例，在底部 **TileMap** 面板里直接画（tileset 已预置，碰撞已关）。
3. 把同一批格子从 `Terrain/SolidTiles` 擦掉，**建议先擦后画**，让自动地形重算边缘。

| 导出项 | 含义 |
| :--- | :--- |
| `reveal_on_contact` | 角色碰到就显形（默认开） |
| `fade_seconds` | 淡出时长，`0` = 立刻消失 |
| `sense_margin_pixels` | 接触判定比墙大多少像素 |
| `blocks_sight` | 显形前是否挡视野 |

- 遮挡轮廓 = 你画在这层上的**所有**格子，装饰瓦片也算；不想挡就画到别处。
- 显形：`reveal()` → 迷雾重建、图层淡出。显形前被它挡住的空间会一直黑着。
- 要"能力/开关才显形"：把 `reveal_on_contact` 关掉，触发时自己调 `reveal()`。
- 状态只在本房间访问内有效，重新进房间墙面恢复。

### 2.4 三者的区别

| | 实心？ | 挡视野？ | 怎么打开 |
| :--- | :--- | :--- | :--- |
| 门 | 关着时实心 | 关着时挡 | 交互键 |
| 幻影墙 | 永远不实心 | 显形前挡 | 身体碰到 / 手动 `reveal()` |
| 平台 + 遮挡 | 能站上去 | 一直挡 | 不打开，靠移动改变遮挡位置 |

## 3. 放进房间、烘焙、测试

1. 打开源房间（例如 `scenes/levels/test_world/test_fog_start.tscn`，路径约定
   `scenes/levels/<世界>/<房间>.tscn`）。
2. 节点放在 `RoomContent/Entities` 下。迷雾相关的实体（`FogZone`、门、幻影墙）
   都放这里；`Terrain` 下面只放地形图层。
3. 保存源场景，然后在 World 编辑器主界面按 **Bake**（或 **Bake Stale**）。
   输出在 `scenes/rooms/generated/<room_id>/` 和 `resources/rooms/generated/<room_id>.tres`。
4. **不要手改生成出来的场景**，下次烘焙会被覆盖。
5. 跑起来看：`scenes/levels/test_world/runners/test_world_runner.tscn` 可以直接进测试世界。

## 4. 自己写组件

### 4.1 运动组件

```gdscript
class_name DriftMotionComponent2D
extends PlatformMotionComponent2D

## 匀速漂移。宿主会把 sample_velocity 的返回值按 delta 移动。
@export var drift_speed := 12.0

var _direction := 1.0

func sample_velocity(_delta: float) -> Vector2:
	if not enabled:
		return Vector2.ZERO
	return Vector2(drift_speed * _direction, 0.0)

## 返回 true 时宿主会用 move_and_collide 移动，并在撞到时回调 on_motion_collision。
func blocks_on_collision() -> bool:
	return false

func on_motion_collision(_normal: Vector2) -> void:
	pass

func reset_component() -> void:
	_direction = 1.0
```

四个方法就是全部契约。`enabled` 是基类给的开关。

### 4.2 遮挡组件

```gdscript
func _ready() -> void:
	add_to_group(&"fog_occluder")

func is_occluding() -> bool:
	return visible

func get_world_rect() -> Rect2:
	return Rect2(global_position, Vector2(8.0, 16.0))

func refresh_fog() -> void:
	get_tree().call_group(&"fog_of_war", "request_refresh")
```

状态变化（开/关、移动跨格、尺寸变了）之后调一次 `refresh_fog()` 即可。
平台组件不要 `import` 迷雾的脚本，只用组名和方法名。

### 4.3 几条约定

- 组件是 `Node` / `Node2D` / `Area2D` 都行，但运动组件必须直接挂在宿主下。
- 不要用引擎成员名做自己的变量（`position`、`size`、`material`、`modulate` 等），
  编辑器会报 `SHADOWED_VARIABLE_BASE_CLASS`。
- 参数不用就加 `_` 前缀，别删（引擎回调的签名不能改）。
- 改完跑一遍：`godot --headless --path . --check-only -s <脚本>`，
  再跑完整测试 `godot --headless --path . -s res://tests/run_runtime_suite.gd`。

## 5. 总自检表

| 症状 | 先查 |
| :--- | :--- |
| 机关完全没反应 | 节点是不是放错层级（组件要在宿主下，实体要在 `RoomContent/Entities` 下） |
| 改了源场景，游戏里没变 | 忘了 Bake；或改到 `scenes/rooms/generated/` 里去了 |
| 迷雾没挡住 | 遮挡组件在不在 `fog_occluder` 组；宿主有没有 `CollisionShape2D`；`is_occluding()` 是不是 false |
| 挡住的地方还是亮的 | 那块区域之前已经探索过（迷雾只向前揭示） |
| 门打不开 | `Sense` 的 `collision_mask` 不是 2；`interact` 动作不存在；玩家没站进感应区 |
| 幻影墙撞不进去 | `Terrain/SolidTiles` 里的旧格子没擦 |
| 幻影墙挡了不该挡的地方 | 把装饰瓦片也画到了墙的图层上（整层都算遮挡） |
| 组件在编辑器里报警告 | 看 Debugger，按提示改；不要留着"以后再说" |
