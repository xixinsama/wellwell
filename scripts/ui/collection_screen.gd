class_name CollectionScreen
extends Control

## Collection screen and its always-on badge.
##
## The badge shows how many of the current world's numbered collectibles are
## collected. The overlay lists every number the world contains, collected ones
## bright and missing ones dim, so a player can see exactly which one is left.
## It is drawn in the HUD outside the game SubViewport, so it stays sharp.
##
## The full set comes from [Collectibles], which scans the world's baked rooms;
## the author only fills a number on each [NumberPickup].

const REGISTRY := "/root/Collectibles"
const ACTION := &"collection_toggle"

@onready var _badge: PanelContainer = %Badge
@onready var _badge_label: Label = %BadgeLabel
@onready var _overlay: Control = %Overlay
@onready var _grid: GridContainer = %Grid
@onready var _count: Label = %Count

var _registry: Node
var _was_paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible = false
	_registry = get_node_or_null(REGISTRY)
	if _registry != null and _registry.has_signal("changed") and not _registry.changed.is_connected(_refresh):
		_registry.changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _registry == null:
		return
	var world_id := String(_registry.get("current_world_id"))
	if not world_id.is_empty() and event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()
	elif _overlay.visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if _overlay.visible:
		return
	_was_paused = get_tree().paused
	get_tree().paused = true
	_rebuild()
	_overlay.visible = true


func close() -> void:
	if not _overlay.visible:
		return
	_overlay.visible = false
	get_tree().paused = _was_paused


func toggle() -> void:
	if _overlay.visible:
		close()
	else:
		open()


func is_open() -> bool:
	return _overlay.visible


func get_badge_text() -> String:
	return _badge_label.text


func _refresh() -> void:
	if _registry == null:
		_badge.visible = false
		return
	var world_id := String(_registry.get("current_world_id"))
	var total := int(_registry.call("get_total"))
	var collected := int(_registry.call("get_collected_count"))
	_badge.visible = not world_id.is_empty() and total > 0
	_badge_label.text = "图鉴 %d / %d" % [collected, total]
	if _overlay.visible:
		_rebuild()


func _rebuild() -> void:
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var numbers: Array = _registry.call("get_known_numbers")
	var collected := 0
	for number: Variant in numbers:
		var value := int(number)
		var is_collected := bool(_registry.call("is_collected", value))
		if is_collected:
			collected += 1
		_grid.add_child(_make_cell(value, is_collected))
	_count.text = "%d / %d" % [collected, numbers.size()]


func _make_cell(number: int, is_collected: bool) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.name = "Number%d" % number
	cell.custom_minimum_size = Vector2(38.0, 38.0)
	cell.set_meta(&"number", number)
	cell.set_meta(&"collected", is_collected)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(3)
	style.set_border_width_all(1)
	if is_collected:
		style.bg_color = Color(0.1, 0.18, 0.16, 1.0)
		style.border_color = Color(0.475, 0.949, 0.816, 0.95)
	else:
		style.bg_color = Color(0.05, 0.06, 0.07, 0.85)
		style.border_color = Color(0.3, 0.34, 0.38, 0.8)
	cell.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = str(number)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override(
		"font_color",
		Color(0.95, 1.0, 0.92) if is_collected else Color(0.5, 0.55, 0.58)
	)
	cell.add_child(label)
	return cell
