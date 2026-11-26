extends Node2D
## A readable note. Touch it, then press up to open the popup.
##
## The note owns its popup: it builds a CanvasLayer with the reading panel, so no
## HUD wiring is needed and the panel can point its tail at the note itself. The
## paper is drawn from polygons (no art dependency yet); replace the polygons with
## a sprite when the art lands.

const POPUP_SCRIPT := preload("res://game/ui/note_popup.gd")
const HINT_FONT := "res://assets/fonts/JetBrainsMono-Regular.ttf"

@export_multiline var note_text := "按下方向键「上」阅读这条笔记。"
@export var accent := Color(0.55, 0.92, 0.82, 1.0)
@export var paper := Color(0.93, 0.96, 0.92, 1.0)

var _near := false
var _popup: Control
var _hint: Label
var _layer: CanvasLayer
var _time := 0.0


func _ready() -> void:
	add_to_group(&"note_entity")
	_build_paper()
	_build_hint()
	var area := get_node_or_null("Sensor") as Area2D
	if area != null:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_time += delta
	if _hint != null and _hint.visible:
		_hint.position.y = -22.0 + sin(_time * 3.0) * 1.2
	if not _near:
		return
	# The gameplay viewport does not forward key events to world nodes, so the
	# prompt polls the action like the debug tool does.
	if Input.is_action_just_pressed(&"ui_up"):
		_toggle_popup()


func is_popup_open() -> bool:
	return _popup != null and _popup.visible


func get_note_text() -> String:
	return note_text


func _toggle_popup() -> void:
	if _popup != null and _popup.visible:
		_popup.call("hide_note")
		return
	if _popup == null:
		_build_popup()
	var anchor := get_global_transform_with_canvas().origin + Vector2(0.0, -14.0)
	_popup.call("show_note", note_text, anchor)


func _build_popup() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 12
	add_child(_layer)
	_popup = POPUP_SCRIPT.new() as Control
	_popup.name = "NotePopup"
	_layer.add_child(_popup)


func _build_paper() -> void:
	var sheet := Polygon2D.new()
	sheet.name = "Sheet"
	sheet.color = paper
	sheet.polygon = PackedVector2Array([
		Vector2(-4.0, -6.0), Vector2(3.0, -6.0), Vector2(4.0, -5.0),
		Vector2(4.0, 4.0), Vector2(-4.0, 4.0),
	])
	add_child(sheet)
	var fold := Polygon2D.new()
	fold.name = "Fold"
	fold.color = Color(paper.r, paper.g, paper.b, 0.55)
	fold.polygon = PackedVector2Array([
		Vector2(3.0, -6.0), Vector2(4.0, -5.0), Vector2(3.0, -5.0),
	])
	add_child(fold)
	var rule := Line2D.new()
	rule.name = "Rule"
	rule.width = 1.0
	rule.default_color = accent
	rule.points = PackedVector2Array([Vector2(-2.5, -3.0), Vector2(2.5, -3.0)])
	add_child(rule)
	var rule_b := Line2D.new()
	rule_b.name = "RuleB"
	rule_b.width = 1.0
	rule_b.default_color = Color(accent.r, accent.g, accent.b, 0.55)
	rule_b.points = PackedVector2Array([Vector2(-2.5, -0.5), Vector2(1.0, -0.5)])
	add_child(rule_b)


func _build_hint() -> void:
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "↑"
	_hint.visible = false
	_hint.add_theme_font_override("font", load(HINT_FONT) as Font)
	_hint.add_theme_font_size_override("font_size", 9)
	_hint.add_theme_color_override("font_color", accent)
	_hint.position = Vector2(-3.0, -22.0)
	add_child(_hint)


func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group(&"player"):
		return
	_near = true
	if _hint != null:
		_hint.visible = true


func _on_body_exited(body: Node) -> void:
	if body == null or not body.is_in_group(&"player"):
		return
	_near = false
	if _hint != null:
		_hint.visible = false
	if _popup != null and _popup.visible:
		_popup.call("hide_note")
