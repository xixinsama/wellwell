# 地形三层瓦片（z 0）

一间房的可见地面由三个 `TileMapLayer` 组成：它们都挂在 `RoomContent/Terrain`（烘焙产物里是 `Terrain`）下、共用同一张图集、`z_index` 都是 0。本文讲这三层分别是什么、为什么拆成三层，以及**每个系统到底读哪一层**。

场景出处：模板 `scenes/rooms/template/level_template.tscn:35-49`；烘焙产物 `scenes/rooms/generated/light_lab/terrain.tscn:10-26`（根节点 `RoomTerrain`，`Terrain` 直接挂在根下，子节点依次是三层瓦片加一个 `LadderAreaBuilder`）。

## 三层各自是什么

| 层 | `collision_enabled` | 语义 |
| :--- | :--- | :--- |
| `BackTiles` | `false`（`level_template.tscn:39`、`terrain.tscn:15`） | 背景板上的瓦片：不碰撞、不挡光、不挡气。只有法线缓冲和背景投影按瓦片读它（`BackdropField` 只把它当节点调 `modulate`，见下表）。 |
| `SolidTiles` | 默认 `true`（`level_template.tscn:41-42`、`terrain.tscn:17-19`） | 唯一的碰撞层：碰撞体 / 光照遮挡体 / 气体遮罩 / 迷雾视线 / 描边 / 水面地板的来源。 |
| `DetailTiles` | `false`（`level_template.tscn:46`、`terrain.tscn:23`） | 前景装饰层，画在 `SolidTiles` 之后。目前没有任何系统按名字读它。 |

三层的 `tile_set` 都是 `res://resources/tilesets/primordial_tileset.tres`（`level_template.tscn:38/42/45`，`terrain.tscn:14/19/22`）。图集是共享的，所以"这块瓦片算不算实心"不由图集决定，而由**它放在哪一层**加**它有没有碰撞多边形**决定。

**`BackTiles` 到底有没有碰撞？** 图块里有碰撞多边形（见"图集与碰撞"一节），但层上把碰撞关掉了：`collision_enabled = false`。同一份图集放进 `SolidTiles` 才会碰撞。

**`DetailTiles` 和梯子。** 设计意图是梯子/藤蔓这类纯装饰放这一层，但代码和数据都不是这样：`LadderAreaBuilder` 不看层名，它遍历 `Terrain` 下**每一个** `TileMapLayer`，按 `source_id == 0` + 图集坐标 `(0, 7)` 认梯子（`scripts/world/ladder_tile_area_builder.gd:7-8`、`:19-32`），把相邻格子合并成 `LadderZone`（`Area2D`，`:33-45`）。`tests/world/test_ladder_tiles.gd:17-24` 甚至用一个**没名字**的层放 `(0,7)`，说明层名完全不参与判定。实际数据里梯子都在 `SolidTiles`（`loop_entry` 6 格、`room_01_00` 13 格、`s_one` 11 格、`test_fog_start` 6 格），而 `DetailTiles` 在所有烘焙房间中几乎为空，只有 `test_fog_start`（4 格 `(1,5)`）和 `test_fog_wide`（1 格）用过。

梯子放在 `SolidTiles` 里不算墙，原因是光/描边/迷雾按**碰撞多边形**判实心，`(0,7)` 没有多边形所以被跳过（`light_field.gd:695-700`、`terrain_highlight.gd:234-241`、`fog_of_war.gd:792-804`）。但气体和水按**格子有没有瓦片**判实心（`atmosphere.gd:574-585`、`water_field.gd:623`、`water_grid.gd:502`），会把它当实心——见"容易忘的点"。

## 为什么是三层，而不是一层

**层名就是数据契约。** 同一张图集，不同层承担不同语义，而系统是按层名去取数据的：`light_field.gd:683` 写死 `"Terrain/SolidTiles"`，`backdrop_shadow.gd:45` 写死 `Terrain/BackTiles`，`normal_field.gd:65` 用层名数组。所以"这块瓦片放哪一层"不是美术习惯，而是告诉系统"把它当成什么"。

**背景瓦片必须画在墙下面，法线缓冲里也要排在墙下面。** `NormalField.source_layer_names` 的默认值与顺序就是这个意思（`normal_field.gd:58-65`）：注释说背景瓦片"是房间画面的一半"，而实心墙遮挡它们，**后出现的名字画在更早的名字之上**，所以墙不会因为房间场景的节点顺序反而被背景压住。克隆顺序由 `_find_layers_named()` 明确按数组顺序排序（`normal_field.gd:264-274`），不依赖树序的巧合。

**拆开后每个系统只读它需要的那层。** 光读 `SolidTiles`、投影读 `BackTiles`、描边读碰撞多边形。合成一层的话，每个系统都得自己再过滤一遍"这块算不算实心"，而且改一处会牵动所有系统。

**烘焙器要求三个层名固定。** `addons/world_editor/authoring/room/room_baker.gd:14` 是 `REQUIRED_TERRAIN_LAYER_NAMES = ["BackTiles", "SolidTiles", "DetailTiles"]`，`:249-252` 用它校验烘焙产物；运行时同一份名单在 `addons/platformer_kit/world/runtime/world_terrain_runtime.gd:10-12`，`:84-93` 里缺一层整个房间直接载入失败。

## 谁在消费这些层

| 系统 | 读哪一层 | 读来干什么 | 代码位置 |
| :--- | :--- | :--- | :--- |
| `NormalField` | `BackTiles` + `SolidTiles` | 用生成的 `normal_tileset` 克隆进房间大小的视口渲一次，得到法线缓冲（顺序见上节） | `scripts/world/normal_field.gd:65`、`:264-274`、`:290-360` |
| `BackdropShadow` | `BackTiles` | 把瓦片合成一张房间剪影，做背景板上的投影 | `scripts/world/backdrop_shadow.gd:45`、`:244-248`、`:258-293` |
| `LightField` | `SolidTiles`（碰撞多边形） | `_build_occluders()` 收格子 → `_emit_occluders()` 合并成长边 → `_push_occluder()` 建 `LightOccluder2D`；玻璃 `(0,3)` 跳过 | `scripts/world/light_field.gd:679-706`、`:712-742`、`:753-767` |
| `Atmosphere` | `SolidTiles`（整格，不看多边形） | 8 px 一格的气体遮罩，气体进不去 | `addons/fluid_kit/runtime/gas/atmosphere.gd:179`、`:562-585` |
| `FogOfWar` | `SolidTiles`（碰撞多边形，玻璃跳过，单向砖单列） | 视线阻挡表，决定格子是可见/已探索 | `addons/metroidvania_kit/map/discovery/fog_of_war.gd:348`、`:770-809` |
| `WaterField` | `SolidTiles`（整格） | 逐列从下往上找第一格空位当地板高度 | `addons/fluid_kit/runtime/water/water_field.gd:128`、`:611-626` |
| `WaterGrid` | `SolidTiles`（整格） | 单元水体的实心格，墙把水体积拿走 | `addons/fluid_kit/runtime/water/water_grid.gd:124`、`:492-504` |
| `TerrainHighlight` | `SolidTiles`（碰撞多边形） | 沿轮廓画内侧高光，并按 hero 可达空气只亮一侧 | `scripts/world/terrain_highlight.gd:30`、`:214-243` |
| `LadderAreaBuilder` | `Terrain` 下**所有**层，按 `source_id` + `(0,7)` 认梯子 | 合并成 `LadderZone`（`Area2D`） | `scripts/world/ladder_tile_area_builder.gd:7-8`、`:19-45` |
| `CrumbleRuntime` | `SolidTiles`，外加旧层 `CrumbleTiles`/`CrumbleOneWayTiles` | 找出 `(3,0)`/`(3,4)` 的可塌格子 | `scripts/world/crumble_runtime.gd:27-29`、`:73-79` |
| `BackdropField` | **不读瓦片**，只把 `Terrain/BackTiles` 当 `CanvasItem` 调 `modulate` | 画背景板；和"读瓦片"是两回事 | `scripts/world/backdrop_field.gd:126-130` |
| `WorldTerrainRuntime` | `Terrain` 下三层是否齐全 | 不齐就不载入这间房 | `addons/platformer_kit/world/runtime/world_terrain_runtime.gd:84-93` |

## 图集与碰撞

`primordial_tileset.tres` 只有**一个**图集源（source id `0`，`.tres:193`），`texture_region_size = Vector2i(8, 8)`、`tile_size = Vector2i(8, 8)`（`.tres:13`、`:185`）。共 22 个图集坐标、55 个图块条目（22 个基础朝向 + 33 个额外变体），两个物理层：`physics_layer_0`（`collision_layer = 1`，整块实心）与 `physics_layer_1`（`collision_layer = 16`，单向）（`.tres:186-189`）。

| 类别 | 图集坐标 | 备注 |
| :--- | :--- | :--- |
| 实心 | `(0,0)` `(1,0)` `(3,0)` `(0,3)` 整格；`(0,1)` 4 个朝向（斜坡）；`(0,2)` 4 个朝向（半砖） | 6 个坐标 / 12 个条目 |
| 单向 | `(0,4)/0`、`(1,4)/0`、`(1,4)/1`、`(2,4)/0`、`(3,4)/0` | 5 个条目；`(0,4)` 和 `(2,4)` 的另外 3 个朝向**没有**多边形 |
| 无碰撞 | `(0,5)` `(0,6)` `(0,7)` `(0,8)` `(1,5)` `(2,5)` `(3,5)` `(4,0)` `(4,1)` `(4,5)` `(5,1)` `(5,5)` | 梯子 `(0,7)`、藤蔓/贴花、自动地形角块 |

以上数字是把 `.tres` 载入 Godot 后用 `TileSetAtlasSource.get_tiles_count()` / `get_alternative_tiles_count()` / `TileData.get_collision_polygons_count()` 数出来的，不是猜的。

**测试用瓦片（`(3,5)` / `(4,5)` / `(5,5)` / `(4,0)` / `(4,1)` / `(5,1)`）。** 这几块是为了在干净的底色上看光照、气体、抖动而加的，全部**没有碰撞多边形**：

| 坐标 | 内容 | 用途 |
| :--- | :--- | :--- |
| `(3,5)` | 纯白底 + 右侧/下侧各 1px 格线（亮度 255，格线 0） | 铺满就是 8px 网格的纯白背景，光照/气体/阴影在这种空白底上最容易看清 |
| `(4,5)` | 同样的网格，中灰 | 同上，低一档亮度 |
| `(5,5)` | 1 像素棋盘格（255 / 39 交替） | 深色抖动底，用来对比"颗粒背景"和"纯色背景" |
| `(4,0)` `(4,1)` `(5,1)` | 自动地形角块（带 `terrain_set = 0` 的 peering bit，各 4 个翻转备选） | 自动拼接用的边角 |

因为它们没有碰撞多边形，放进 `SolidTiles` 时：玩家可以穿过、光照/描边/迷雾不把它们当实心，**但气体和水会**（见"容易忘的点"的"两套判据"）。当"看得见的墙"用的话，需要先在图集里给它们画碰撞多边形。

**备选（alternative）为什么存在。** 斜坡和半砖需要多个朝向，编辑器用 `flip_h`/`flip_v`/`transpose` 组合出变体（例如 `(0,1)` 一共 4 个朝向，`.tres:18-29`），单向平台 `(1,4)` 甚至有 8 个（`.tres:56-80`）。另一类是自动地形用的角块：`(4,0)`、`(4,1)`、`(5,1)` 带 `terrain_set = 0` 的 peering bit（`.tres:118-179`），它们也没有碰撞多边形。

**法线图集是从这张反照率烘出来的，不接受手绘。** `scripts/tools/bake_tileset_normals.gd:1-17` 的说明和流程：读 `assets/images/primordial_tileset.png` → 推出法线 → 写 `primordial_tileset_normal.png` → 按反照率的**结构**重建 `primordial_tileset_normal.tres`（同坐标、同备选顺序、同翻转标志）。加一块新瓦片到反照率之后必须重跑：

```powershell
godot --headless --path . -s res://scripts/tools/bake_tileset_normals.gd
```

不重跑的后果有两条：`tests/world/test_tileset_normals.gd:330-380` 会扫全部烘焙房间，把"图集缺格"直接判失败；运行时那些格子在法线缓冲里是平的，而且只留一条 `push_warning`（`normal_field.gd:361-365`、`:378-388`）。另外，法线的备选是**镜像区域而不取反法线的 x/y**，所以翻转备选的浮雕方向不严格正确——这是已知限制，写在 `bake_tileset_normals.gd:47-58`。

**玻璃 `(0,3)`。** 它有碰撞但透光：`LightField` 用 `glass_tile_atlas = Vector2i(0,3)` 跳过它（`light_field.gd:65`、`:687-690`），`FogOfWar` 同样跳过（`fog_of_war.gd:787`），所以它挡玩家、不挡光、不挡视线。`light_lab` 在 `SolidTiles` 里放了 5 格试这个行为。

## 描边和法线怎么接进来

描边接在 `SolidTiles` 上：`TerrainHighlight.layer_path` 默认 `Terrain/SolidTiles`（`terrain_highlight.gd:30`），轮廓形状取自每块瓦片的碰撞多边形做扫描线填充（`:216-243`），所以斜坡是三角形边缘、没有多边形的格子（梯子/贴花）完全不进遮罩。可达图、只亮 hero 一侧、参数和实测都在 `docs/terrain-highlight.md`，这里不重复。

法线接在 `NormalField` 上：房间没有手工的 `NormalTiles` 层时，它把 `source_layer_names` 里的层按数组顺序克隆进一个房间大小的 `SubViewport`、换成 `normal_tileset` 渲一次（`normal_field.gd:290-360`），之后引擎把它留在 `UPDATE_DISABLED`，一个房间只花一次。法线怎么用、浮雕强度与暗部/高光的关系在 `docs/lighting.md`。

## 房间作者要遵守的三条

1. **三层都要存在，名字不能改。** `BackTiles` / `SolidTiles` / `DetailTiles` 是硬契约（`room_baker.gd:14`、`:249-252`；运行时另有一份校验 `world_terrain_runtime.gd:84-93`）。改名的后果不是"少画一层"，而是烘焙校验失败或房间载入失败。
2. **实心墙放 `SolidTiles`。** 只放在 `BackTiles` 里的东西不会碰撞（层上 `collision_enabled = false`，`level_template.tscn:39`）、不会遮挡光（`light_field.gd:683` 只找 `Terrain/SolidTiles`）、也不挡气体（`atmosphere.gd:179`），而且不挡迷雾视线（`fog_of_war.gd:348`）。它是纯背景。
3. **加图块之后重烘法线图集。** 命令见上一节；反过来，只改房间不动图集也要重烘房间产物（`scripts/tools/rebake_room.gd`），否则运行时加载的还是旧的 `terrain.tscn`。

## 怎么自己看

```powershell
$godot = "D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"

# 整帧 + 每个顶层节点 solo + z 阶梯 + 各系统遮罩 + 层清单
& $godot --path . --resolution 1280x720 `
    -s res://scripts/tools/render_inspector.gd -- `
    --scene res://scenes/levels/test/light_lab_runner.tscn --out C:/tmp/layers
```

- `solo_*.png`：每个**顶层世界节点**单独一张（`render_inspector.gd:265-284`）。三层瓦片不是顶层节点，所以没有 `solo_backtiles.png`；要看的是 `solo_terrainroot.png`（`render_inspector.gd:32-36` 的图例顺序）。
- `stack_z+000.png` 与 `stack_z+001.png`：`z <= N` 的所有东西（`:195-207`）。和 `stack_z-001.png`（只有背景板）对比，差值就是"地形层加了什么"。
- `mask_normal_buffer_*.png`、`mask_backdrop_mask_*.png`、`mask_gas_density_*.png`、`mask_light_map_*.png`（`:39-46`、`:287-305`）。这几张最能证明"这层有没有被消费"：法线缓冲里该有背景瓦片的浮雕、剪影里该有背景瓦片的形状、气体遮罩里被当成实心的格子应该和 `SolidTiles` 的占用格一致。注意 `gas_density` 只有 GPU 后端才出图（`atmosphere.gd:312-318`），`normal_buffer` 是只渲一次的视口，工具会先踢它一脚再读（`render_inspector.gd:292-299`）。
- `inventory.txt`：一行一个 `CanvasItem`，字段是 `name / class / z / z_relative / visible / texture / shader`，缩进表示树深（`render_inspector.gd:137-152`）。找 `BackTiles`、`SolidTiles`、`DetailTiles` 三行：`z` 都是 `0`，**出现得越早的越先画**，这就是三层的先后关系；改 `z` 会让它跳到别的系统的上方/下方。

## 容易忘的点

- **三层 z 都是 0**，它们之间的先后只靠树序：`BackTiles` → `SolidTiles` → `DetailTiles` → `LadderAreaBuilder`。给某层单独调 `z_index` 会把它抬到整帧的别处去，地形不需要这么干。
- **`DetailTiles` 在 `SolidTiles` 之后画**，所以它是前景：放在这里的瓦片会盖住实心墙。
- **`LadderAreaBuilder` 是 `Terrain` 下的一个 `Node2D`，自己什么都不画**（`level_template.tscn:48-49`、`terrain.tscn:25-26`）。它只在 `_ready()` 里 `rebuild()` 一次（`ladder_tile_area_builder.gd:11-13`），运行时改瓦片不会自动重算（`test_ladder_tiles.gd:36` 是手动调）；烘焙产物里它的子节点是空的，`LadderZone` 全部运行时生成（`test_ladder_tiles.gd:76-80`）。
- **"实心"有两套判据。** 光/描边/迷雾看碰撞多边形，气体/水看格子有没有瓦片。所以一块没有多边形的装饰瓦片（梯子 `(0,7)`、自动地形角块 `(4,0)` 等）不挡玩家、不挡光、不挡视线，却会被气体和水当成实心格。
- **`BackTiles` 忘了关碰撞就是一层看不见的碰撞墙。** 模板和多数烘焙房间是关的；`gas_field_lab` 早先的脚本生成器用默认参数建层（`collision_enabled = true`），现已修正为 `false` 并重新烘焙（实测 `BackTiles` / `DetailTiles` 都是 `false`、`SolidTiles` 是 `true`）。自己写房间生成器时记得显式关掉这两层。
- **旧房间可能多于三层。** `GlassTiles`、`VisionBlockTiles`、`MarkerTiles`、`CrumbleTiles`、`CrumbleOneWayTiles` 仍被 `world_terrain_runtime.gd:6-9` 和部分系统兼容读取，但模板只要求三层（`room_baker.gd:14`）；新房间不要依赖这些旧层。
- **`CrumbleRuntime` 认的是图集坐标而不是层**：`(3,0)` 既是完整实心砖又是可塌砖（`crumble_runtime.gd:27-29`），所以"这块砖会不会塌"不能只看层，得看图集坐标。
