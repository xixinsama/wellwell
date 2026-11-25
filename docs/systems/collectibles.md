# 编号收集物

`scenes/world/number_pickup.tscn` 是一个带编号的收集物：数字是它的**身份**，不是数量。
它会上下浮动、发一圈微光，玩家碰到即收集，并写进存档；收集图鉴会把当前世界的所有编号
一一列出，已收集的亮、没收集的灰着，漏了哪一个一眼就能看到。

## 作者怎么放

1. 把 `scenes/world/number_pickup.tscn` 拖到房间的 `RoomContent/Entities` 下。
2. 在检查器里填 `number`（同一世界内唯一）。
3. 保存源房间并 **Bake**。

就这三步。不需要登记总数、不需要在别处维护列表：图鉴的全集是游戏启动时扫描
当前世界所有已烘焙房间里的收集物得到的。

| 导出项 | 含义 |
| :--- | :--- |
| `number` | 编号，也是图鉴里的那一格；同一世界内唯一 |
| `bob_pixels` | 上下浮动的幅度（像素），默认 2 |
| `bob_speed` | 浮动快慢（Hz 量级），默认 0.5 |

## 运行时表现

- `ActivationArea` 只检测玩家所在的第 2 层，并且只认 `player` 组的角色，敌人/其他物体不会误吃。
- 收集后立即隐藏、停止浮动，实体状态写进存档（`world:room:number_<编号>`），读档或重进房间不会再出现。
- 微光是两层加色多边形加脉冲，不依赖房间光照系统，放很多也不会增加灯光开销。
- 图鉴的全集按**当前世界**算；换世界（穿梭门）后会自动扫描新世界，编号各自独立，存档里也按世界分开记。

## 收集图鉴

- HUD 左下角常驻一个小角标：`图鉴 3 / 12`。
- 按 `collection_toggle`（默认 **J**，可在设置 → 输入映射里改）打开全屏图鉴：
  标题下面是 `已收集 / 总数`，再下面按编号从小到大排列每一格，已收集的是亮色边框 + 白色数字，
  未收集的是灰边框 + 灰色数字。按 `Esc` 或再按一次 J 关闭。
- 图鉴打开时游戏暂停，关闭后恢复原来的暂停状态。

## 实现结构

| 文件 | 作用 |
| :--- | :--- |
| `game/entities/number_pickup.gd` | 收集物实体：编号、浮动、光晕、接触收集、存档状态 |
| `scenes/world/number_pickup.tscn` | 预制体（数字标签 + 两层加色光晕 + 检测区域） |
| `game/collectibles/collectibles.gd` | 自动加载 `Collectibles`：全集扫描、按世界记录已收集、写读存档模块 `collectibles` |
| `game/ui/collection_screen.gd` + `scenes/ui/collection_screen.tscn` | HUD 角标 + 全屏图鉴（SubViewport 之外，窗口分辨率） |
| `project.godot` | 自动加载 `Collectibles`、动作 `collection_toggle`（J） |

存档格式（模块 `collectibles`）：

```json
{"version": 1, "worlds": {"dash_world": {"collected": [1, 3, 7]}}}
```

## 注意

- 编号必须在**同一世界内唯一**；重复的编号在图鉴里会合并成一格。
- 图鉴的全集来自**已烘焙**的房间，改完收集物记得重新烘焙；没烘焙的房间不会被扫到。
- 换世界后角标和图鉴显示的是新世界的集合，之前的世界的收集进度仍在存档里。
- 调试场景（`tests/...runner`）不加载 `main.tscn`，所以没有 HUD 角标和图鉴；正常游戏流程有。

## 测试

- `tests/game/test_collectibles.gd` — 按世界记录、存档往返、扫描发现编号。
- `tests/game/test_number_pickup.gd` — 预制体契约、编号显示、收集隐藏、读档保持。
- `tests/ui/test_collection_screen.gd` — 角标文本、图鉴格子的已收集/未收集、暂停与关闭恢复。
