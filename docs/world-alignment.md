# 世界格子对齐与房间框

区块是 `320x180` 像素，格子是 `8x8`：横向 40 格整，纵向 `180 / 8 = 22.5` 格。
所以**相邻两个区块行不可能都是 23 格**。本项目把每个房间的格子矩形对齐到全局格子网格：

```text
x0 = origin_chunk.x * 40
y0 = round(origin_chunk.y * 22.5)
w  = size_chunks.x * 40
h  = round((origin_chunk.y + size_chunks.y) * 22.5) - y0
```

| 区块行 y | 起始格 | 1 行房间的高度 |
| :---: | :---: | :---: |
| 0 | 0 | 23 |
| 1 | 23 | 22 |
| 2 | 45 | 23 |
| 3 | 68 | 22 |

两行合计 45 格 = 360 像素，正好覆盖两个区块；多行房间按每个 block 行分别计算，所以高度会在
23 / 22 之间交替。`RoomGrid.get_room_cell_rect` / `get_room_block_cell_rects` 是唯一的换算入口，
`WorldData.get_room_cell_rect` / `get_room_pixel_rect` 直接用它。

## 运行时都按格子对齐

以下系统不再用 `origin_chunk * (320,180)`，而是用格子矩形 × 8 的像素原点：

- 房间内容（`RoomRuntime.position`）、世界地形（`WorldTerrainRuntime`）；
- 迷雾的房间范围（`FogOfWar.set_room_chunks`）、相机边界（`WorldSession` 的 room bounds）；
- 光照 / 法线 / 尘埃 / 背景阴影 / 崩塌（`light_field`、`normal_field`、`dust_field`、
  `backdrop_shadow`、`crumble_runtime`）；
- 流体（`fluid_kit` 的水网格、水面、气体）；
- 世界画布的房间矩形 / 地形预览、地图的精确渲染与迷雾叠加（`MapRoom.cell_origin/cell_size`）。

奇数行房间会整体下移 4 像素（内容和地形一起移动），房间之间从此严丝合缝；代价是奇数行房间
高 176 像素，而视口高 180，相机会多露出 4 像素邻接房间的边缘——那 4 像素本来就属于上一行的
最后一格，视觉上是连续的。

## 房间源场景里的格子框

`RoomAuthoringRoot` 现在有：

| 属性 | 含义 |
| :--- | :--- |
| `world_origin_chunk` | 房间在世界里的区块起点 |
| `world_origin_known` | 世界编辑器是否已经写入过起点 |

场景在编辑器里打开时，`RoomAuthoringRoot` 会创建一个**内部子节点** `RoomCellFrame`
（`INTERNAL_MODE_FRONT`，`z_index = 100`），由它绘制格子框：

- **一条外框**：房间格子矩形并集，2 像素粗，**紧贴房间边缘**（描边中心线在房间边界外 1 像素，
  所以线正好占 0～2 像素，不留空隙）；
- **每个 block 接缝一条线**：多 block 房间不再画多个互相重叠的矩形，而是外框 + 每道接缝一条
  2 像素线；这条线以接缝为中心，**每侧只占 1 像素，合计 2 像素**，不会像两个相邻矩形那样
  叠成 4 像素。接缝落在真实格子上：
  - 横向接缝永远在 40 格（320 像素）处，X 方向与奇偶无关；
  - 纵向接缝按世界起点奇偶交替：偶数行上方是 23 格（184 像素），奇数行上方是 22 格（176 像素）；
- 绿色：起点已同步，框就是烘焙后实际保留的格子；
- 橙色：起点还没同步，框按“偶数行”假设绘制；
- 内部子节点不会被保存进 `.tscn`，每次打开场景时重建，所以场景文件里没有多余节点。

`world_origin_chunk` / `world_origin_known` / `room_size_chunks` 改动时，框会立即重绘。
从 World 编辑器打开房间（`open_source_room`）时，插件会把当前的世界起点写进打开的场景
（跟着场景一起保存）。直接双击打开房间场景时，如果之前没从世界编辑器打开过，就会看到橙色框。

> 世界编辑器里的 **Bake** 总是把当前的世界起点作为参数传给 `RoomBaker`，所以即使源场景里
> 存的是旧起点，裁剪也永远按真实放置来算。

## 烘焙裁剪

`RoomBaker.stage/bake` 新增可选的 `origin_chunk` 参数。传了它时：

- 每个地形图层（`BackTiles`、`SolidTiles`、`DetailTiles`……）里超出 block 框的格子会在
  复制出来的烘焙副本上被删除，不会出现在生成物和游戏里；警告里会给出被裁掉的数量
  （`cropped N terrain cell(s) outside the room's cell frame`）。
- 实体**不裁**：位置在框外的实体只在警告里列出（`entity 'X' sits outside the room's cell frame`），
  由作者决定移动还是保留。
- 不传 `origin_chunk`（且源场景没有同步起点）时不做裁剪，保持旧行为，便于单独测试/旧流程。

源场景本身不会被修改，框外的格子还留在场景里，方便你看到并手动清理。

在世界编辑器里编辑世界地形（Edit Terrain / Sync Terrain）见
[world-painting.md](world-painting.md)。

## 已知影响
- 已经有烘焙产物的房间需要重新 **Bake** 一次才会吃到裁剪；运行时的对齐会立即生效。
- 迷雾/地图的探索记录以全局格子坐标保存：区块行 ≥ 2 的房间，旧存档里的探索格子会偏移
  1 格（世界格子原点从 `chunk*23` 变成 `round(chunk*22.5)`）。开发存档重新探索即可。
- 世界栈的 3D 视图、门的位置等都通过 `WorldData.get_room_pixel_rect` 自动跟随，无需再改。

## 验证

- `tests/world/data/test_room_grid.gd`：23/22 交替、多行合计 45、block 框。
- `tests/authoring/test_room_cell_crop.gd`：偶数行 23 格 / 奇数行 22 格的裁剪。
- `tests/authoring/test_room_cell_frame.gd`：场景里的 2 像素外框与 22/23 交替。
- `tests/authoring/test_terrain_patch.gd`：世界内绘制的补丁与烘焙合并。
- `tests/world/test_room_runtime.gd`、`test_world_terrain_runtime.gd`、`test_world_session.gd`、
  `test_runtime_bindings.gd`、`test_light_field.gd`、`test_normal_field.gd`、`test_dust_field.gd`、
  `test_backdrop_shadow.gd` 都按格子对齐后的期望值断言。
