# 华容道自动生成与自动打乱设计

日期：2026-10-25
项目：wellwell / 华容道平台跳跃
状态：已实现（2026-10-25），由无头运行时测试套件验证

## 目标

1. 新增自动生成棋盘组件：不再手写 `PuzzleTilePiece`，而是指定一个源 `TileMapLayer`，
   按「华容道大小 × 每个滑块大小」均分区域，自动生成每块的 `PuzzleTilePiece`
   （含 TileMapLayer 子层、格子内容、移动距离、虚空块）。
2. 新增自动打乱组件：盘面由等大的滑块组成、存在一个或多个虚空滑块时，加载时通过
   合法滑动（围绕虚空）把盘面打乱，并让打乱结果成为新的初始布局；兼容第 1 个组件，
   也兼容手工摆放的 `PuzzleBoard`。
3. 用 `res://scenes/levels/main/room_02_00.tscn` 做示范迁移，并重烘运行时场景。

## 非目标

- 不做求解器 / 不保证最少步数。
- 不做非均分 / 非方形区块的自动拆分（`room_04_00` 的 L 形块保持手工）。
- 不持久化打乱结果（离开房间再进入会重新打乱；可用非 0 `seed` 固定）。
- 不改核心规则层（`PuzzleRuleSet` / `BoardOccupancy` / `PuzzleSession` 语义不变）。
- 不新增美术资源；不改 `scenes/levels/room_02_00.tscn`（同名旧副本）与
  `the_world.tres`。

## 术语

- **区块（chunk）**：`piece_size` 大小的格子矩形，是生成一个滑块的单位。
- **源图层**：编辑器内的输入 TileMapLayer，不是运行时内容。
- **虚空源图层**：可选，涂到的格子就是虚空滑块的足迹。
- **生成签名**：源图层内容 + 导出参数的哈希，用于判断是否需要重建。

## 组件 1：`PuzzleBoardAuto`

文件：`scripts/puzzle/view/puzzle_board_auto.gd`，`@tool`，`class_name PuzzleBoardAuto extends PuzzleBoard`。

### 导出参数

| 参数 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `puzzle_size` | `Vector2i` | `(3,3)` | 横向 / 纵向区块数 |
| `piece_size` | `Vector2i` | `(7,7)` | 每个滑块的格子数 |
| `source_layer_path` | `NodePath` | 空 | 拼图内容源图层 |
| `void_layer_path` | `NodePath` | 空 | 可选虚空源图层 |
| `void_enable` | `bool` | `false` | 生成的虚空块是否可被主动操控 |
| `regenerate` | `bool` | `false` | 勾选立即重建（写回 false） |
| `_source_signature` | `String`（`@export_storage`） | `""` | 上次生成时的签名，不显示在检查器 |

`board_size` 由 `puzzle_size * piece_size` 自动写入，不手填。`cell_size` 继承父类（默认 8）。

### 拆分算法

1. 解析 `source_layer_path` / `void_layer_path`（相对本节点）。源图层缺失或为空 → 警告并中止。
2. 原点 = 两个图层已用矩形（`get_used_rect()`）的并集左上角（非空图层参与）。
   所有格子减去原点得到棋盘格坐标。
3. 按 `Vector2i(floor(rel.x / piece_size.x), floor(rel.y / piece_size.y))` 分桶。
4. 每个桶：
   - 桶内有虚空格 → 虚空块（忽略实体/单向格，与 `PuzzleTilePiece` 现有规则一致）。
   - 否则桶内有实体格 → 普通块。普通块若没有任何「带物理」的格子，仍生成但
     `PuzzleTilePiece` 会得到空 footprint（现状行为，不做特殊处理）。
   - 桶内既无实体也无虚空 → 不生成（天然空位）。
5. 越出 `[0, puzzle_size * piece_size)` 的格子被忽略并报告警告数量。

### 生成的节点

```
PuzzleBoardAuto (board_size = puzzle_size * piece_size)
├─ Piece_0_0            PuzzleTilePiece, position = chunk_origin * cell_size
│  └─ SolidTiles        TileMapLayer, tile_set = 源图层 TileSet, collision_enabled = true
├─ Piece_1_1            PuzzleTilePiece（虚空），z_index = 1
│  └─ VoidTiles         TileMapLayer, tile_set = 虚空图层 TileSet, collision_enabled = false
└─ ...
```

- 子层格子坐标是「相对区块左上角」的坐标；`piece.position` 是区块左上角。
- `x_move_distance = piece_size.x`，`y_move_distance = piece_size.y`，
  `movement_mode = FREE`，普通块 `enable = true`，虚空块 `enable = void_enable`。
- 所有生成节点 `set_meta(&"puzzle_generated", true)`，并记录 `set_meta(&"authored_cell", chunk_origin)`；
  重建只删除带该 meta 的子节点，不碰手工节点。源图层只读。
- 虚空块 `z_index = 1`，保证被普通滑块盖住时仍然可见（设计文档要求虚空绘制在普通块之上）。

### 刷新与幂等

- `_process`（仅编辑器）：计算签名
  `puzzle_size | piece_size | cell_size | 源路径+名字+tileset id+hash(tile_map_data) |
  虚空路径+名字+tileset id+hash(tile_map_data) | 原点`。
  与 `_source_signature` 不同则累积 0.2s 后重建一次；重建后写回签名。
- 场景打开时若签名不一致（包括首次迁移）自动重建一次。
- `regenerate` 勾选立即重建。
- 生成结果 `owner` 设为场景根（编辑器内），从而写入房间源场景并参与烘焙。
- 公开 `generate_pieces() -> bool` 供测试/工具直接调用（不依赖编辑器）；
  公开 `get_generated_pieces() -> Array[PuzzleTilePiece]`。

### 运行时

- 不生成、不解析 NodePath、不做签名检查；只把 `board_size` 设为
  `puzzle_size * piece_size`，然后 `super._ready()` 用已保存的 Piece 建会话。
- 源图层放在房间源场景的 `PreviewOnly/` 下（烘焙流程只烘焙 `RoomContent`，不会进运行时）。

### 配置警告

- 源图层未设置 / 为空。
- 有格子落在棋盘范围之外（被忽略）。
- 同一区块同时存在实体与虚空格（按虚空处理）。
- 源图层 TileSet 的 tile 宽度与 `cell_size` 不一致。
- 整盘被滑块填满且没有任何虚空块（滑块永远动不了）。

## 组件 2：自动打乱

### `PuzzleScrambler`（纯逻辑）

文件：`scripts/puzzle/systems/puzzle_scrambler.gd`，`class_name PuzzleScrambler extends RefCounted`。

```gdscript
const DEFAULT_STEPS := 120
const MAX_EXTRA_STEPS := 400

static func build_scrambled_state(
    definition: PuzzleDefinition,
    rules: PuzzleRuleSet,
    start_state: BoardState,
    steps: int,
    rng: RandomNumberGenerator,
    void_only: bool = true,
    avoid_reverse: bool = true
) -> BoardState
```

算法：

1. `state = start_state.duplicate_state()`。
2. 每步用 `rules.get_legal_moves(state)` 生成候选，再对每个候选调用
   `rules.resolve_turn(state, move)`（虚空 A+ 诱导移动在这里整体校验）。
3. `void_only = true` 时只保留「回合中至少有一个块是虚空」的 turn。
4. `avoid_reverse = true` 时排除「与上一回合主移动同一块、方向相反」的候选；
   若排除后没有候选则允许（避免死锁）。
5. `rng.randi_range` 选一个 turn，用 `rules.apply_move` 依次落到新 state；
   记录本回合主移动。
6. 完成 `steps` 步后若 `state.get_hash_key() == start_state.get_hash_key()`，
   继续补步，最多再 `MAX_EXTRA_STEPS` 步。
7. 无候选（棋盘没有可动滑块）→ 返回 `null`。

### `PuzzleBoard` 新增 API

```gdscript
func apply_initial_layout(state: BoardState) -> void
func scramble(steps: int = 120, seed: int = 0, void_only: bool = true, avoid_reverse: bool = true) -> bool
```

- `apply_initial_layout(state)`：
  - 校验 `session` / `definition` / 数量一致；
  - 把 `state.pieces[i].cell` 写回 `definition.pieces[i].initial_cell`；
  - `session.clear_rider()`、`_deselect_piece(true)`、`_end_drag()`、`_hide_preview()`；
  - `session.reset_initial()`（清空撤销/重做历史）；
  - `_sync_pieces_from_state(false)`（瞬间同步，无动画）。
- `scramble(...)`：
  - 清 rider；`seed == 0` → `rng.randomize()`，否则 `rng.seed = seed`；
  - 调 `PuzzleScrambler.build_scrambled_state(...)`；
  - 结果为空或与当前状态相同 → 返回 `false`，不改任何状态；
  - 成功 → `apply_initial_layout(state)` 并返回 `true`。

### `PuzzleBoardShuffler`（节点组件）

文件：`scripts/puzzle/view/puzzle_board_shuffler.gd`，`class_name PuzzleBoardShuffler extends Node`，运行时生效（非 `@tool`）。

| 参数 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `board_path` | `NodePath` | `^".."` | 指向目标 `PuzzleBoard`；默认放在 Board 子节点 |
| `shuffle_on_ready` | `bool` | `true` | 加载时打乱一次 |
| `steps` | `int` | `120` | 随机走步数 |
| `seed` | `int` | `0` | 0 = 每局随机；非 0 = 可复现 |
| `void_only` | `bool` | `true` | 只走会让虚空移动的回合 |
| `avoid_reverse` | `bool` | `true` | 避免立即反向 |

- `_ready()`：`shuffle_on_ready` 为真时解析 board；若 board 已 ready 立即打乱，
  否则 `await board.ready` 后打乱。目标缺失或打乱失败只 `push_warning`。
- 公开 `shuffle_now() -> bool` 供调试工具再次打乱。
- 放在 Board 子节点时用默认 `board_path = ^".."`；放在兄弟节点时把 `board_path`
  指向 `../PuzzleBoard`。若想让加载时的打乱同步完成（便于测试与确定顺序），
  放在 `RoomContent/Entities` 中 Board **之后** 的兄弟位置。
- 打乱后：`R` 重置回到打乱后的布局；`Z` 没有可撤销内容；打乱不动玩家、不播动画。
- 兼容任意 `PuzzleBoard`，不依赖 `PuzzleBoardAuto` 的私有字段。

## 场景迁移：`scenes/levels/main/room_02_00.tscn`

1. 用一次性 headless 脚本从现有 9 个 `PuzzleTilePiece` 读出格子，合并成两个源图层：
   - `PuzzleSourceTiles`：8 个普通区块共 392 格；
   - `PuzzleVoidTiles`：中间菱形 25 格。
   两者位于 `PreviewOnly/`，`tile_set` 沿用 `primordial_tileset.tres`，碰撞关闭，
   节点位置与 Board 对齐。
2. Board 节点脚本换成 `puzzle_board_auto.gd`，设置参数并删除 9 个手工 Piece 子节点。
3. `RoomContent/Entities` 中 Board 之后新增 `PuzzleBoardShuffler`，`board_path = ^"../PuzzleBoard"`，
   其余默认参数。
4. 在编辑器中让 `@tool` 重建并保存源场景；然后用一次性 headless 脚本调用
   `RoomBaker.bake(...)` 重烘 `scenes/rooms/generated/main_room_02_00/`。
   一次性脚本不进版本库。
5. 注意：`PackedScene.pack()` 会把 `level_template.tscn` 实例内联，破坏房间契约，
   因此迁移必须保留源 `.tscn` 结构（文本补丁 + 编辑器保存）。

## 测试

新增（并注册进 `tests/runtime_suite.gd`）：

- `tests/puzzle/test_puzzle_board_auto.gd`
  - 用真实 TileSet 在代码里搭源图层（含菱形虚空），调用 `generate_pieces()`；
  - 断言 `board_size`、区块数量、Piece 位置、`SolidTiles` / `VoidTiles` 命名与碰撞开关、
    子层格子相对坐标、虚空足迹与 `is_void`、移动距离、`void_enable`；
  - 幂等：连续生成两次节点数不变、格子不变；
  - 越界格子被忽略；
  - 源图层缺失时 `generate_pieces()` 返回 `false` 且不修改棋盘。
- `tests/puzzle/test_puzzle_board_shuffler.gd`
  - 自动生成 2×2 棋盘（每块 2×2，一格整块虚空）→ 打乱端到端；
  - 固定种子可复现，不同种子不同布局；
  - 打乱后布局 ≠ 起点、所有格子仍在棋盘内且不压墙；
  - `definition.pieces[i].initial_cell` 已更新、`undo()` / `reset()` 都是 no-op、
    Piece 节点位置与 state 一致；
  - 无虚空但有空位的棋盘：`void_only = true` 返回 `false` 且布局不变，
    `void_only = false` 可打乱；
  - 整盘填满且无虚空：返回 `false`，无报错。
- `tests/puzzle/test_puzzle_auto_room.gd`
  - 加载重烘后的 `main_room_02_00` 运行时场景；
  - Board 脚本是 `puzzle_board_auto.gd`，9 个 Piece（8 普通 + 1 虚空）；
  - 虚空足迹 25 格、锚点 `(7,7)`；
  - 加载后布局已偏离作者布局（打乱生效）；
  - `PreviewOnly` 不在运行时场景中。

## 风险与对策

- 生成节点写入房间源场景会让 `.tscn` 变大、需要重新烘焙：只处理均分棋盘，节点数有限，
  重建幂等，且只删除带 meta 的生成节点。
- 忘记重新生成：编辑器内签名自动重建 + `regenerate` 手动按钮。
- 打乱把玩家卡住：打乱只在加载时发生，是合法滑动序列；文档注明出生点不要放在棋盘内。
- 打乱结果不可复现：`seed` 非 0 即可复现。
- 迁移破坏模板实例：不使用 `PackedScene.pack()` 重存源场景，改用文本补丁 + 编辑器保存。

## 不变契约

- `PuzzleBoard` 现有的输入、选中、跟随、撤销/重置、虚空 A+ 规则不变。
- 手工摆放的 `PuzzleBoard` 继续可用；自动板与打乱组件都是可选组合。
- `PuzzleTilePiece` 的层命名、虚空规则、碰撞开关约定不变。
