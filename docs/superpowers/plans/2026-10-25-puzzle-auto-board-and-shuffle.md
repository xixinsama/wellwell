# 华容道自动生成与自动打乱实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `PuzzleBoardAuto`（从源 TileMapLayer 均分生成滑块）与 `PuzzleBoardShuffler`（加载时随机打乱并作为新初始布局），并迁移 `room_02_00`。

**Architecture:** 自动板是 `PuzzleBoard` 的 `@tool` 子类，只新增「读源图层 → 拆分 → 生成 `PuzzleTilePiece`」；打乱由纯逻辑 `PuzzleScrambler` + 薄节点 `PuzzleBoardShuffler` 组成，`PuzzleBoard` 增加 `apply_initial_layout` / `scramble` 两个公开方法。规范见 `docs/superpowers/specs/2026-10-25-puzzle-auto-board-and-shuffle-design.md`。

**Tech Stack:** Godot 4.7 / GDScript / 现有 `PuzzleSession`、`SlidingPuzzleRuleSet`、`PuzzleTilePiece`、`RoomBaker`、headless 测试套件。

**Status:** Implemented 2026-10-25. Tasks 1-5 are complete; the headless runtime suite passes.

---

## 文件结构

- Create: `scripts/puzzle/systems/puzzle_scrambler.gd` — 纯逻辑随机走步。
- Create: `scripts/puzzle/view/puzzle_board_shuffler.gd` — 打乱节点组件。
- Create: `scripts/puzzle/view/puzzle_board_auto.gd` — 自动生成棋盘（`@tool`）。
- Modify: `scripts/puzzle/view/puzzle_board.gd` — 追加 `apply_initial_layout` / `scramble`。
- Create: `tests/puzzle/test_puzzle_board_shuffler.gd` — 打乱（纯逻辑 + 节点）。
- Create: `tests/puzzle/test_puzzle_board_auto.gd` — 自动拆分。
- Create: `tests/puzzle/test_puzzle_auto_room.gd` — 迁移后的运行时场景契约。
- Modify: `tests/runtime_suite.gd` — 注册三个新测试。
- Modify: `scenes/levels/main_world/room_02_00.tscn` — 迁移（文本补丁 + 编辑器保存）。
- Create (migration outputs): `scenes/rooms/generated/main_room_02_00/*`（重烘）。
- Modify: `docs/extension-guide.md`、`游戏机制设计.md`。

## 验证命令

- 聚焦：`godot --headless --path . -s res://_tmp_run_puzzle_tests.gd`（临时 runner，用完删除）。
- 全量：`godot --headless --path . -s res://tests/run_runtime_suite.gd`。
- 烘焙：一次性 headless 脚本调用 `RoomBaker.bake`（用完删除）。

---

### Task 1: `PuzzleScrambler` 纯逻辑

**Files:**
- Create: `scripts/puzzle/systems/puzzle_scrambler.gd`
- Test: `tests/puzzle/test_puzzle_board_shuffler.gd`

- [ ] **Step 1: 写失败测试（纯逻辑部分）**

```gdscript
extends Node

const PuzzleScrambler := preload("res://scripts/puzzle/systems/puzzle_scrambler.gd")
const SlidingPuzzleRuleSet := preload("res://scripts/puzzle/rules/sliding_puzzle_rule_set.gd")
const PuzzleSession := preload("res://scripts/puzzle/systems/puzzle_session.gd")
const PUZZLE_BOARD := preload("res://scripts/puzzle/view/puzzle_board.gd")
const PUZZLE_SHUFFLER := preload("res://scripts/puzzle/view/puzzle_board_shuffler.gd")
const TILESET := preload("res://resources/tilesets/primordial_tileset.tres")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_scrambler_walks_around_void(failures)
	_assert_scrambler_is_deterministic(failures)
	_assert_scrambler_void_only_filter(failures)
	_assert_scrambler_rejects_packed_board(failures)
	_assert_board_scramble_updates_initial_layout(failures)
	_assert_shuffler_node_scrambles_on_ready(failures)
	return failures


func _assert_scrambler_walks_around_void(failures: Array[String]) -> void:
	var def := _definition(Vector2i(4, 4), [
		_piece(&"a", Vector2i(0, 0), Vector2i(2, 2), false),
		_piece(&"b", Vector2i(2, 0), Vector2i(2, 2), false),
		_piece(&"c", Vector2i(0, 2), Vector2i(2, 2), false),
		_piece(&"v", Vector2i(2, 2), Vector2i(2, 2), true),
	])
	var rules := SlidingPuzzleRuleSet.new(def)
	var start := PuzzleSession.new(def).current_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var result: Variant = PuzzleScrambler.build_scrambled_state(def, rules, start, 40, rng, true, true)
	if result == null:
		failures.append("scrambler returned null for a board with a void slider")
		return
	if result.get_hash_key() == start.get_hash_key():
		failures.append("scrambler returned the start layout")
	_assert_state_legal(def, result, failures, "void walk")


func _assert_scrambler_is_deterministic(failures: Array[String]) -> void:
	var def := _void_board()
	var rules := SlidingPuzzleRuleSet.new(def)
	var start := PuzzleSession.new(def).current_state
	var first: Variant = _scramble_with_seed(def, rules, start, 4242)
	var second: Variant = _scramble_with_seed(def, rules, start, 4242)
	if first == null or second == null or first.get_hash_key() != second.get_hash_key():
		failures.append("same seed produced different scrambled layouts")
	var other: Variant = _scramble_with_seed(def, rules, start, 99)
	if other != null and other.get_hash_key() == first.get_hash_key():
		failures.append("different seeds produced the same scrambled layout")


func _assert_scrambler_void_only_filter(failures: Array[String]) -> void:
	var def := _definition(Vector2i(4, 4), [
		_piece(&"a", Vector2i(0, 0), Vector2i(2, 2), false),
		_piece(&"b", Vector2i(2, 0), Vector2i(2, 2), false),
		_piece(&"c", Vector2i(0, 2), Vector2i(2, 2), false),
	])
	var rules := SlidingPuzzleRuleSet.new(def)
	var start := PuzzleSession.new(def).current_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	if PuzzleScrambler.build_scrambled_state(def, rules, start, 20, rng, true, true) != null:
		failures.append("void_only scramble succeeded on a board without void sliders")
	rng.seed = 5
	var result: Variant = PuzzleScrambler.build_scrambled_state(def, rules, start, 20, rng, false, true)
	if result == null or result.get_hash_key() == start.get_hash_key():
		failures.append("non-void_only scramble did not move a board with an empty slot")
	else:
		_assert_state_legal(def, result, failures, "empty slot")


func _assert_scrambler_rejects_packed_board(failures: Array[String]) -> void:
	var def := _definition(Vector2i(4, 4), [
		_piece(&"a", Vector2i(0, 0), Vector2i(2, 2), false),
		_piece(&"b", Vector2i(2, 0), Vector2i(2, 2), false),
		_piece(&"c", Vector2i(0, 2), Vector2i(2, 2), false),
		_piece(&"d", Vector2i(2, 2), Vector2i(2, 2), false),
	])
	var rules := SlidingPuzzleRuleSet.new(def)
	var start := PuzzleSession.new(def).current_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	if PuzzleScrambler.build_scrambled_state(def, rules, start, 20, rng, false, true) != null:
		failures.append("scrambler moved a packed board with no empty slot")
```

- [ ] **Step 2: 运行，确认失败**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: 失败（`puzzle_scrambler.gd` 不存在 / `build_scrambled_state` 未定义）。

- [ ] **Step 3: 实现 `PuzzleScrambler`**

```gdscript
class_name PuzzleScrambler
extends RefCounted

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
) -> BoardState:
	if definition == null or rules == null or start_state == null or rng == null:
		return null
	if definition.pieces.is_empty() or start_state.pieces.is_empty():
		return null
	var state := start_state.duplicate_state()
	var target_steps := maxi(1, steps)
	var step := 0
	var last_primary: PuzzleMove = null
	while step < target_steps or (
		step < target_steps + MAX_EXTRA_STEPS
		and state.get_hash_key() == start_state.get_hash_key()
	):
		var turn := _pick_turn(definition, rules, state, rng, void_only, avoid_reverse, last_primary)
		if turn == null:
			return null if step == 0 else state
		for move: PuzzleMove in turn.moves:
			state = rules.apply_move(state, move)
		last_primary = turn.moves[0]
		step += 1
	return state


static func _pick_turn(
	definition: PuzzleDefinition,
	rules: PuzzleRuleSet,
	state: BoardState,
	rng: RandomNumberGenerator,
	void_only: bool,
	avoid_reverse: bool,
	last_primary: PuzzleMove
) -> PuzzleTurn:
	var candidates: Array[PuzzleTurn] = []
	var fallback: Array[PuzzleTurn] = []
	for move: PuzzleMove in rules.get_legal_moves(state):
		var turn := rules.resolve_turn(state, move)
		if turn == null or turn.is_empty():
			continue
		if void_only and not _turn_touches_void(definition, turn):
			continue
		fallback.append(turn)
		if avoid_reverse and _is_reverse_of(turn.moves[0], last_primary):
			continue
		candidates.append(turn)
	if candidates.is_empty():
		candidates = fallback
	if candidates.is_empty():
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _turn_touches_void(definition: PuzzleDefinition, turn: PuzzleTurn) -> bool:
	for move: PuzzleMove in turn.moves:
		if move.piece_index < 0 or move.piece_index >= definition.pieces.size():
			continue
		if definition.pieces[move.piece_index].is_void:
			return true
	return false


static func _is_reverse_of(move: PuzzleMove, previous: PuzzleMove) -> bool:
	if move == null or previous == null:
		return false
	return move.piece_index == previous.piece_index and move.get_direction() == -previous.get_direction()
```

- [ ] **Step 4: 运行，确认纯逻辑测试通过**（棋盘/节点测试仍失败，Task 2 处理）。

- [ ] **Step 5: 提交**

```bash
git add scripts/puzzle/systems/puzzle_scrambler.gd tests/puzzle/test_puzzle_board_shuffler.gd
git commit -m "feat: add puzzle scrambler random walk"
```

---

### Task 2: `PuzzleBoard` API + `PuzzleBoardShuffler`

**Files:**
- Modify: `scripts/puzzle/view/puzzle_board.gd`（文件末尾追加两个方法）
- Create: `scripts/puzzle/view/puzzle_board_shuffler.gd`
- Test: `tests/puzzle/test_puzzle_board_shuffler.gd`（补棋盘/节点测试与辅助函数）

- [ ] **Step 1: 写失败测试（棋盘 + 节点）**

```gdscript
func _assert_board_scramble_updates_initial_layout(failures: Array[String]) -> void:
	var board := _make_board_with_void()
	var start := board.session.current_state.get_hash_key()
	if not board.scramble(40, 7, true, true):
		failures.append("PuzzleBoard.scramble returned false on a board with a void slider")
		return
	if board.session.current_state.get_hash_key() == start:
		failures.append("PuzzleBoard.scramble did not change the layout")
	var state: Variant = board.session.current_state
	for i in state.pieces.size():
		if board.definition.pieces[i].initial_cell != state.pieces[i].cell:
			failures.append("scramble did not adopt piece %d as new initial cell" % i)
	if board.session.get_move_count() != 0:
		failures.append("scramble left a non-zero move count")
	if board.session.undo():
		failures.append("scramble left an undo entry")
	if board.session.reset():
		failures.append("reset after scramble was not a no-op")
	var pieces: Array[PuzzlePiece] = []
	for child in board.get_children():
		if child is PuzzlePiece:
			pieces.append(child as PuzzlePiece)
	if pieces.size() != state.pieces.size():
		failures.append("scrambled board lost pieces")
	for i in pieces.size():
		if pieces[i].get_logical_cell() != state.pieces[i].cell:
			failures.append("piece %d node cell was not synced after scramble" % i)
		if not pieces[i].position.is_equal_approx(pieces[i].cell_to_world(state.pieces[i].cell)):
			failures.append("piece %d node position was not synced after scramble" % i)
	_assert_state_legal(board.definition, state, failures, "board scramble")


func _assert_shuffler_node_scrambles_on_ready(failures: Array[String]) -> void:
	var root := Node2D.new()
	add_child(root)
	var board := _make_board_with_void()
	root.add_child(board)
	var start := board.session.current_state.get_hash_key()
	var shuffler := PUZZLE_SHUFFLER.new() as PuzzleBoardShuffler
	shuffler.board_path = ^"../PuzzleBoard"
	shuffler.steps = 40
	shuffler.seed = 11
	root.add_child(shuffler)
	if board.session.current_state.get_hash_key() == start:
		failures.append("PuzzleBoardShuffler did not scramble a sibling board on ready")
	if not shuffler.shuffle_now():
		failures.append("PuzzleBoardShuffler.shuffle_now returned false")


func _make_board_with_void() -> PuzzleBoard:
	var board := PUZZLE_BOARD.new() as PuzzleBoard
	board.board_size = Vector2i(4, 4)
	board.cell_size = 8
	board.add_child(_make_tile_piece(Vector2i(0, 0), false))
	board.add_child(_make_tile_piece(Vector2i(2, 0), false))
	board.add_child(_make_tile_piece(Vector2i(0, 2), false))
	board.add_child(_make_tile_piece(Vector2i(2, 2), true))
	add_child(board)
	return board


func _make_tile_piece(cell: Vector2i, is_void: bool) -> PuzzleTilePiece:
	var piece := PuzzleTilePiece.new()
	piece.position = Vector2(cell * 8)
	piece.x_move_distance = 2
	piece.y_move_distance = 2
	var layer := TileMapLayer.new()
	layer.name = "VoidTiles" if is_void else "SolidTiles"
	layer.tile_set = TILESET
	layer.collision_enabled = not is_void
	for y in 2:
		for x in 2:
			layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 5) if is_void else Vector2i(0, 0))
	piece.add_child(layer)
	return piece


func _definition(board_size: Vector2i, pieces: Array) -> PuzzleDefinition:
	var def := PuzzleDefinition.new()
	def.board = BoardDefinition.new()
	def.board.board_size = board_size
	var index := 0
	for piece: PieceDefinition in pieces:
		piece.id = StringName("piece_%d" % index)
		def.pieces.append(piece)
		index += 1
	return def


func _piece(id: StringName, cell: Vector2i, size: Vector2i, is_void: bool) -> PieceDefinition:
	var piece := PieceDefinition.new()
	piece.id = id
	piece.shape = PieceDefinition.make_rect_shape(size)
	piece.initial_cell = cell
	piece.is_void = is_void
	piece.enable = not is_void
	piece.x_move_distance = size.x
	piece.y_move_distance = size.y
	return piece


func _void_board() -> PuzzleDefinition:
	return _definition(Vector2i(4, 4), [
		_piece(&"a", Vector2i(0, 0), Vector2i(2, 2), false),
		_piece(&"b", Vector2i(2, 0), Vector2i(2, 2), false),
		_piece(&"c", Vector2i(0, 2), Vector2i(2, 2), false),
		_piece(&"v", Vector2i(2, 2), Vector2i(2, 2), true),
	])


func _scramble_with_seed(def: PuzzleDefinition, rules: PuzzleRuleSet, start: BoardState, seed_value: int) -> Variant:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return PuzzleScrambler.build_scrambled_state(def, rules, start, 40, rng, true, true)


func _assert_state_legal(def: PuzzleDefinition, state: BoardState, failures: Array[String], label: String) -> void:
	var occupied: Dictionary = {}
	for i in state.pieces.size():
		var piece_def: PieceDefinition = def.pieces[i]
		var cell: Vector2i = state.pieces[i].cell
		for offset: Vector2i in piece_def.shape:
			var world := cell + offset
			if not def.board.contains_cell(world):
				failures.append("%s: piece %d left the board at %s" % [label, i, world])
			if not piece_def.is_void:
				if occupied.has(world):
					failures.append("%s: normal pieces overlap at %s" % [label, world])
				occupied[world] = true
```

- [ ] **Step 2: 运行，确认失败**（`scramble` / `PuzzleBoardShuffler` 未定义）。

- [ ] **Step 3: 实现 `PuzzleBoard` API**

```gdscript
## Adopt [param state] as the authored initial layout: every piece's initial
## cell becomes its current cell, the move history is cleared and the view
## snaps to the new layout. Used by the shuffler.
func apply_initial_layout(state: BoardState) -> void:
	if session == null or definition == null or state == null:
		return
	if state.pieces.size() != definition.pieces.size() or _pieces.size() != state.pieces.size():
		return
	for i in state.pieces.size():
		definition.pieces[i].initial_cell = state.pieces[i].cell
	session.clear_rider()
	_deselect_piece(true)
	_end_drag()
	_hide_preview()
	session.reset_initial()
	_sync_pieces_from_state(false)


## Random-walk the board with the sliding rules and make the result the new
## initial layout. Returns false when the board cannot be scrambled.
func scramble(steps: int = 120, seed: int = 0, void_only: bool = true, avoid_reverse: bool = true) -> bool:
	if session == null or definition == null or definition.pieces.is_empty():
		return false
	session.clear_rider()
	var rng := RandomNumberGenerator.new()
	if seed == 0:
		rng.randomize()
	else:
		rng.seed = seed
	var start_state := session.current_state
	var scrambled := PuzzleScrambler.build_scrambled_state(
		definition,
		session.rules,
		start_state,
		maxi(1, steps),
		rng,
		void_only,
		avoid_reverse
	)
	if scrambled == null or scrambled.get_hash_key() == start_state.get_hash_key():
		return false
	apply_initial_layout(scrambled)
	return true
```

- [ ] **Step 4: 实现 `PuzzleBoardShuffler`**

```gdscript
class_name PuzzleBoardShuffler
extends Node

## Scrambles a PuzzleBoard on load by walking random legal turns.
##
## Place it after the board (as a later sibling) to scramble synchronously
## during the scene's ready pass, or as a child of the board and let it wait
## for the board's ready signal.

@export var board_path: NodePath = ^".."
@export var shuffle_on_ready: bool = true
@export var steps: int = 120
@export var seed: int = 0
@export var void_only: bool = true
@export var avoid_reverse: bool = true


func _ready() -> void:
	if not shuffle_on_ready:
		return
	var board := _get_board()
	if board == null:
		push_warning("PuzzleBoardShuffler %s: board_path does not point at a PuzzleBoard." % name)
		return
	if board.is_node_ready():
		shuffle_now()
	else:
		await board.ready
		shuffle_now()


## Scramble immediately. Returns false when the board has no legal turn to walk.
func shuffle_now() -> bool:
	var board := _get_board()
	if board == null:
		push_warning("PuzzleBoardShuffler %s: board_path does not point at a PuzzleBoard." % name)
		return false
	if not board.scramble(steps, seed, void_only, avoid_reverse):
		push_warning("PuzzleBoardShuffler %s: the board could not be scrambled." % name)
		return false
	return true


func _get_board() -> PuzzleBoard:
	if board_path.is_empty():
		return null
	return get_node_or_null(board_path) as PuzzleBoard
```

- [ ] **Step 5: 运行，确认通过。**

- [ ] **Step 6: 提交**

```bash
git add scripts/puzzle/view/puzzle_board.gd scripts/puzzle/view/puzzle_board_shuffler.gd tests/puzzle/test_puzzle_board_shuffler.gd
git commit -m "feat: scramble puzzle boards around void sliders"
```

---

### Task 3: `PuzzleBoardAuto`

**Files:**
- Create: `scripts/puzzle/view/puzzle_board_auto.gd`
- Test: `tests/puzzle/test_puzzle_board_auto.gd`

- [ ] **Step 1: 写失败测试**

```gdscript
extends Node

const AUTO_BOARD := preload("res://scripts/puzzle/view/puzzle_board_auto.gd")
const TILESET := preload("res://resources/tilesets/primordial_tileset.tres")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_split_creates_pieces(failures)
	_assert_generation_is_idempotent(failures)
	_assert_void_enable_flag(failures)
	_assert_missing_source_is_rejected(failures)
	return failures


func _assert_split_creates_pieces(failures: Array[String]) -> void:
	var board := _make_board(true)
	if not board.generate_pieces():
		failures.append("PuzzleBoardAuto.generate_pieces returned false for a valid picture")
		return
	if board.board_size != Vector2i(4, 4):
		failures.append("board_size was not derived from puzzle_size * piece_size")
	if board.get_generated_pieces().size() != 4:
		failures.append("expected 4 generated pieces, got %d" % board.get_generated_pieces().size())
	var piece_10 := board.get_node_or_null("Piece_1_0") as PuzzleTilePiece
	var piece_11 := board.get_node_or_null("Piece_1_1") as PuzzleTilePiece
	if piece_10 == null or piece_11 == null:
		failures.append("generated piece names are not Piece_<chunk_x>_<chunk_y>")
		add_child(board)
		return
	if piece_10.position != Vector2(16.0, 0.0) or piece_11.position != Vector2(16.0, 16.0):
		failures.append("generated pieces are not placed at their chunk origins")
	if piece_10.x_move_distance != 2 or piece_10.y_move_distance != 2:
		failures.append("generated pieces did not get piece_size as move distance")
	if not piece_10.enable:
		failures.append("normal generated pieces must be controllable")
	if not piece_11.is_void:
		failures.append("a chunk painted in the void layer was not generated as a void piece")
	if piece_11.enable:
		failures.append("void pieces must default to enable = false")
	if piece_11.z_index != 1:
		failures.append("void pieces must draw above normal pieces")
	var solid := piece_10.get_node_or_null("SolidTiles") as TileMapLayer
	if solid == null or not solid.collision_enabled:
		failures.append("normal pieces need a colliding SolidTiles layer")
	elif solid.get_used_cells().size() != 4:
		failures.append("SolidTiles did not receive the chunk cells")
	elif solid.get_cell_atlas_coords(Vector2i(1, 1)) != Vector2i(0, 3):
		failures.append("chunk cells were not offset into piece-local coordinates")
	var void_layer := piece_11.get_node_or_null("VoidTiles") as TileMapLayer
	if void_layer == null or void_layer.collision_enabled:
		failures.append("void pieces need a non-colliding VoidTiles layer")
	elif piece_11.get_node_or_null("SolidTiles") != null:
		failures.append("void chunks must not also create SolidTiles")
	add_child(board)
	if piece_10.shape.size() != 4 or piece_11.shape.size() != 4:
		failures.append("generated tile pieces did not derive their footprints")
	if board.session == null or board.session.current_state.pieces.size() != 4:
		failures.append("PuzzleBoardAuto did not build a session from generated pieces")
	if board.session != null and not board.session.definition.pieces[3].is_void:
		failures.append("the generated void piece was not registered as void")


func _assert_generation_is_idempotent(failures: Array[String]) -> void:
	var board := _make_board(true)
	board.generate_pieces()
	board.generate_pieces()
	if board.get_generated_pieces().size() != 4:
		failures.append("regeneration duplicated generated pieces")
	var piece := board.get_node_or_null("Piece_1_1") as PuzzleTilePiece
	if piece == null or piece.get_node("VoidTiles").get_used_cells().size() != 4:
		failures.append("regeneration dropped generated cell data")
	board.free()


func _assert_void_enable_flag(failures: Array[String]) -> void:
	var board := _make_board(true)
	board.void_enable = true
	board.generate_pieces()
	var void_piece := board.get_node_or_null("Piece_1_1") as PuzzleTilePiece
	if void_piece == null or not void_piece.enable:
		failures.append("void_enable = true did not enable the generated void piece")
	board.free()


func _assert_missing_source_is_rejected(failures: Array[String]) -> void:
	var board := AUTO_BOARD.new() as PuzzleBoardAuto
	board.puzzle_size = Vector2i(2, 2)
	board.piece_size = Vector2i(2, 2)
	if board.generate_pieces():
		failures.append("generate_pieces succeeded without a source layer")
	if not board.get_generated_pieces().is_empty():
		failures.append("generate_pieces modified the board on failure")
	board.free()


func _make_board(with_void: bool) -> PuzzleBoardAuto:
	var board := AUTO_BOARD.new() as PuzzleBoardAuto
	board.puzzle_size = Vector2i(2, 2)
	board.piece_size = Vector2i(2, 2)
	board.cell_size = 8
	var source := _layer("PictureSource", [
		{"cell": Vector2i(0, 0), "atlas": Vector2i(0, 0)}, {"cell": Vector2i(1, 0), "atlas": Vector2i(0, 0)},
		{"cell": Vector2i(0, 1), "atlas": Vector2i(0, 0)}, {"cell": Vector2i(1, 1), "atlas": Vector2i(0, 0)},
		{"cell": Vector2i(2, 0), "atlas": Vector2i(0, 3)}, {"cell": Vector2i(3, 0), "atlas": Vector2i(0, 3)},
		{"cell": Vector2i(2, 1), "atlas": Vector2i(0, 3)}, {"cell": Vector2i(3, 1), "atlas": Vector2i(0, 3)},
		{"cell": Vector2i(0, 2), "atlas": Vector2i(0, 0)}, {"cell": Vector2i(1, 2), "atlas": Vector2i(0, 0)},
		{"cell": Vector2i(0, 3), "atlas": Vector2i(0, 0)}, {"cell": Vector2i(1, 3), "atlas": Vector2i(0, 0)},
	])
	board.add_child(source)
	board.source_layer_path = ^"PictureSource"
	if with_void:
		var void_source := _layer("VoidSource", [
			{"cell": Vector2i(2, 2), "atlas": Vector2i(0, 5)}, {"cell": Vector2i(3, 2), "atlas": Vector2i(0, 5)},
			{"cell": Vector2i(2, 3), "atlas": Vector2i(0, 5)}, {"cell": Vector2i(3, 3), "atlas": Vector2i(0, 5)},
		])
		board.add_child(void_source)
		board.void_layer_path = ^"VoidSource"
	return board


func _layer(layer_name: String, cells: Array) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = TILESET
	layer.collision_enabled = false
	for entry: Dictionary in cells:
		layer.set_cell(entry["cell"], 0, entry["atlas"], 0)
	return layer
```

- [ ] **Step 2: 运行，确认失败。**

- [ ] **Step 3: 实现 `PuzzleBoardAuto`**

按 spec 实现：`@tool`、导出参数、`generate_pieces()`、`_split_layout()`、
`_create_piece()`、`_clear_generated_pieces()`、编辑器签名防抖重建、
`_get_configuration_warnings()`、运行时 `super._ready()`。
手动重建按钮用 `@export_tool_button("重新生成", "Reload")`。

- [ ] **Step 4: 运行，确认通过。**

- [ ] **Step 5: 提交**

```bash
git add scripts/puzzle/view/puzzle_board_auto.gd tests/puzzle/test_puzzle_board_auto.gd
git commit -m "feat: auto-split tilemap pictures into puzzle sliders"
```

---

### Task 4: 迁移 `room_02_00` 并重烘

**Files:**
- Modify: `scenes/levels/main_world/room_02_00.tscn`
- Regenerate: `scenes/rooms/generated/main_room_02_00/runtime.tscn`（及 `terrain.tscn`、`resources/rooms/generated/main_room_02_00.tres`）
- Test: `tests/puzzle/test_puzzle_auto_room.gd`

- [ ] **Step 1: 写失败测试**

```gdscript
extends Node

const AUTO_BOARD := preload("res://scripts/puzzle/view/puzzle_board_auto.gd")
const RUNTIME := "res://scenes/rooms/generated/main_room_02_00/runtime.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	var scene: PackedScene = load(RUNTIME)
	if scene == null:
		failures.append("main_room_02_00 runtime scene is missing")
		return failures
	var root: Node = scene.instantiate()
	add_child(root)
	if root.get_node_or_null("PreviewOnly") != null:
		failures.append("PreviewOnly leaked into the baked runtime scene")
	var board: Node = root.get_node_or_null("Entities/PuzzleBoard")
	if board == null or board.get_script() != AUTO_BOARD:
		failures.append("main_room_02_00 PuzzleBoard is not a PuzzleBoardAuto")
		root.free()
		return failures
	if board.board_size != Vector2i(21, 21):
		failures.append("main_room_02_00 board is not 21x21 cells")
	var pieces: Array = board.call("get_generated_pieces")
	if pieces.size() != 9:
		failures.append("main_room_02_00 should generate 9 sliders, got %d" % pieces.size())
	var void_count := 0
	for piece: PuzzleTilePiece in pieces:
		if piece.is_void:
			void_count += 1
			if piece.shape.size() != 25 or piece.get_bounds() != Rect2i(0, 0, 7, 7):
				failures.append("main_room_02_00 void slider is not the 25-cell diamond")
	if void_count != 1:
		failures.append("main_room_02_00 should have exactly one void slider")
	var moved := 0
	for piece: PuzzleTilePiece in pieces:
		if piece.get_logical_cell() != Vector2i(piece.get_meta(&"authored_cell")):
			moved += 1
	if moved == 0:
		failures.append("the shuffler did not scramble main_room_02_00 on load")
	if root.get_node_or_null("Entities/PuzzleBoardShuffler") == null:
		failures.append("main_room_02_00 is missing the PuzzleBoardShuffler")
	root.free()
	return failures
```

说明：`PuzzleBoardAuto` 在生成每个 Piece 时写入 `set_meta(&"authored_cell", chunk_origin)`，
因此「打乱后至少有一块离开作者锚点」可以用该 meta 稳定断言（打乱自身保证结果 ≠ 起点）。

- [ ] **Step 2: 迁移源场景**

用一次性 headless 脚本（不进版本库）：
1. 实例化 `res://scenes/levels/main_world/room_02_00.tscn`，读取 9 个 `PuzzleTilePiece` 的格子，
   构建合并后的 `PuzzleSourceTiles`（392 格）与 `PuzzleVoidTiles`（25 格）TileMapLayer，
   打印 `var_to_str(tile_map_data)`。
2. Python 文本补丁：
   - 新增两个 `ext_resource`（`puzzle_board_auto.gd`、`puzzle_board_shuffler.gd`，可省略 uid）；
   - Board 节点脚本换成自动板，追加 `puzzle_size` / `piece_size` / 源图层 NodePath；
   - 删除 9 个 Piece 节点块及其子层块；
   - 在文件末尾追加 `PreviewOnly` 下的两个源 TileMapLayer（带 `tile_map_data`）与
     `RoomContent/Entities` 下的 `PuzzleBoardShuffler`（`board_path = NodePath("../PuzzleBoard")`）。
3. 用 MCP `godot_scene reload` 让 `@tool` 重建并 `godot_scene save`。
4. 校验：重新加载源场景，断言 9 个 Piece、1 个虚空 25 格、源图层存在。

- [ ] **Step 3: 重烘**

一次性 headless 脚本调用 `RoomBaker.bake(instantiate(SOURCE), SOURCE)`，然后加载
`runtime.tscn` 验证。

- [ ] **Step 4: 运行新测试，确认通过。**

- [ ] **Step 5: 提交**

```bash
git add scenes/levels/main_world/room_02_00.tscn scenes/rooms/generated/main_room_02_00 resources/rooms/generated/main_room_02_00.tres tests/puzzle/test_puzzle_auto_room.gd
git commit -m "feat: move room_02_00 puzzle to generated board and shuffle"
```

---

### Task 5: 文档、测试注册与全量验证

- [ ] **Step 1:** `tests/runtime_suite.gd` 注册三个新测试。
- [ ] **Step 2:** `docs/extension-guide.md` 与 `游戏机制设计.md` 补用法。
- [ ] **Step 3:** 全量运行 `godot --headless --path . -s res://tests/run_runtime_suite.gd`，确认无失败。
- [ ] **Step 4:** 用 MCP 打开 `main_room_02_00` 并截图，确认编辑器与运行时外观。
- [ ] **Step 5:** 提交文档与测试注册。
