extends Node2D
class_name GridOverlay

@export var safe_size: Vector2i = Vector2i(320, 180)
@export var safe_origin: Vector2 = Vector2(0.0, 0.0)
@export var color_8px: Color = Color(1.0, 1.0, 1.0, 0.12)
@export var color_16px: Color = Color(0.4, 0.9, 1.0, 0.18)

var mode: int = 1


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
        toggle_grid()


func toggle_grid() -> void:
    mode = (mode + 1) % 3
    queue_redraw()


func _draw() -> void:
    if mode == 0:
        return
    if mode == 1:
        _draw_grid(8, color_8px)
    else:
        _draw_grid(16, color_16px)


func _draw_grid(step: int, line_color: Color) -> void:
    var rect: Rect2 = Rect2(safe_origin, Vector2(safe_size))
    for x: int in range(0, safe_size.x + 1, step):
        var x_pos: float = safe_origin.x + float(x)
        draw_line(Vector2(x_pos, rect.position.y), Vector2(x_pos, rect.end.y), line_color, 1.0)
    for y: int in range(0, safe_size.y + 1, step):
        var y_pos: float = safe_origin.y + float(y)
        draw_line(Vector2(rect.position.x, y_pos), Vector2(rect.end.x, y_pos), line_color, 1.0)
    draw_rect(rect, Color(1.0, 1.0, 1.0, 0.35), false, 1.0)
