# 以 World 为中心的地形与房间分区设计

日期：2026-11-22
状态：阶段 A/B/C/D 均已实现（世界地形、切片烘焙、Edit/Sync、迁移、Draw Room、Merge、Split）
相关：`docs/world-alignment.md`、`docs/world-painting.md`

## 1. 目标工作流

1. 在 World 编辑器点 **Edit Terrain**：Godot 打开一个**只有地形节点**的场景，作者用原生的
   TileMap 编辑面板（调色板、自动拼接、撤销、多选）编辑**整个世界**的地形。
2. 编辑完保存场景，回到 World 编辑器点 **Sync Terrain**：世界视图、模板房间、所有房间的
   烘焙产物统一更新为同一份地形。
3. 在 World 编辑器里框选空地 **New Room**：直接生成新房间（实体场景 + 放置矩形），地形不用重画。
4. 选中多个房间 → **Merge**：合并为一个大房间；选中一个房间 → **Split**：按切线拆成两个。

核心原则：**地形只有一份、属于世界；房间只是世界上的矩形分区 + 实体容器。**

## 2. 数据模型

### 2.1 WorldData（世界，唯一事实来源）

```text
WorldData
├── world_id / display_name / start_room_id / start_spawn_id
├── terrain_scene_path : String        # 新增：世界地形场景，唯一作者编辑入口
├── rooms        : Array[RoomData]     # 房间元数据（实体场景、尺寸、清单）
├── placements   : Array[WorldRoomPlacementData]  # origin_chunk
├── connections  : Array[RoomConnectionData]
└── regions      : Array[RegionData]
```

- `terrain_scene_path` 约定为 `scenes/worlds/<world_id>/terrain.tscn`；
- 地形场景只含 `WorldTerrain` 根 + 各 `TileMapLayer`（Back/Solid/Detail/Glass/Vision/Marker/
  Crumble/CrumbleOneWay），所有格子使用**世界格子坐标**（允许负数）；
- 地形场景不包含实体、脚本逻辑、预览节点，可以在 Godot 里独立打开/保存/撤销。

### 2.2 RoomData（房间 = 分区 + 实体场景）

```text
RoomData
├── room_id / display_name / map_color / tags
├── source_scene_path : String     # 只含实体、出生点、门、装饰的源场景
├── scene_path        : String     # 生成的运行时场景
├── terrain_scene_path: String     # 生成的房间地形切片（不再由作者编辑）
├── room_size_chunks  : Vector2i
├── entrance_ids / spawn_ids / entity_ids
└── source_fingerprint
```

- 房间源场景不再包含 `RoomContent/Terrain`；模板房间也去掉 Terrain（只留实体/PreviewOnly）。
- 房间的地形由烘焙时从世界地形**切片**得到（见 §3），运行时结构（每房间一个 terrain 节点）
  保持不变，所以迷雾/光照/法线/流体/相机/崩塌都不需要重写。

### 2.3 生成的切片

`RoomBaker` 烘焙一个房间时：

```text
world terrain (cells in world coordinates)
   └── slice by room cell rect (canonical, 23/22 rows)
        └── cells shifted by -room_cell_origin
             └── generated/<room>/terrain.tscn (room-local cells)
```

- 切片矩形就是房间的格子框（`RoomGrid.get_room_cell_rect`），所以不再需要“裁掉框外格子”；
  世界地形里房间框之外的格子属于别的房间或空地。
- 房间的 `runtime.tscn`（实体）照旧由源场景打包，不涉及地形。
- 每个房间记录一个 `terrain_revision`（世界地形文件 hash + 房间矩形），用于 stale 检测。

## 3. 地形编辑流程（复用 Godot 编辑器）

1. **Edit Terrain**：
   - 若 `terrain_scene_path` 不存在，用 `scenes/worlds/terrain_template.tscn` 实例化一份
     （8 个空 TileMapLayer，共用 primordial tileset），保存到约定路径；
   - `EditorInterface.open_scene_from_path(terrain_scene_path)`。
2. 作者在 Godot 的 TileMap 面板里编辑（调色板、自动拼接、Undo 全部原生可用），Ctrl+S 保存。
3. **Sync Terrain**（World 编辑器）：
   - 读取世界地形场景；
   - 刷新世界预览（整张世界地形按当前视图裁剪绘制）；
   - 对每个房间重新切片；与旧切片比较，内容变化的房间标记 stale；
   - 调用现有 Bake 流程重新生成地形切片 + 运行时场景（实体不变时只更新地形）；
   - 刷新模板房间预览（模板房间按自己的放置矩形显示切片）。
4. 作者不需要在 World 编辑器里选瓦片/画笔；`docs/world-painting.md` 里的“补丁画笔”方案删除。

**保存检测**：Sync 时直接读取磁盘上的 `terrain.tscn`（`ResourceLoader.CACHE_MODE_IGNORE`），
并与上次同步的 hash 比较；未保存的编辑器修改不会被读到，状态栏提示“先保存地形场景”。

## 4. 新建房间

- World 编辑器进入 **New Room** 模式：在画布上拖出一个矩形（按区块吸附，至少 1x1）。
- 合法性：不与现有房间矩形重叠；必须落在世界地形范围内（或允许空地）。
- 生成：
  1. 用房间模板实例化一个**实体-only**源场景，保存到 `scenes/rooms/<room_id>.tscn`；
  2. 在矩形中心放一个 `SpawnPoint`（`spawn_id = "default"`）；
  3. 创建 `RoomData` + placement（origin/size）；
  4. 不写任何地形——地面已经在地形场景里；
  5. 自动 Bake 一次，世界预览立即可见。
- 房间 id 默认 `room_<x>_<y>`，可改；改名时同步 world 里的连接/起始点。

## 5. 合并（Merge）

**输入**：选中 2 个及以上房间。

**约束**：所选矩形的并集**必须是一个矩形**（中间有被其他房间占据的空洞或非矩形并集 → 拒绝并
提示）。不做外接矩形吸收、不做任意形状。

**数据操作**：

1. 新房间 `C`：**全部使用新 id**（用户输入或默认 `merged_<x>_<y>`），rect = 并集。
2. 实体合并：依次实例化 A、B 的源场景，把实体节点按世界坐标重定基到 C 的局部坐标，
   reparent 到 C 的源场景；保留实例化预制体（`scene_file_path` + owner 不变），
   合并 `spawn_ids` / `entrance_ids` / `entity_ids`，重复 id 报错并要求先改名。
3. 连接重映射：所有 `from_room_id` / `to_room_id` 属于 A/B 的连接改为 C；
   entrance/spawn id 保持不变（重复则加后缀并更新连接）。
4. 删除 A/B 的 placement 与 RoomData；源场景/生成物移到
   `resources/worlds/<world_id>/merge_backup/<timestamp>/`，不直接删除。
5. 起始房间/出生点若在 A/B，改为 C 的对应 spawn。
6. 世界地形不动；C 的切片就是并集矩形切出来的地形。
7. 重新 Bake C，删除 A/B 的生成目录（或保留在备份里）。
8. **存档影响（已确认）**：房间 id 全部变化，A/B 里已开的门/宝箱、雾的探索记录会重置；
   操作前明确提示。

## 6. 拆分（Split）

**输入**：选中 1 个房间，选择切线方向与位置（**只允许区块边界**上的水平/垂直切线，
保证两个新房间都是整块矩形）。

**数据操作**：

1. 新房间 `C1`、`C2`，rect 为切线两侧，**全部使用新 id**（用户输入或默认
   `<old>_a` / `<old>_b`）。
2. 源场景复制两份，按实体的世界坐标过滤：完全落在各自矩形内的实体留下，位置重定基；
   跨切线的实体报错/提示手动处理（门、平台等）。
3. `spawn_ids` / `entrance_ids` 按所在侧分配；切线上的出生点归左侧（或提示）。
4. 连接重映射：连接端点所在侧的房间 id 更新；两侧之间的连接保留，变为跨房间连接。
5. 起始房间/出生点按所在侧更新。
6. 旧房间源场景/生成物备份；重新 Bake C1/C2；世界地形不动。
7. **存档影响（已确认）**：房间 id 全部变化，原房间的实体状态/探索记录重置，操作前提示。

## 7. 运行时与工具改动

| 模块 | 改动 |
| :--- | :--- |
| `WorldData` | 新增 `terrain_scene_path`；房间矩形仍由 placement 拥有 |
| `RoomData` | `terrain_scene_path` 变为生成物；`source_scene_path` 只含实体 |
| `RoomBaker` | 不再打包房间 Terrain；改为从世界地形切片 + 生成房间地形 scene |
| `WorldTerrainPreviewLayer` | 改为绘制**世界地形场景**（整张/按视图裁剪），不再逐房间加载 baked terrain |
| `WorldLayoutCanvas` | 新增 New Room 拖框、Merge/Split 选择与操作 |
| `WorldEditorMain` | Terrain 栏改为 Edit/Sync；新增 Merge/Split/New Room 命令与错误提示 |
| 模板房间 | 去掉 `RoomContent/Terrain`，只留实体/PreviewOnly |
| 迁移工具 | `tools/migrate_world_terrain.gd`：把每个世界现有房间地形合并进 `terrain.tscn`，删除房间场景里的 Terrain，重新切片/烘焙；先 dry-run + 备份 |
| 存档 | 房间 id 语义不变；Merge/Split 后按 §5/§6 提示存档状态影响 |

**不做的事**：不改迷雾/光照/流体/相机运行时（仍按房间切片工作）；不做跨房间自动拼接
（切片之间仍是独立 TileMap，跨房间边界的 autotile 拼接是后续“世界地形直接运行时”才解决）。

## 8. 分阶段实施

1. **阶段 A（地基）**：世界地形场景 + 模板/源场景去 Terrain + 切片烘焙 + 迁移工具 +
   Edit/Sync Terrain + 世界预览改为世界地形。
2. **阶段 B**：New Room 拖框创建（实体-only 源场景）。
3. **阶段 C**：Merge（矩形并集）+ 实体/连接重映射 + 备份。
4. **阶段 D**：Split（区块切线）+ 实体分配。
5. **阶段 E（可选）**：运行时直接渲染世界地形（解决跨房间 autotile 接缝、减少生成物）。

每阶段结束跑完整套件 + 编辑器冒烟；C/D 需要新测试覆盖实体重定基、连接重映射、备份。

## 9. 风险

- **实体重定基**：合并/拆分要在保留实例化预制体的前提下移动节点，必须用
  `scene_file_path` + owner 保持实例；需要专门的测试场景（门、存档点、平台）。
- **存档状态**：房间 id 变化导致实体状态/探索记录丢失（已确认接受，操作前提示）。
- **大地图性能**：每世界一个地形场景（已确认）；超大世界若编辑变慢，再按区域拆成多个
  地形场景，切片时合并读取。
- **地形保存检测**：必须提醒作者在 Godot 里保存地形场景后再 Sync，否则读到旧文件。
- **房间分区约束**：矩形不重叠、Merge 并集必须矩形、Split 只在区块边界、合并/拆分都用
  新房间 id——先立规矩，避免任意多边形/斜切带来的运行时与实体分配复杂度。
