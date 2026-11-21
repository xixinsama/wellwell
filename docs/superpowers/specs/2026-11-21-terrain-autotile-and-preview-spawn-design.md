# 自动地形描边与预览出生点自动跟随

日期：2026-11-21
状态：已与作者确认，待实现

## 背景

作者在 `primordial_tileset.tres` 的 `(4,0)`–`(5,1)` 2×2 图块上手动摆了 terrain peering bit，但实际刷图时边缘选块不对。无头测试复现出三个问题：

1. `(5,0)` 填充块 8 位全开，匹配任何邻域，刷任何形状都被它吃掉。
2. `(4,0)` 四个直边块各少一位“对侧”bit，直边与凸角同时匹配时 Godot 选凸角（右墙变 `4,1/1`、底边变 `4,1/1`）。
3. `(5,1)` 四个内角块只有 4 位，内角匹配不到；而且只有每块的 0 号备选有碰撞多边形，翻转备选不挡玩家、不挡光。

同时，新建房间从模板继承 `preview_spawn_id = "start"`，一旦把预览出生点改名（例如 `start_dash_01` 改成 `start01`），就必须手动同步，否则契约报错、预览失效。

## 目标

- 在 `SolidTiles` 上刷一片 ≥2 格厚的实心区域时，外缘自动出现 1 套描边（地面、天花板、左右墙、内外角）。
- 新建房间的 `preview_spawn_id` 不再需要手填：跟随预览出生点的改名，失效时回退到房间内第一个出生点。

## 非目标

- 不支持 1 格厚的薄墙/细线（缺“上下双描边、端点、T 形交叉”的美术）。Godot 会退回最接近的边块，可能缺一侧描边。
- 不新增图集坐标、不重绘美术、不改变 2×2 图块的翻转备选结构。
- 不改房间烘焙产物格式，不改世界数据格式。

## 自动地形

terrain set 保持 `mode = 0`（Match Corners and Sides）、terrain 0。规则：**bit 表示“同种地形继续延伸的方向”**，描边画在朝空气的一侧。

| 图块 | 画面 | peering bits |
| :--- | :--- | :--- |
| `(4,0)/0` | 上描边 | 左、右、下、左下、右下 |
| `(4,0)/1` | 下描边 | 左、右、上、左上、右上 |
| `(4,0)/2` | 左描边 | 上、下、右、右上、右下 |
| `(4,0)/3` | 右描边 | 上、下、左、左上、左下 |
| `(4,1)/0` | 上+右凸角 | 左、下、左下 |
| `(4,1)/1` | 下+右凸角 | 左、上、左上 |
| `(4,1)/2` | 上+左凸角 | 右、下、右下 |
| `(4,1)/3` | 下+左凸角 | 右、上、右上 |
| `(5,1)/0` | 左上内角 | 除“左上”外全部 7 位 |
| `(5,1)/1` | 左下内角 | 除“左下”外全部 |
| `(5,1)/2` | 右上内角 | 除“右上”外全部 |
| `(5,1)/3` | 右下内角 | 除“右下”外全部 |
| `(5,0)/0` | 填充 | 全部 8 位 |

- 13 个图块的每个备选都补整格碰撞多边形 `(-4,-4)(4,-4)(4,4)(-4,4)`，图层 0；图块本身不区分翻转。
- 用法：在 `RoomContent/Terrain/SolidTiles` 的 TileMap 面板 → Terrains → 地形集 0，用 Connect 刷。实心区域至少 2 格厚。
- 因为 `SolidTiles` 有碰撞，光/描边/迷雾/气体/水都会把它当实心；`BackTiles` 仍是纯背景。
- 法线图集按 AGENTS.md 重烘：`godot --headless --path . -s res://scripts/tools/bake_tileset_normals.gd`。

验收（无头测试）：刷 10×6 实心块，顶部 `4,0/0`、底部 `4,0/1`、左右 `4,0/2`/`4,0/3`、四角 `4,1/2`/`4,1/0`/`4,1/3`/`4,1/1`；在顶边挖一格凹口，凹口两侧出 `5,1/2`/`5,1/0`。

## 预览出生点自动跟随

`RoomAuthoringRoot` 新增：

- `get_spawn_ids() -> Array[String]`：扫描 `RoomContent` 内所有 `SpawnPoint`，去重并排序。
- `resolve_preview_spawn_id() -> String`：`preview_spawn_id` 在列表里就用它；否则用列表第一个；没有出生点返回空。
- `on_spawn_id_renamed(previous_id, new_id)`：由 `SpawnPoint` 改名时回调；如果旧 ID 就是当前预览 ID，或当前预览 ID 已失效，则把 `preview_spawn_id` 改成新 ID。
- `get_manifest()` 输出解析后的 `preview_spawn_id`。

`SpawnPoint` 的 `spawn_id` 改为带 setter 的属性（使用私有 backing 字段），编辑器里改名时向祖先查找 `on_spawn_id_renamed`。加载场景时不触发无效同步（属性设置阶段还没有父节点）。

消费方统一改用解析值：

- `RoomAuthoringContract.validate()`：原始 ID 失效但房间里有出生点时只记 warning（“回退到第一个出生点”），不再报错；房间完全没有出生点且原始 ID 非空时仍报错。
- `RoomPreviewController.setup_preview()`：用解析值查找 SpawnPoint，并把解析值写进预览快照。
- `RoomBakeManifest` / `WorldRoomImporter` 通过 manifest 自动拿到解析值。

## 涉及文件

- `resources/tilesets/primordial_tileset.tres`：13 个图块的 bits + 碰撞。
- `assets/images/primordial_tileset_normal.png`、`resources/tilesets/primordial_tileset_normal.tres`：重烘产物。
- `addons/world_editor/authoring/room/room_authoring_root.gd`
- `addons/world_editor/authoring/room/room_authoring_contract.gd`
- `addons/world_editor/authoring/room/room_preview_controller.gd`
- `addons/platformer_kit/world/entities/spawn_point.gd`
- `tests/world/test_tileset_terrain.gd`（新增）
- `tests/authoring/test_room_preview_spawn_auto.gd`（新增）
- `tests/authoring/test_room_authoring_contract.gd`（失效 preview 改为 warning）
- `tests/runtime_suite.gd`（注册新测试）
- `docs/layers/terrain-tiles.md`（图块表与用法）

## 兼容性

- 已有房间若在 `SolidTiles` 里画过 `(4,0)`–`(5,1)`，会自动获得碰撞，这是本次想要的语义；`BackTiles`/`DetailTiles` 仍然 `collision_enabled = false`。
- 已有的 `preview_spawn_id` 有效时行为不变；失效时从“报错”变为“warning + 回退”，只在完全没有出生点时仍报错。
- 世界数据、`RoomData` 字段不变。
