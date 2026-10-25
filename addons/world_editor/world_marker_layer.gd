@tool
extends Control

## Draws the room annotations (spawns, entrances, entities) collected from the
## baked runtime scenes on top of the world canvas, plus a hover tooltip.
##
## The layer is input-transparent: the canvas owns box selection / dragging and
## forwards the cursor position, so a click on a marker simply selects its room.

const TYPE_COLORS := {
    &"spawn": Color(0.31, 0.78, 0.49),
    &"entrance": Color(0.94, 0.68, 0.31),
    &"save": Color(0.45, 0.72, 1.0),
    &"pickup": Color(0.90, 0.85, 0.40),
    &"hazard": Color(0.90, 0.35, 0.35),
    &"switch": Color(0.70, 0.55, 0.95),
    &"reset_zone": Color(0.55, 0.60, 0.70),
    &"world_entity": Color(0.75, 0.78, 0.85),
}
const TYPE_LETTERS := {&"spawn": "S", &"entrance": "E"}
const TYPE_LABEL_KEYS := {
    &"spawn": "WE_MARKER_SPAWN",
    &"entrance": "WE_MARKER_ENTRANCE",
    &"save": "WE_MARKER_SAVE",
    &"pickup": "WE_MARKER_PICKUP",
    &"hazard": "WE_MARKER_HAZARD",
    &"switch": "WE_MARKER_SWITCH",
    &"reset_zone": "WE_MARKER_RESET_ZONE",
    &"world_entity": "WE_MARKER_ENTITY",
}
const MARKER_SIZE := 9.0
const HIT_RADIUS := 8.0

var _world: WorldData
var _view: RefCounted
var _annotations: Dictionary = {}
var _statuses: Dictionary = {}
var _selected_ids: Array[String] = []
var _cursor := Vector2.ZERO
var _hovered: Dictionary = {}
var _screen_markers: Array[Dictionary] = []


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    queue_redraw()


func set_data(
    world: WorldData,
    view: RefCounted,
    annotations: Dictionary,
    statuses: Dictionary,
    selected_ids: Array[String]
) -> void:
    _world = world
    _view = view
    _annotations = annotations
    _statuses = statuses
    _selected_ids = selected_ids
    _rebuild_screen_markers()
    queue_redraw()


func set_cursor(local_position: Vector2) -> void:
    _cursor = local_position
    var hovered: Dictionary = {}
    for marker: Dictionary in _screen_markers:
        if (marker["screen"] as Vector2).distance_to(local_position) <= HIT_RADIUS:
            hovered = marker
    if hovered.get("key", "") != _hovered.get("key", ""):
        _hovered = hovered
        queue_redraw()


func get_hovered_marker() -> Dictionary:
    return _hovered


func _draw() -> void:
    if _world == null or _view == null:
        return
    _rebuild_screen_markers()
    var size_px := MARKER_SIZE
    for marker: Dictionary in _screen_markers:
        var screen: Vector2 = marker["screen"]
        if not Rect2(Vector2.ZERO, size).grow(12.0).has_point(screen):
            continue
        var color: Color = marker["color"]
        var rect := Rect2(screen - Vector2(size_px, size_px) * 0.5, Vector2(size_px, size_px))
        draw_rect(rect, color, true)
        draw_rect(rect, Color(0.06, 0.08, 0.10, 0.9), false, 1.0)
        var letter := String(marker.get("letter", ""))
        if not letter.is_empty():
            draw_string(
                ThemeDB.fallback_font,
                screen + Vector2(-2.5, 3.0),
                letter,
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                8,
                Color(0.06, 0.08, 0.10, 0.95)
            )
    var hovered: Dictionary = _hovered
    if not hovered.is_empty():
        _draw_tooltip(hovered)


func _draw_tooltip(marker: Dictionary) -> void:
    var text := String(marker["label"])
    var font := ThemeDB.fallback_font
    var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0
    var position := _cursor + Vector2(12, -28)
    position.x = clampf(position.x, 4.0, maxf(4.0, size.x - width - 4.0))
    position.y = clampf(position.y, 4.0, maxf(4.0, size.y - 22.0))
    draw_rect(Rect2(position, Vector2(width, 18)), Color(0.08, 0.10, 0.13, 0.96), true)
    draw_rect(Rect2(position, Vector2(width, 18)), Color(0.35, 0.40, 0.48, 0.9), false, 1.0)
    draw_string(font, position + Vector2(6, 13), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.87, 0.90, 0.95))


func _rebuild_screen_markers() -> void:
    _screen_markers.clear()
    if _world == null or _view == null:
        return
    for room_id: String in _world.get_room_ids():
        var annotations: Array = _annotations.get(room_id, [])
        if annotations.is_empty():
            continue
        var room_rect := Rect2(_world.get_room_pixel_rect(room_id))
        var stale: bool = String(_statuses.get(room_id, &"fresh")) == "stale"
        for annotation: Dictionary in annotations:
            var world_position: Vector2 = room_rect.position + (annotation.get("position", Vector2.ZERO) as Vector2)
            var screen: Vector2 = _view.call("world_to_screen", world_position, size)
            var type: StringName = annotation.get("type", &"world_entity")
            var id := String(annotation.get("id", ""))
            var type_label := WorldEditorLocalization.t(String(TYPE_LABEL_KEYS.get(type, "WE_MARKER_ENTITY")))
            var label := "%s · %s" % [String(annotation.get("name", "")), type_label]
            if not id.is_empty():
                label += " · %s" % id
            label += "  (%d, %d)" % [roundi((annotation.get("position", Vector2.ZERO) as Vector2).x), roundi((annotation.get("position", Vector2.ZERO) as Vector2).y)]
            if stale:
                label += "  · %s" % WorldEditorLocalization.t("WE_FROM_LAST_BAKE")
            _screen_markers.append({
                "key": "%s/%s" % [room_id, annotation.get("path", "")],
                "screen": screen,
                "color": TYPE_COLORS.get(type, Color(0.75, 0.78, 0.85)) if not stale else (TYPE_COLORS.get(type, Color(0.75, 0.78, 0.85)) * Color(0.8, 0.8, 0.8, 1.0)),
                "letter": String(TYPE_LETTERS.get(type, "")),
                "label": label,
                "room_id": room_id,
            })
