# World Editor Workbench Design

日期：2026-10-25
项目：wellwell / 华容道平台跳跃
状态：已实现（2026-10-25），由无头运行时测试验证；主屏骨架写在 .tscn，列表/检查器的行内容由组件在运行时构建，诊断输出到编辑器 Output。

## 目标

重构 `addons/world_editor/` 的 World 主屏幕，解决：

- 房间列表缺失：只能点画布选中，房间多了找不到。
- 画布信息太少：只有地形，没有出生点/入口/实体，也没有烘焙状态。
- 不能多选/框选房间；没有批量操作。
- 错误/警告只有一行 Status；无法定位到房间或源场景。
- UI 只是按钮堆砌，没有信息层次和视觉设计。

本轮只做「界面 + 信息 + 多选/框选 + 诊断输出」。房间入驻流水线（New Room 向导、保存后自动重烘、Bake Stale）留给下一轮 spec。

## 已补充实现（原下一轮 spec）

- `New Room` 向导：写 inherited scene（继承 `world_editor/room_template_scene`），自动导入/烘焙/选中并打开源场景；错误信息保持英文。
- `Bake Stale (N)`：按指纹比对批量烘焙所有待重烘房间。
- 未做：源场景保存后自动重烘（需要文件系统监听，后续再评估）。
- 实体标注持久化进 `RoomData`；画布拖线连接入口；房间缩略图。
- 修改 `display_name` / `map_color` / `room_id` 等元数据（源场景是唯一真相）。

## 已确认的设计决策

- 布局采用 **A · 三栏工作台**：左房间列表｜中画布｜右检查器｜底部状态栏。
- 检查器**只读 + 起点设置**，不编辑元数据；单房间/批量动作放在顶部命令栏与右键菜单。
- 画布标记从**烘焙后的运行时场景**读取，只显示关键锚点（出生点/入口/存档点/道具/危险物/开关/ResetZone/自定义 WorldEntity），悬停给详情。
- 「待重烘」用 `RoomData.source_fingerprint` 与源场景 sha256 比对；不改数据模型和烘焙器。
- 框选=**相交即选中**；组拖动与批量删除各算**一次撤销**；`Delete` 不弹确认（可撤销）。
- `stale` 房间仍显示上次烘焙的标记。

## 窗口骨架与视觉

```
WorldEditorMain (VBoxContainer, 纵向扩展)
├─ WorldBar (HBox)          world picker · Save World · ⋯
├─ CommandBar (HBox)        [New Room][Add Existing] │ [Open Source][Bake][Validate] │
│                           [Validate World][Bake World] │ [Rooms][Inspector]
├─ Workspace (HSplit)
│  ├─ RoomListPanel (VBox)  搜索 · 房间 Tree · 计数
│  └─ CanvasSplit (HSplit)
│     ├─ LayoutCanvas (Control, clip_contents, focus_mode=ALL)
│     │  ├─ TerrainPreviewLayer
│     │  └─ MarkerLayer
│     └─ InspectorPanel (VBox, 只读 + 动作)
└─ StatusBar (HBox)         world 路径 · 房间数 · 选中数 · 缩放
```

- 原生 Godot 深色主题；图标取 `EditorIcons`；间距 4 的倍数；列表行高 22；分组标题 11px 大写弱化；分隔线 1px `#2c333f`。
- 状态色：已烘焙 `#4fae74`、待重烘 `#e08a3c`、失败 `#e05a5a`、选中 `#5aa9e6`。
- 画布底 `#101318`；房间标签两行（显示名 / `id · W×H · (cx,cy)`）+ 右上状态点；选中 2px 蓝框；多选显示 `N selected`。
- 列表/检查器可折叠；分隔条位置存 `EditorSettings` 项目元数据；折叠后画布占满。
- 空状态：未选 world → 居中提示 + New World；无房间 → Add Existing；无选中 → 检查器提示。
- 快捷键只做局部：`Delete` 移除引用、`Esc` 清空选择、`Ctrl+A` 全选（焦点在列表/画布）、双击打开源场景；不覆盖编辑器全局键。
- 命令分组：WorldBar 只放 world picker / Save / ⋯；CommandBar 四组主操作；右键菜单与检查器承载低频动作（Remove、Set as Start、Focus）。

## 房间列表

- `Tree`（单层多选，`SELECT_ROW`），列：状态点 · 显示名（缺省 id）· `W×H` 区块 · `(cx,cy)`；起点房间加 ★，不置顶。
- 排序：显示名 → id；搜索框按名称/id 过滤（重建行）。
- 单击选中并同步画布/检查器；`Ctrl/Shift` 多选；双击 = Open Source；右键 = Open Source / Bake / Validate / Set as Start / Focus / Remove Reference。
- 底部计数：`N rooms · M selected`。

## 状态计算

- `addons/world_editor/authoring/world/room_status_service.gd`（RefCounted，纯逻辑 + IO 适配器）：
  - `fresh`：`source_fingerprint == sha256(源场景)` 且 runtime/terrain 产物存在；
  - `stale`：指纹不一致；
  - `error`：源场景缺失 / 产物缺失 / 本次会话最近一次 Bake/Validate 失败；
  - `unknown`：world 未保存、房间无源路径或指纹为空。
- sha256 按 `(path, mtime, size)` 缓存；只在刷新/保存/烘焙/校验时重算。
- 列表与检查器共用同一份结果。

## 检查器（只读 + 动作）

- 头部状态徽章 + 说明。
- 字段：显示名、id、尺寸（区块 + 世界像素）、origin（区块 + 像素）、源场景路径、runtime / terrain 路径、`preview_spawn_id`、tags。
- 出生点列表（`S`，标出 world 起点 spawn）、入口列表（`E`，已连接时显示 `→ 目标房间 / spawn`）。
- 动作：只有 `Set as Start`（多 spawn 时用下拉选择）。单房间与批量动作统一由顶部命令栏（作用于整个选择）和房间列表/画布右键菜单提供，避免检查器与命令栏重复。
- 多选：只显示摘要（N 个房间、各状态计数），不重复放批量按钮。
- 元数据不可编辑。

## 画布

- 图层顺序：地形预览 → 标记 → 连接线/标签/选择/框选。
- 标记：实例化 `RoomData.scene_path`（不入树、读完即 free），递归匹配 `SpawnPoint` / `RoomEntrance` / `SavePoint` / `PickupEntity` / `HazardEntity` / `SwitchEntity` / `ResetZone` / `WorldEntity`，累积 `Transform2D` 得房间本地坐标；按 `(scene_path, mtime)` 缓存。
- 绘制：类型色块 + 深色描边（`S`/`E` 带字母），尺寸随缩放在 5–9px 钳制；悬停显示「名字 · 类型 · id · 位置」；点击选中所属房间，`Ctrl+点击` 切换多选。
- 房间标签 + 状态边框；`stale` 标记基于上次烘焙（tooltip 注明）。
- 多选/框选：空白左键拖动 = 框选（相交即选中）；`Ctrl+点击` 加/减选；`Esc` 清空；`Ctrl+A` 全选。
- 组拖动：整组同一位移，提交一次 UndoRedo 动作；单房间拖动保持现状。
- `Delete`：批量移除引用，一次 UndoRedo 动作，不弹确认。
- 平移：中键 / `Space+左键`；滚轮缩放不变。
- 世界起点：在 `start_room_id` + `start_spawn_id` 处画 ★，找不到 spawn 时退化为房间左上角。

## 诊断输出（替代独立问题面板）

- 不再有独立的问题面板/徽章。房间状态、本次会话 Bake/Validate 失败、`WorldLayoutModel.validate_world()` 的错误/警告直接打印到 Godot 编辑器 **Output**：
  `[World Editor][ERROR] ...` / `[World Editor][WARNING] ...`（英文，符合“报错只用英文”的约定）。
- 相同的诊断集合只在变化时打印一次，避免刷新时刷屏；单次动作的结果由动作本身打印。
- 列表/检查器仍显示每个房间的状态标签与说明。

## 文件结构

- 重建 `addons/world_editor/world_editor_main.tscn`（三栏骨架；具体行/字段内容由组件在运行时构建）。
- 保留并扩展 `addons/world_editor/world_editor_main.gd`（全部现有公开方法、`get_command_state()` 字段不变；新增 `set_selection(ids, primary)`）。
- 新增：
  - `world_room_list.gd`（extends Tree）
  - `world_room_inspector.gd`（extends VBoxContainer）
  - `world_problems_panel.gd`（extends VBoxContainer）
  - `world_marker_layer.gd`（extends Control）
  - `authoring/world/room_status_service.gd`
  - `authoring/world/room_annotation_service.gd`
- 扩展：`world_layout_canvas.gd`（选择集合、框选、组拖动、键盘、标记层协调）。
- 选择模型：主屏持有 `selected_room_ids`（集合）+ `selected_room_id`（最后点击的主选中）；列表/画布/检查器统一走 `set_selection`。

## 测试

- 新增 `tests/authoring/test_room_status.gd`：fresh/stale/error/unknown、空指纹、缓存命中。
- 新增 `tests/authoring/test_room_annotations.gd`：`user://` 造运行时场景，断言类型/id/本地坐标/缓存/不残留实例。
- 扩展 `test_world_editor_main_screen.gd`：根仍 `VBoxContainer` 纵向扩展；新节点存在；`LayoutCanvas` 新路径 + `clip_contents`/`focus_mode` 不变；CommandBar 分组。
- 扩展 `test_world_canvas_view.gd`（或新增 selection 测试）：框选相交、Ctrl 切换、组拖动一次撤销、Esc、Delete 可撤销、标记命中。
- 扩展 `test_world_editor_commands.gd`：路径更新、`set_selection`、批量命令、`set_as_start` 命令状态。
- 现有 layout model / baker / importer / resource service 测试不动。

## 兼容与迁移

- 公开方法、命令状态字段、插件注册方式不变。
- `LayoutCanvas` 从根直接子节点移入 `CanvasSplit`，测试路径断言同步更新，属性保持。
- 旧 world / RoomData 无需迁移；指纹为空的房间显示 `unknown`（「无烘焙指纹，请重新烘焙」）。
- 文档：本 spec + `docs/extension-guide.md` 的 World Editor 段落补状态/标记/多选/诊断输出。

## 风险

- 实例化运行时场景可能触发 `@tool` 脚本：只 `instantiate()` 不入树，读完 `free()`。
- sha256 刷新成本：按 `(path, mtime, size)` 缓存，只在用户动作时重算。
- 标记过密：当前房间规模可接受；后续可按缩放隐藏低优先级标记。
- 编辑器运行中重写 addon 脚本：实现后检查文件内容，必要时重启编辑器再验证。
