# World Editor Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 把 World 主屏幕重构为三栏工作台：房间列表（状态/搜索/多选）、信息更全的画布（实体标记/状态/框选）、只读检查器、问题面板。

**Architecture:** 保持 `WorldEditorMain` 的公开 API 与命令状态；UI 骨架写在 `world_editor_main.tscn`，行内容由 `world_room_list.gd` / `world_room_inspector.gd` / `world_problems_panel.gd` 在 `_ready` 构建；纯逻辑拆到 `room_status_service.gd` / `room_annotation_service.gd`（可无头测试）；画布扩展 `world_layout_canvas.gd` 负责选择集合、框选、组拖动与标记命中。

**Tech Stack:** Godot 4.7 / GDScript / 现有 `WorldData`、`RoomData`、`WorldLayoutModel`、`RoomBaker`、`tests/run_runtime_suite.gd`。

---

## 文件结构

- Create: `addons/world_editor/authoring/world/room_status_service.gd`
- Create: `addons/world_editor/authoring/world/room_annotation_service.gd`
- Create: `addons/world_editor/world_room_list.gd`
- Create: `addons/world_editor/world_room_inspector.gd`
- Create: `addons/world_editor/world_problems_panel.gd`
- Create: `addons/world_editor/world_marker_layer.gd`
- Rewrite: `addons/world_editor/world_editor_main.tscn`（三栏骨架）
- Modify: `addons/world_editor/world_editor_main.gd`（协调、选择模型、命令、问题聚合；保留全部现有方法）
- Modify: `addons/world_editor/world_layout_canvas.gd`（多选/框选/组拖动/键盘/标记命中）
- Test: `tests/authoring/test_room_status.gd`、`tests/authoring/test_room_annotations.gd`、`tests/authoring/test_world_canvas_selection.gd`
- Modify: `tests/authoring/test_world_editor_main_screen.gd`、`tests/authoring/test_world_editor_commands.gd`、`tests/runtime_suite.gd`
- Docs: `docs/extension-guide.md`（World Editor 段落）

## 验证命令

- 聚焦：`godot --headless --path . -s res://_tmp_run_world_tests.gd`（临时 runner，用完删除）
- 全量：`godot --headless --path . -s res://tests/run_runtime_suite.gd`
- 编辑器烟测：MCP `godot_editor_edit restart` → 打开 World 主屏幕 → `screenshot_editor`

---

### Task 1: `RoomStatusService`

**Files:** Create `addons/world_editor/authoring/world/room_status_service.gd`; Test `tests/authoring/test_room_status.gd`.

- [ ] **Step 1: 写失败测试**

构造 `RoomData`（`source_scene_path = "user://status_test.tscn"`、`source_fingerprint` 已知、`scene_path`/`terrain_scene_path` 指向真实存在的 `user://` 文件），并用适配器注入 `sha256` 与 `exists`，断言：

```gdscript
service.evaluate(room)  # fresh: fingerprint == hash 且两个产物存在
room.source_fingerprint = "old"   # stale
room.source_scene_path = "missing" # unknown（无源路径）
room.source_fingerprint = ""       # unknown
# error: 删掉 runtime 产物 / 最近一次 bake 失败（service.mark_bake_failure(room_id, msg)）
# 缓存：同一 (path, mtime, size) 只调用一次 hash_provider
```

- [ ] **Step 2: 运行确认失败**（脚本不存在）。
- [ ] **Step 3: 实现**

```gdscript
class_name RoomStatusService
extends RefCounted

const FRESH := &"fresh"
const STALE := &"stale"
const ERROR := &"error"
const UNKNOWN := &"unknown"

var hash_provider: Callable = Callable()   # (path) -> String
var exists_provider: Callable = Callable() # (path) -> bool
var _hash_cache: Dictionary = {}           # path -> {mtime, size, hash}
var _bake_failures: Dictionary = {}        # room_id -> message

func evaluate(room: RoomData) -> Dictionary   # {state, message}
func mark_bake_failure(room_id: String, message: String) -> void
func clear_bake_failure(room_id: String) -> void
```

规则：无 `source_scene_path` 或指纹为空 → `unknown`；源不存在 → `error`；`hash != fingerprint` → `stale`；`scene_path`/`terrain_scene_path` 缺失 → `error`；本会话 bake 失败 → `error`；否则 `fresh`。

- [ ] **Step 4: 运行确认通过；提交** `feat: add world room status service`.

---

### Task 2: `RoomAnnotationService`

**Files:** Create `addons/world_editor/authoring/world/room_annotation_service.gd`; Test `tests/authoring/test_room_annotations.gd`.

- [ ] **Step 1: 写失败测试**：用 `PackedScene` 在 `user://` 造一个运行时场景：

```gdscript
root (Node2D)
├─ Entities (Node2D)
│  ├─ Spawn (Marker2D + spawn_point.gd, spawn_id="start")  position=(16, 8)
│  ├─ Door (Marker2D + room_entrance.gd, entity_id="east") position=(48, 8)
│  ├─ Save (Node2D + save_point.gd)                        position=(24, 24)
│  └─ Custom (Node2D + world_entity.gd)                     position=(8, 32)
```
`RoomData.scene_path = "user://..."`；`service.collect(room)` 断言 4 个标注、类型、id、房间本地坐标（含父节点偏移）、`(path, mtime)` 缓存命中、实例不残留。

- [ ] **Step 2: 运行确认失败。**
- [ ] **Step 3: 实现**

```gdscript
class_name RoomAnnotationService
extends RefCounted

const ANNOTATION_SCRIPT := &"type"

func collect(room: RoomData) -> Array[Dictionary]  # [{type, id, name, position, node_path}]
```

- 实例化 `room.scene_path`（`PackedScene.instantiate()`），**不 add_child**；递归遍历 `get_children()`，用 `is SpawnPoint` / `is RoomEntrance` / ... 匹配；用 `Transform2D` 累乘 `node.transform` 得到房间本地坐标；`instance.free()`；按 `(path, mtime)` 缓存数组。
- 类型标签：`spawn` / `entrance` / `save` / `pickup` / `hazard` / `switch` / `reset_zone` / `world_entity`。

- [ ] **Step 4: 运行确认通过；提交** `feat: collect world room annotations`.

---

### Task 3: 三栏骨架 + 房间列表

**Files:** Rewrite `addons/world_editor/world_editor_main.tscn`；Create `world_room_list.gd`；Modify `world_editor_main.gd`.

- [ ] **Step 1: 写失败测试**（扩展 `test_world_editor_main_screen.gd`）：instantiate 场景后 `get_node` 断言 `WorldBar/CommandBar/Workspace/RoomListPanel/CanvasSplit/LayoutCanvas/InspectorPanel/ProblemsPanel/StatusBar` 存在；`LayoutCanvas.clip_contents == true`、`focus_mode == ALL`；CommandBar 的四个分组容器顺序。
- [ ] **Step 2: 重写 `.tscn` 骨架**（根 `VBoxContainer` + script；`HSplitContainer` 嵌套；`LayoutCanvas` Control + 现有 canvas/terrain 脚本；`RoomList` Tree + `world_room_list.gd`；`Search` LineEdit；计数 Label）。
- [ ] **Step 3: 实现 `world_room_list.gd`**：4 列 Tree、`populate(rooms, statuses, selected_ids, start_room_id)`、搜索过滤、`item_selected`/`multi_selected` → `selection_changed(ids, primary)`、双击 `room_activated(room_id)`、右键菜单 `action_requested(action, room_id)`。
- [ ] **Step 4: `world_editor_main.gd` 接线**：`set_selection(ids, primary)`、`select_room` 复用、`_refresh` 填充列表与状态、`WorldBar`/`CommandBar` 按钮连接现有方法；保留全部公开方法。
- [ ] **Step 5: 运行聚焦测试；提交** `feat: add world editor workbench shell and room list`.

---

### Task 4: 检查器 + 问题面板

**Files:** Create `world_room_inspector.gd`、`world_problems_panel.gd`；Modify `world_editor_main.gd`.

- [ ] **Step 1: 写失败测试**：实例化主屏后 `set_selection`，断言检查器显示 id/尺寸/origin/源路径/状态；多选显示摘要；问题面板 `set_issues()` 后行数与计数、过滤、点击行发出 `issue_activated(room_id)`。
- [ ] **Step 2: 实现检查器**：`show_room(room, status, connections)`、`show_multi(rooms, statuses)`、`clear()`；动作按钮发出 `action_requested(action)`；`Set as Start` 用 `OptionButton` 选 spawn。
- [ ] **Step 3: 实现问题面板**：`set_issues(Array[Dictionary])`（`{severity, message, room_id, action}`）、过滤下拉、`Revalidate` 信号、行双击/点击定位；计数徽章 `update_badge(errors, warnings)`。
- [ ] **Step 4: 主屏聚合**：`_refresh` 里跑 `validate_world` + 状态服务 + 本会话 bake/validate 结果，生成 issues；问题面板点击 → `select_room` + `canvas.focus_room`。
- [ ] **Step 5: 运行聚焦测试；提交** `feat: add world room inspector and problems panel`.

---

### Task 5: 画布多选/框选/组拖动 + 标记

**Files:** Create `world_marker_layer.gd`；Modify `world_layout_canvas.gd`、`world_editor_main.gd`.

- [ ] **Step 1: 写失败测试**（`test_world_canvas_selection.gd`）：用假 WorldData（或真实 `main_world.tres` 副本）设置房间矩形，调用 `begin_box_select` / `update_box_select` / `commit_box_select` 断言相交选中；`toggle_room_selection`；`move_selected_rooms(delta)` 断言所有选中房间位移一致且只产生一次 `UndoRedo` 动作（用假 adapter 记录 action 数）。
- [ ] **Step 2: 实现选择模型**：canvas 增加 `selected_room_ids: Array[String]`、`set_selection/get_selection`、`_box_selecting` 状态；`_gui_input`：空白左键按下进入框选，拖动更新矩形，松开提交；房间上左键拖动进入组拖动；`Esc`/`Ctrl+A`/`Delete` 发信号。
- [ ] **Step 3: 组拖动**：主屏 `move_selected_rooms_by(delta)` 用一次 `UndoRedo.create_action("Move Rooms")` + 每个房间一组 do/undo。
- [ ] **Step 4: 标记层**：`WorldMarkerLayer` 持有 `{room_id: annotations}`，`_draw` 画类型色块 + `S`/`E` 字母 + 描边；`_gui_input` 命中 → 发出 `marker_clicked(room_id)`；悬停 tooltip（用一个 `Label`/`PopupPanel`）；`world_editor_main` 在刷新时调用 `annotation_service.collect(room)` 并 `set_annotations`。
- [ ] **Step 5: 房间标签/状态边框**：canvas `_draw` 增加状态色、起点 ★、`W×H · (x,y)` 文本。
- [ ] **Step 6: 运行聚焦测试；提交** `feat: add world canvas selection, markers and status`.

---

### Task 6: 测试收尾、文档、烟测

- [ ] 更新 `test_world_editor_commands.gd` 的 `LayoutCanvas` 路径与命令状态断言；注册三个新测试进 `tests/runtime_suite.gd`。
- [ ] 全量：`godot --headless --path . -s res://tests/run_runtime_suite.gd`（exit 0）。
- [ ] 编辑器烟测：MCP 重启编辑器 → World 主屏幕 → 截图；确认三栏、列表、标记、问题面板可见。
- [ ] `docs/extension-guide.md` 补「World Editor 工作台」用法。
- [ ] 提交（只 stage 本轮文件，不碰用户/编辑器产生的其它改动）。

## 风险

- 编辑器运行中可能重写 addon 脚本：每步后 `grep` 关键符号；必要时重启编辑器再验证。
- `Tree` 多选/搜索的行为在无头测试里较繁琐：优先把「状态/标注/选择集合/组拖动」放在纯逻辑或 Control 层测试，UI 只做连接。
- 标记实例化可能触发 `@tool` 脚本：不 `add_child`，读完 `free()`。
