# 世界地形（World Terrain）

地形只有一份、属于世界：`scenes/worlds/<world_id>/terrain.tscn`。房间只是世界地形上的
矩形分区 + 实体容器，烘焙时从世界地形**切片**出每个房间的运行时地形。房间源场景里的
`RoomContent/Terrain` 保留为空壳（满足房间契约），不再作为地形来源。

## 编辑流程

1. World 编辑器顶部 **Edit Terrain**：
   - 地形场景不存在时，按 `scenes/worlds/terrain_template.tscn` 创建；
   - 用 Godot 正常打开该场景。
2. 在 Godot 的 TileMap 面板里编辑整个世界的地形（调色板、自动拼接、撤销都是原生的），
   Ctrl+S 保存。
3. 回到 World 编辑器点 **Sync Terrain**：
   - 读取磁盘上的地形场景；
   - 按每个房间的格子矩形切片、生成 `scenes/rooms/generated/<room>/terrain.tscn`；
   - 重新烘焙所有房间（实体不变时只更新地形）；
   - 刷新世界视图与房间预览。

> 没保存地形场景就 Sync 会读到旧文件；Sync 会先检查文件是否存在。

命令行等价物（无需打开编辑器，一次同步所有世界）：

```bash
godot --headless --path . -s res://tools/sync_world_terrain.gd
# 只同步一个世界
godot --headless --path . -s res://tools/sync_world_terrain.gd -- \
  --world=res://resources/worlds/test_world.tres
```

## 数据流

```text
scenes/worlds/<world>/terrain.tscn          ← 唯一地形作者入口（世界格子坐标）
        │ Sync：按 room cell rect 切片
        ├──> generated/<room>/terrain.tscn  ← 运行时每房间地形（房间本地格子）
        ├──> World 视图（整张世界地形）
        └──> 房间场景里的 WorldTerrainSlice（未保存的预览节点）
```

- 房间矩形由 placement 拥有（`origin_chunk` + `room_size_chunks`），切片用
  `RoomGrid.get_room_cell_rect`（偶数行 23 格、奇数行 22 格）。
- 房间源场景的 `Terrain` 图层保留（房间契约需要），但烘焙不再读取它；如果里面还有格子，
  烘焙会警告“room source terrain is ignored”。
- 房间场景打开时，`RoomAuthoringRoot` 会载入该房间的 baked terrain 切片，作为一个
  **无 owner 的 `WorldTerrainSlice` 节点**插在 Background 之后、Entities 之前；它不会被
  存进 `.tscn`，每次打开重建。

## 迁移（已有世界）

`tools/migrate_world_terrain.gd` 把每个世界现有房间的 Terrain 格子合并进世界地形场景，
然后清空房间源场景里的 Terrain 格子（图层保留）：

```bash
# 先看计划
godot --headless --path . -s res://tools/migrate_world_terrain.gd -- --dry-run
# 实际写入（会备份到 res://resources/worlds/_migration_backup/<时间戳>/）
godot --headless --path . -s res://tools/migrate_world_terrain.gd
# 单个世界 / 覆盖已有地形场景
godot --headless --path . -s res://tools/migrate_world_terrain.gd -- \
  --world=res://resources/worlds/test_world.tres --force
```

- 继承源场景（`packed.get_state().get_base_scene_state() != null`）不会被重写，避免把继承
  压平；它们只输出提示，Terrain 需要手动清空（烘焙已忽略它）。
- 迁移完成后在 World 编辑器里点一次 **Sync Terrain**，运行时切片才会更新为新地形。

## 新建房间（Draw Room）

World 编辑器顶部 **Draw Room** 进入拖框模式：在画布上按区块拖出一个矩形（不能和现有房间重叠），
释放后自动：

1. 用 `scenes/rooms/template/level_template.tscn` 生成实体-only 源场景
   `scenes/levels/generated/<world_id>/<room_id>.tscn`，`room_size_chunks` / `world_origin_chunk`
   按画出的矩形写入，`StartSpawn` 放到房间中心；
2. 若世界还没有地形场景，先按模板创建一个；
3. 走现有导入流程（placement + 切片烘焙 + 世界保存）；
4. 选中并聚焦新房间，关闭 Draw Room。

默认房间 id 是 `room_<x>_<y>`（冲突时加后缀），可以之后在检查器里改。

## 合并与拆分房间

世界地形不动，只重排房间矩形；两者都会生成**全新房间 id**，因此被合并/拆分区域的实体状态
（门、宝箱）和迷雾探索记录会重置，操作前请确认。

**Merge**（选中 2 个以上房间）

- 选中房间的并集必须**刚好是一个矩形**，否则拒绝并提示；
- 新房间 id 默认 `merged_<x>_<y>`，源场景写到
  `scenes/levels/generated/<world_id>/<id>.tscn`；
- 各成员的 `Entities` / `Foreground` 节点按世界坐标重定基后合并进新源场景（实例化预制体保留，
  重复的出生点/入口/持久实体 id 会报错并要求先改名）；
- 连接两端指向被合并房间的，改指向新房间；起始房间在其中时改到新房间的对应 spawn；
- 旧房间的源场景、`RoomData`、生成的运行时/地形场景会复制到
  `resources/worlds/<world_id>/merge_backup/<时间戳>/`，世界资源本身备份到
  `resources/worlds/_partition_backup/`。

**Split**（选中 1 个房间）

- 弹窗选择切线方向（水平切左右 / 垂直切上下）与切割位置（区块边界，默认中间）；
- 两个新房间 id 默认 `<原 id>_a` / `<原 id>_b`；
- 实体按世界坐标分到各自一侧并重定基；跨切线的实体不会保留，请先移到一侧；
- 连接按入口/出生点的世界位置改到对应新房间；起始房间/出生点按所在侧更新；
- 旧房间同样先备份再移除。

合并/拆分之后建议对相关房间跑一次 Bake（流程内部已经走导入并烘焙了新房间）。

## 注意

- 世界地形是普通场景，可以单独提交/回滚；修改后记得 Sync 才影响游戏。
- 一个世界一个地形场景；超大世界若编辑变慢，再按区域拆（后续）。
- 跨房间边界的自动拼接仍不会发生（运行时仍是每房间独立切片）；世界地形视图里能看到
  连续的地形，但烘焙后是分开的 TileMap。
- 房间源场景的 Terrain 图层目前保留为空壳；后续新房间（New Room）会从模板创建同样的空壳。
