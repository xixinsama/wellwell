# 组件样板间

`scenes/levels/test/components_gallery.tscn` 是一个两屏宽（2×1 区块）的房间，把平台、
视野和实体组件各摆了一份，**每个站点都是一个可以整段复制的节点**。

- 直接预览：在编辑器里打开这个场景按 **F6**。场景自带玩家、相机和迷雾
  （`PreviewOnly`），门、幻影墙、遮挡都能正常工作，不需要先烘焙。
- 在世界里跑：它已经烘焙并注册进测试世界（区块 `(3, 1)`），从世界编辑器打开
  测试世界、或跑 `scenes/levels/test/test_world_runner.tscn` 都能进去。

## 怎么复制

1. 打开 `components_gallery.tscn`，展开 `RoomContent/Entities`。
2. 选中你要的站点（比如 `01_Elevator`），复制。
3. 粘贴到你自己的房间里，放在 `RoomContent/Entities` 下。
4. 改参数、改位置，必要时补上它脚下的地形。

复制时注意：

- **平台**：复制后把 `platform_id` 改成你自己的稳定名字（诊断/存档用）。
- **门 `05_Door`、幻影墙 `06_PhantomWall`**：它们是预制体实例，复制实例就行；
  里面的节点路径（`body_path`、`occluder_paths`）会跟着一起复制。
- **幻影墙**：复制后要 ① 在新的位置画上瓦片，② 把同一批格子从
  `Terrain/SolidTiles` 里擦掉。样板间里它替掉的是 `(60, 18)`、`(60, 19)` 两格。
- `Signs` 只是说明用的小字，不用复制。

## 站点一览

| 节点 | 包含的组件 | 演示什么 | 复制后常改 |
| :--- | :--- | :--- | :--- |
| `01_Elevator` | `PlatformBody2D` + `ElevatorMotionComponent2D` + `RiderTriggerComponent2D` | 踩上去触发，升到上面的小台，停一下自动下来 | `travel`、`speed`、等待时间；脚下要有一个落脚平台 |
| `02_Conveyor` | `PlatformBody2D` + `ConveyorSurfaceComponent2D` | 站在上面被传送带向右推 | `surface_velocity`（负值向左） |
| `03_Waypoint` | `PlatformBody2D` + `WaypointMotionComponent2D` + `FogOccluderComponent2D` | 左右往返；挂在它下面的遮挡在迷雾上投出**会移动的阴影** | `waypoints`（第一个必须是 `(0,0)`）、`travel_speed`、`arrival_pause_seconds` |
| `04_Falling` | `PlatformBody2D` + `FallMotionComponent2D` + `RiderTriggerComponent2D` | 踩上延迟 0.2 秒后坠落，落地停住 | `gravity`、`activation_delay`、`terminal_velocity` |
| `05_Door` | `DoorComponent2D` + `FogOccluderComponent2D`（`scenes/world/fog_door.tscn`） | 关着时挡住移动和视野，按 `E` 打开后里面的房间亮起来 | `size_cells`、`blocks_sight`、感应区形状 |
| `06_PhantomWall` | `PhantomWallComponent2D`（`scenes/world/phantom_wall.tscn`） | 看起来是墙、能直接穿过去，碰到后淡出并露出暗格 | 画在上面的瓦片、`fade_seconds`、`reveal_on_contact` |
| `07_OneWayPlatform` | 原生 `CollisionShape2D.one_way_collision` | 从下面跳上去、从上面落下来，不需要脚本 | 形状尺寸、方向 |

对照站点的地形：`01` 的落脚台、`05`/`06` 的口袋房间（墙 + 天花板）都在
`RoomContent/Terrain/SolidTiles` 里，复制节点时记得把配套地形一起补上。

## 重新生成

```powershell
godot --headless --path . -s res://tools/build_components_gallery.gd
```

- 源场景已存在时，工具**只重新烘焙**，保留你在编辑器里的手改；
- 想按脚本里的布局整体重写源场景，把 `FORCE_REWRITE` 改成 `true`；
- 世界注册只在测试世界里还没有这个房间时执行。

## 保护测试

`tests/authoring/test_components_gallery.gd` 会检查：房间契约、每个站点该有的组件、
幻影墙盖住的两格确实从 `SolidTiles` 擦掉了、单向平台打开了 `one_way_collision`、
以及房间仍然注册在测试世界的 `(3, 1)`。改样板间时跑一遍完整套件即可发现回归。
