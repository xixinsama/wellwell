# 场景结构：世界框架 / 房间内容 / 预览副本

这份文档回答两个问题：**渲染系统住在哪、房间作者该放什么**，以及
"为什么这些系统不放进模板关卡"。

---

## 1. 三层结构

```
scenes/runtime/world_root.tscn          运行时框架（整个世界一份，任何房间都用它）
├─ 系统节点（单例）：BackdropField / BackdropShadow / TerrainHighlight /
│   LightField / NormalField / ScreenBloom / DustField / FogOfWar /
│   Atmosphere / WaterField / WaterGrid / CrumbleRuntime / Player / PixelCamera2D
└─ WorldRuntime（房间内容的挂载点，按房间 id 生成子节点）
    └─ TerrainRoot（房间地形 + 房间实体，房间绑定时创建）

scenes/rooms/template/level_template.tscn   房间模板（作者继承它来画关卡）
├─ RoomContent/{Background, Terrain/{BackTiles,SolidTiles,DetailTiles}, Entities, Foreground}
├─ PreviewOnly/{Player, PixelCamera2D, WaterField, Atmosphere, FogOfWar, DebugOverlay}
└─ UI/DebugHud

scenes/rooms/generated/<room_id>/           烘焙产物（运行时加载的就是它们）
├─ runtime.tscn     RoomRuntimeContent/{Entities, Foreground}
└─ terrain.tscn     RoomTerrain/{Background, Terrain/三层瓦片}
```

要点：**烘焙器只打包 `RoomContent`**（`room_baker.gd` 的 `RUNTIME_EXCLUDED_CHILD_NAMES = ["Background", "Terrain"]` 只是把它们分到 `terrain.tscn`，`PreviewOnly` 和 `UI` 根本不进产物）。所以模板里的 `PreviewOnly/Atmosphere` 只存在于编辑器里。

---

## 2. 房间绑定时发生了什么

`WorldSession`（挂在 `world_root.tscn` 根上）持有 `_room_extensions`，切房间时按顺序做：

1. 对每个 extension 调 `clear_room()`（如果有）；
2. 加载/实例化房间的 `runtime.tscn` 和 `terrain.tscn`，挂到 `WorldRuntime/<room_id>` 和 `TerrainRoot` 下；
3. `_bind_room_extensions()`：对每个 extension 调 **`bind_room_with_origin(room_data, terrain_root, origin_chunk)`**（没有这个方法的退回 `bind_room(room_data, terrain_root)`）；
4. `LightField` 通过 **`set_light_field(texture, pixels, origin_pixels)`** 把光照图交给订阅者；
5. `NormalField` 同理交 `set_normal_field(...)`；
6. 发 `world_ready` 信号。

两种注册方式（这是最容易漏的地方）：

| 方式 | 谁这么做 | 说明 |
| :--- | :--- | :--- |
| **自注册** | `BackdropShadow`、`NormalField`、`DustField`、`CrumbleRuntime`、`WaterField`、`WaterGrid`、`Atmosphere`、`LightField` | 在 `_ready()` 里 `world.call("register_room_extension", self)`，宿主不用管 |
| **宿主注册** | `FogOfWar` | 它**不自注册**，必须由宿主场景（`runners/test_world_runner.gd`、`scenes/app/main.tscn` 等）显式 `register_room_extension` 一次 |
| **只收信号** | `BackdropField`、`TerrainHighlight` | 不绑定房间，只连 `world_ready` 自己装饰 |

`register_room_extension` 是幂等的（已在列表里就返回 false），所以 `runners/test_world_runner.gd` 里那一长串注册调用对自注册的系统是冗余的 —— **只有 `FogOfWar` 那条是必需的**。写新 runner 时照抄那段，或至少别漏掉 fog。

`LightField._bind_consumers()` 按**组名**找消费者：`fog_of_war`、`terrain_highlight`、`water_field`、`atmosphere`、`backdrop_shadow` —— 任何进了这些组且实现了 `set_light_field` 的节点都会拿到光照图。

---

## 3. 为什么这些系统不放进模板关卡

**理由一：它们是单例，放进房间就会变成 N 份。** 光照图是"一个屏幕一张"，里面是加色 `PointLight2D` + 全部遮挡体；法线缓冲、泛光缓冲、迷雾遮罩同理。每个房间各带一份，同屏就有多份在渲染同一个矩形、互相覆盖，而且多份 GPU 缓冲白烧。

**理由二：它们的输入与房间无关，输出才与房间有关。** 系统读的是世界状态（玩家位置、当前房间矩形、设置），产出的是"这个房间的光图/法线/剪影"。所以系统住在世界框架里，**每次绑定时按新房间重建自己的产物**（`LightField` 重建视口、灯和遮挡体；`NormalField` 重新克隆瓦片渲一次；`BackdropShadow` 重新合剪影；`Atmosphere` 重建 160×90 或 80×45 的求解器）。

**理由三：房间产物必须保持"纯内容"。** 烘焙器的契约是"房间 = 地形 + 实体"，产物里只有 `RoomRuntimeContent` 和 `RoomTerrain`。一旦允许系统实例进房间，产物就不再是纯数据，房间之间的差异会渗进渲染管线，改动一个系统要重烘所有房间。

**理由四：作者不需要、也不该编辑基础设施。** 作者只需要画地形、摆实体和标记；系统参数（环境光、泛光阈值、气体步频）在世界框架上统一调，改一次全场生效。

---

## 4. 房间可以放什么

| 标记 | 谁收集 | 作用 |
| :--- | :--- | :--- |
| `SpawnPoint`（`spawn_id`） | 烘焙 + `WorldSession` | 出生点；`start_spawn_id` 用它 |
| `RoomEntrance` | 烘焙 + `WorldSession` | 房间出口，连接另一个房间的 spawn |
| `RoomLight`（`fog_light` 组） | `LightField`、`Atmosphere` | 房间里的灯（半径/颜色/闪烁），同时进雾的受光列表 |
| `GasVent`（`gas_vent` 组） | `Atmosphere` | 喷口：一个通道、方向、半径、速率、射流速度（最多 4 个） |
| `GasField`（`gas_field` 组） | `Atmosphere` | 房间级气体配置：ambient / decay / diffusion / refill |
| `GasInteractor` / `GasBrush` | 自己找 `atmosphere` 组 | 让实体推挤气体 / 让鼠标画气体 |
| `FluidRegion` / `WaterBasin` / `WaterGate` | `WaterField`、`WaterGrid` | 水体区域、水池、闸门 |
| `FogZone` | `FogOfWar` | 暗区/亮区、雾的渐隐与聚光 |

**不要放**：`LightField`、`NormalField`、`ScreenBloom`、`DustField`、`FogOfWar`、`Atmosphere`、`BackdropField`、`BackdropShadow` 的运行时实例。世界框架里已经有；房间再放一份，轻则白烧，重则同一个组里出现两个实例、`get_first_node_in_group()` 取到错的那个。

---

## 5. 一个真实踩过的坑

模板里有 `PreviewOnly/Atmosphere`、`PreviewOnly/FogOfWar`，它们和世界框架里的同名节点在**同一个组**里。在编辑器里预览房间时只有预览那份存在，没问题；但**如果在运行中的世界里把房间源场景（带 `PreviewOnly`）实例化出来**，`get_first_node_in_group(&"atmosphere")` 可能返回错误的那一个，气体就会画到一个房间里、而求解器在另一个。所以：运行时永远只加载 `scenes/rooms/generated/` 的产物，不要加载 `scenes/levels/` 的源场景。

---

## 6. 加一个新系统要做的三件事

1. 继承/实现 `bind_room_with_origin(room_data, terrain_root, origin_chunk)`（以及 `clear_room()`）；
2. 在 `_ready()` 里 `get_parent()...call("register_room_extension", self)` **或者**在宿主（runner / main）里注册 —— 二选一，别两边都做（虽然幂等）；
3. 如果它需要光照图/法线缓冲，加入对应组并实现 `set_light_field(...)` / `set_normal_field(...)`；
4. 在 `render_inspector.gd` 的 `KNOWN_LAYERS`（层顺序图例）和 `MASK_SOURCES`（遮罩导出）里加上它，否则调试工具看不见这一层。

对应的契约测试：`tests/world/test_runtime_bindings.gd`、`tests/world/test_world_session.gd`。
