extends Control
## The reading popup: a rounded panel with a tail that points at the world object
## that opened it.
##
## The panel is drawn, not nine-sliced, so the tail can point anywhere along the
## bottom edge and the corner radius stays crisp at any scale. Text uses JetBrains
## Mono for latin and falls back to the serif CJK face for Chinese.

const LATIN_FONT := "res://assets/fonts/JetBrainsMono-Regular.ttf"
const CJK_FONT := "res://assets/fonts/SourceHanSerifCN-Regular-1.otf"

const PADDING := Vector2(10.0, 8.0)
const CORNER_RADIUS := 6.0
const TAIL_WIDTH := 9.0
const TAIL_HEIGHT := 7.0
const MAX_WIDTH := 168.0
const MIN_WIDTH := 52.0
const FADE_SECONDS := 0.14

const PANEL_COLOR := Color(0.043, 0.09, 0.11, 0.94)
const BORDER_COLOR := Color(0.44, 0.86, 0.79, 0.95)
const INNER_GLOW := Color(0.35, 0.95, 0.85, 0.14)
const TEXT_COLOR := Color(0.93, 0.97, 0.96, 1.0)

var _label: Label
var _panel := Rect2()
var _tail_x := 0.0
var _fade := 0.0
var _text := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	visible = false
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_font_size_override("font_size", 9)
	_label.add_theme_font_override("font", _ui_font())
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


## Show [param text] above the world point [param anchor] (a canvas position).
func show_note(text: String, anchor: Vector2) -> void:
	_text = text
	visible = true
	modulate.a = 0.0
	_layout(anchor)
	set_process(true)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, FADE_SECONDS)


func hide_note() -> void:
	if not visible:
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(func() -> void: visible = false)


func is_open() -> bool:
	return visible


func get_note_text() -> String:
	return _text


func _layout(anchor: Vector2) -> void:
	_label.add_theme_font_size_override("font_size", 9)
	var text_width := minf(MAX_WIDTH, _label.get_theme_font("font").get_string_size(
		_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9
	).x)
	text_width = maxf(MIN_WIDTH, text_width)
	_label.size = Vector2(text_width, 0.0)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(text_width, 0.0)
	_label.size = Vector2(text_width, _label.get_combined_minimum_size().y)
	var panel_size := _label.get_combined_minimum_size() + PADDING * 2.0
	panel_size.x = maxf(MIN_WIDTH, panel_size.x)
	var origin := anchor - Vector2(panel_size.x * 0.5, panel_size.y + TAIL_HEIGHT + 4.0)
	_panel = Rect2(origin, panel_size)
	_label.position = origin + PADDING
	_tail_x = clampf(anchor.x, origin.x + CORNER_RADIUS + TAIL_WIDTH, origin.x + panel_size.x - CORNER_RADIUS)
	queue_redraw()


func _draw() -> void:
	if _panel.size.x <= 0.0:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(CORNER_RADIUS))
	style.shadow_color = INNER_GLOW
	style.shadow_size = 3
	style.anti_aliasing = true
	draw_style_box(style, _panel)
	var bottom := _panel.position.y + _panel.size.y
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(_tail_x - TAIL_WIDTH * 0.5, bottom - 1.0),
			Vector2(_tail_x + TAIL_WIDTH * 0.5, bottom - 1.0),
			Vector2(_tail_x, bottom + TAIL_HEIGHT),
		]),
		PANEL_COLOR
	)
	draw_line(
		Vector2(_tail_x - TAIL_WIDTH * 0.5, bottom - 1.0),
		Vector2(_tail_x, bottom + TAIL_HEIGHT),
		BORDER_COLOR,
		1.0
	)
	draw_line(
		Vector2(_tail_x + TAIL_WIDTH * 0.5, bottom - 1.0),
		Vector2(_tail_x, bottom + TAIL_HEIGHT),
		BORDER_COLOR,
		1.0
	)


func _ui_font() -> Font:
	var latin := load(LATIN_FONT) as Font
	var cjk := load(CJK_FONT) as Font
	if latin == null:
		return null
	if cjk != null:
		var fallbacks: Array[Font] = [cjk]
		latin.set("fallbacks", fallbacks)
	return latin
