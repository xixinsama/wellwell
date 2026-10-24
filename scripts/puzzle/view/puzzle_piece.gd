@tool
class_name PuzzlePiece
extends Polygon2D

## A single sliding block authored directly in a scene.
##
## The block face is this Polygon2D's own polygon. Draw it in the 2D editor
## with grid snapping set to [member cell_size]; the script derives the occupied
## cell list ([member shape]) from the polygon, so no shape array is authored by
## hand. The node's local origin (0, 0) is the block's anchor cell.
##
## Polygon rules:
##  - Vertices are automatically snapped to the nearest cell-grid corner, so a
##    slightly drifted point cannot silently break shape generation.
##  - Every edge must be axis-aligned (horizontal or vertical).
##  - The polygon must be a single, non-self-intersecting outline.
## An empty polygon is treated as "not drawn yet" (empty shape, no warning). A
## non-empty polygon that still breaks the rules (e.g. a diagonal edge) prints a
## warning and yields no shape.

@export var movement_mode: PieceDefinition.MovementMode = PieceDefinition.MovementMode.FREE
## Whether interactive input may move this piece. Disabled pieces still occupy
## their cells and block other pieces. A disabled void piece can still be moved
## passively by an A+ induced turn.
@export var enable: bool = true
## Cells travelled per horizontal input step.
@export var x_move_distance: int = 1
## Cells travelled per vertical input step.
@export var y_move_distance: int = 1
@export var cell_size: int = 8:
    set(value):
        cell_size = maxi(1, value)
        _refresh_from_polygon()

var piece_index: int = -1
var logical_cell: Vector2i = Vector2i.ZERO
## Derived cell offsets this piece occupies, relative to the anchor cell (0, 0).
var shape: Array[Vector2i] = []
## Cells that block from every direction. Legacy polygon faces are all walls.
var wall_shape: Array[Vector2i] = []
## Upward-facing one-way platform cells. The base polygon face never fills this.
var one_way_shape: Array[Vector2i] = []
## True for a moving void region. Tile pieces set this from a VoidTiles layer.
var is_void: bool = false

var _base_color: Color = Color.WHITE
var _cached_polygon: PackedVector2Array = PackedVector2Array()
var _cached_cell_size: int = -1


func _ready() -> void:
    _base_color = color
    logical_cell = _position_to_cell(position)
    _refresh_from_polygon()
    if not Engine.is_editor_hint():
        _build_collision()


func _process(_delta: float) -> void:
    if not Engine.is_editor_hint():
        return
    if _cached_polygon != polygon or _cached_cell_size != cell_size:
        _refresh_from_polygon()


func _draw() -> void:
    if polygon.is_empty():
        return
    draw_colored_polygon(polygon, color)
    # Per-cell grid lines make the unit cells ("格子") visible.
    var grid_color := Color(0.0, 0.0, 0.0, 0.28)
    for cell_offset: Vector2i in shape:
        draw_rect(
            Rect2(Vector2(cell_offset) * float(cell_size), Vector2(cell_size, cell_size)),
            grid_color,
            false,
            1.0
        )
    # Solid outer outline.
    var outline := polygon.duplicate()
    outline.append(polygon[0])
    draw_polyline(outline, Color(0.0, 0.0, 0.0, 0.7), 1.0)


# --- Shape derivation ---------------------------------------------------------

func _refresh_from_polygon() -> void:
    var grid_polygon := _snapped_polygon()
    if grid_polygon != polygon:
        polygon = grid_polygon
    _cached_polygon = grid_polygon
    _cached_cell_size = cell_size
    shape = _derive_shape(grid_polygon)
    wall_shape.clear()
    wall_shape.append_array(shape)
    one_way_shape.clear()
    queue_redraw()


func _snapped_polygon() -> PackedVector2Array:
    ## Snaps every vertex to the nearest cell-grid corner so a slightly drifted
    ## point cannot silently break shape generation.
    var result := PackedVector2Array()
    for point: Vector2 in polygon:
        result.append(Vector2(
            roundf(point.x / float(cell_size)) * float(cell_size),
            roundf(point.y / float(cell_size)) * float(cell_size)
        ))
    return result


func _derive_shape(grid_polygon: PackedVector2Array) -> Array[Vector2i]:
    if grid_polygon.is_empty():
        return []
    var validation_error := _polygon_validation_error(grid_polygon)
    if not validation_error.is_empty():
        push_warning("PuzzlePiece %s: %s" % [name, validation_error])
        return []

    var min_cell := Vector2i(1 << 30, 1 << 30)
    var max_cell := Vector2i(-(1 << 30), -(1 << 30))
    for point: Vector2 in grid_polygon:
        var cell := _point_to_cell(point)
        min_cell.x = mini(min_cell.x, cell.x)
        min_cell.y = mini(min_cell.y, cell.y)
        max_cell.x = maxi(max_cell.x, cell.x)
        max_cell.y = maxi(max_cell.y, cell.y)

    var result: Array[Vector2i] = []
    for cy in range(min_cell.y, max_cell.y + 1):
        for cx in range(min_cell.x, max_cell.x + 1):
            var cell := Vector2i(cx, cy)
            var center := Vector2(cell) * float(cell_size) + Vector2(0.5, 0.5) * float(cell_size)
            if Geometry2D.is_point_in_polygon(center, grid_polygon):
                result.append(cell)
    return result


func _polygon_validation_error(grid_polygon: PackedVector2Array) -> String:
    if grid_polygon.size() < 3:
        return "polygon needs at least 3 vertices."
    for i in grid_polygon.size():
        var a: Vector2 = grid_polygon[i]
        var b: Vector2 = grid_polygon[(i + 1) % grid_polygon.size()]
        var delta := b - a
        if delta.length_squared() < 0.01:
            return "edge %d has zero length." % i
        if absf(delta.x) > 0.001 and absf(delta.y) > 0.001:
            return "edge %d is diagonal; edges must be axis-aligned." % i
    return ""


func _point_to_cell(point: Vector2) -> Vector2i:
    return Vector2i(roundi(point.x / float(cell_size)), roundi(point.y / float(cell_size)))


# --- Collision (runtime only) -------------------------------------------------

func _build_collision() -> void:
    var old := get_node_or_null("CollisionWall")
    if old != null:
        old.queue_free()
    if shape.is_empty():
        return

    var body := StaticBody2D.new()
    body.name = "CollisionWall"
    body.collision_layer = 1
    body.collision_mask = 0
    add_child(body)

    for cell_offset: Vector2i in shape:
        var collision_shape := CollisionShape2D.new()
        collision_shape.name = "CollisionShape2D"
        var rect := RectangleShape2D.new()
        rect.size = Vector2(cell_size, cell_size)
        collision_shape.shape = rect
        collision_shape.position = (Vector2(cell_offset) + Vector2(0.5, 0.5)) * float(cell_size)
        body.add_child(collision_shape)


# --- Queries / state ----------------------------------------------------------

func set_cell(cell: Vector2i) -> void:
    logical_cell = cell
    position = cell_to_world(cell)


func get_logical_cell() -> Vector2i:
    return logical_cell


func cell_to_world(cell: Vector2i) -> Vector2:
    return Vector2(cell) * float(cell_size)


## Bounding rect (in cell coordinates) enclosing the shape, relative to the anchor.
func get_bounds() -> Rect2i:
    if shape.is_empty():
        return Rect2i(Vector2i.ZERO, Vector2i.ONE)
    var min_cell := shape[0]
    var max_cell := shape[0]
    for cell_offset: Vector2i in shape:
        min_cell.x = mini(min_cell.x, cell_offset.x)
        min_cell.y = mini(min_cell.y, cell_offset.y)
        max_cell.x = maxi(max_cell.x, cell_offset.x)
        max_cell.y = maxi(max_cell.y, cell_offset.y)
    return Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)


## Visual feedback for the selected block.
func set_highlight(active: bool) -> void:
    color = _base_color.lightened(0.3) if active else _base_color
    queue_redraw()


func _position_to_cell(pos: Vector2) -> Vector2i:
    return Vector2i(roundi(pos.x / float(cell_size)), roundi(pos.y / float(cell_size)))
