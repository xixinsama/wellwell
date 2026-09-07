extends Control
class_name Main

const SAFE_SIZE: Vector2i = Vector2i(320, 180)
const VIEWPORT_SIZE: Vector2i = Vector2i(322, 182)
const MIN_SCALE: int = 1

@onready var viewport_container: SubViewportContainer = $SubViewportContainer
@onready var sub_viewport: SubViewport = $SubViewportContainer/SubViewport


func _ready() -> void:
    get_viewport().size_changed.connect(setup_viewport_scale)
    setup_viewport_scale()

    Globals.SVC = viewport_container


func setup_viewport_scale() -> void:
    var window_size: Vector2 = get_viewport_rect().size
    var scale_x: int = floori(window_size.x / SAFE_SIZE.x)
    var scale_y: int = floori(window_size.y / SAFE_SIZE.y)
    var integer_scale: int = maxi(MIN_SCALE, mini(scale_x, scale_y))
    var display_size: Vector2 = Vector2(VIEWPORT_SIZE) * integer_scale
    viewport_container.custom_minimum_size = display_size
    viewport_container.size = display_size
    viewport_container.position = ((window_size - display_size) * 0.5).round()
    viewport_container.stretch = true
