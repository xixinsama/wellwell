@tool
class_name PuzzleTilePiece
extends PuzzlePiece

## A sliding block whose face is a movable chunk of level terrain.
##
## Paint the child [TileMapLayer]s exactly like room terrain:
##  - [code]BackTiles[/code]: background decoration. Keep collision disabled so
##    it neither blocks nor enlarges the footprint.
##  - [code]SolidTiles[/code]: walls. Keep collision enabled.
##  - [code]OneWayTiles[/code]: upward-facing one-way platforms. Keep collision
##    enabled and keep this layer above [code]SolidTiles[/code] so overlapping
##    walls and platforms both remain visible.
##  - [code]VoidTiles[/code]: the footprint of a void slider. It is a visual
##    layer with collision disabled; the script builds a player-only body on
##    the void physics layer. Void and wall/one-way layers are mutually
##    exclusive; a void piece ignores wall/one-way layers.
##  - [code]DetailTiles[/code]: optional foreground detail. Collision disabled.
##
## The footprint ([member shape]) is derived from collision-bearing cells. For
## a void piece, [member is_void] is true and the footprint is the painted
## VoidTiles cells. Background, marker and other physics-less tiles never
## enlarge a normal block.

const HIGHLIGHT_NODE_NAME := &"SelectionHighlight"
const VOID_LAYER_NAME := &"VoidTiles"

const CELL_KIND_NONE := 0
const CELL_KIND_WALL := 1
const CELL_KIND_ONE_WAY := 2

var _collision_layers: Array[TileMapLayer] = []
var _void_layer: TileMapLayer = null
var _highlight: PuzzleTilePieceHighlight = null
var _layer_signature: String = ""


func _ready() -> void:
    _collect_tile_layers()
    if not _is_tile_piece():
        super._ready()
        return
    logical_cell = _position_to_cell(position)
    _refresh_from_polygon()
    if not Engine.is_editor_hint():
        _ensure_highlight()
        _update_highlight()


func _process(_delta: float) -> void:
    if not Engine.is_editor_hint():
        return
    if not _is_tile_piece():
        _collect_tile_layers()
        if not _is_tile_piece():
            super._process(_delta)
            return
    var signature := _compute_layer_signature()
    if signature != _layer_signature:
        _refresh_from_polygon()


func _draw() -> void:
    if not _is_tile_piece():
        super._draw()


func _get_configuration_warnings() -> PackedStringArray:
    var warnings := PackedStringArray()
    var has_collision_layer := false
    var first_tile_set: TileSet = null
    for child: Node in get_children():
        var layer := child as TileMapLayer
        if layer == null:
            continue
        if first_tile_set == null:
            first_tile_set = layer.tile_set
        if layer.collision_enabled:
            has_collision_layer = true
        if layer.position != Vector2.ZERO or layer.scale != Vector2.ONE or not is_zero_approx(layer.rotation):
            warnings.append(
                "%s must stay at position (0, 0), scale (1, 1) and rotation 0 so its cells line up with the piece grid."
                % layer.name
            )
    var void_layer := get_node_or_null(String(VOID_LAYER_NAME)) as TileMapLayer
    var has_void := void_layer != null and not void_layer.get_used_cells().is_empty()
    if not has_collision_layer and not has_void and polygon.is_empty():
        warnings.append(
            "Add a collision-enabled TileMapLayer child (for example SolidTiles) "
            + "or a VoidTiles layer or draw a Polygon2D face."
        )
    if has_void and has_collision_layer:
        warnings.append("A void piece cannot also have SolidTiles/OneWayTiles; those layers are ignored.")
    if has_void and void_layer.collision_enabled:
        warnings.append("VoidTiles must have collision disabled; the piece builds its own player-only body.")
    if first_tile_set != null and first_tile_set.tile_size.x != cell_size:
        warnings.append(
            "TileSet tile width %d does not match cell_size %d."
            % [first_tile_set.tile_size.x, cell_size]
        )
    return warnings


func _refresh_from_polygon() -> void:
    _collect_tile_layers()
    if not _is_tile_piece():
        super._refresh_from_polygon()
        return
    # The Polygon2D face is only a fallback; tile pieces render their layers.
    if not polygon.is_empty():
        polygon = PackedVector2Array()

    var void_cells: Array[Vector2i] = []
    if _void_layer != null:
        void_cells.assign(_void_layer.get_used_cells())
        if _void_layer.collision_enabled:
            _void_layer.collision_enabled = false

    if not void_cells.is_empty():
        # VoidTiles wins over wall/one-way layers in an invalid hybrid setup.
        for layer: TileMapLayer in _collision_layers:
            layer.collision_enabled = false
        _collision_layers.clear()
        void_cells.sort_custom(_cell_comes_before)
        is_void = true
        shape = void_cells
        wall_shape.clear()
        one_way_shape.clear()
        _layer_signature = _compute_layer_signature()
        _rebuild_void_body()
        _update_highlight()
        queue_redraw()
        return

    is_void = false
    _clear_void_body()

    var walls: Array[Vector2i] = []
    var one_ways: Array[Vector2i] = []
    var wall_seen: Dictionary = {}
    var one_way_seen: Dictionary = {}
    for layer: TileMapLayer in _collision_layers:
        for cell: Vector2i in layer.get_used_cells():
            var kind := _cell_collision_kind(layer, cell)
            if kind == CELL_KIND_WALL:
                if not wall_seen.has(cell):
                    wall_seen[cell] = true
                    walls.append(cell)
                # A solid tile wins if the same cell also has a one-way tile.
                one_way_seen.erase(cell)
            elif kind == CELL_KIND_ONE_WAY:
                if not wall_seen.has(cell) and not one_way_seen.has(cell):
                    one_way_seen[cell] = true
                    one_ways.append(cell)

    var filtered_one_ways: Array[Vector2i] = []
    for cell: Vector2i in one_ways:
        if not wall_seen.has(cell):
            filtered_one_ways.append(cell)
    walls.sort_custom(_cell_comes_before)
    filtered_one_ways.sort_custom(_cell_comes_before)

    wall_shape = walls
    one_way_shape = filtered_one_ways
    var next_shape: Array[Vector2i] = []
    next_shape.append_array(walls)
    next_shape.append_array(filtered_one_ways)
    next_shape.sort_custom(_cell_comes_before)
    shape = next_shape
    _layer_signature = _compute_layer_signature()
    _update_highlight()
    queue_redraw()


func _build_collision() -> void:
    # TileMapLayer owns normal tile collision; void pieces own a player body.
    if not _is_tile_piece():
        super._build_collision()


func set_highlight(active: bool) -> void:
    if not _is_tile_piece():
        super.set_highlight(active)
        return
    _ensure_highlight()
    if _highlight != null:
        _highlight.visible = active
        _update_highlight()


func _collect_tile_layers() -> void:
    _collision_layers.clear()
    _void_layer = null
    for child: Node in get_children():
        var layer := child as TileMapLayer
        if layer == null:
            continue
        if layer.name == VOID_LAYER_NAME:
            _void_layer = layer
        elif layer.collision_enabled:
            _collision_layers.append(layer)


func _is_tile_piece() -> bool:
    return _void_layer != null or not _collision_layers.is_empty()


func _cell_collision_kind(layer: TileMapLayer, cell: Vector2i) -> int:
    var tile_set := layer.tile_set
    if tile_set == null:
        return CELL_KIND_NONE
    var source_id := layer.get_cell_source_id(cell)
    if source_id < 0:
        return CELL_KIND_NONE
    var source := tile_set.get_source(source_id)
    if source is TileSetAtlasSource:
        var atlas_source := source as TileSetAtlasSource
        var tile_data := atlas_source.get_tile_data(
            layer.get_cell_atlas_coords(cell),
            layer.get_cell_alternative_tile(cell)
        )
        if tile_data == null:
            return CELL_KIND_NONE
        var has_one_way := false
        for physics_layer in tile_set.get_physics_layers_count():
            var polygon_count := tile_data.get_collision_polygons_count(physics_layer)
            for polygon_index in polygon_count:
                if tile_data.is_collision_polygon_one_way(physics_layer, polygon_index):
                    has_one_way = true
                else:
                    return CELL_KIND_WALL
        return CELL_KIND_ONE_WAY if has_one_way else CELL_KIND_NONE
    return CELL_KIND_WALL


func _compute_layer_signature() -> String:
    var parts := PackedStringArray()
    for child: Node in get_children():
        var layer := child as TileMapLayer
        if layer == null:
            continue
        var tile_set_id := 0
        if layer.tile_set != null:
            tile_set_id = layer.tile_set.get_instance_id()
        parts.append("%s|%s|%s|%s" % [
            layer.name,
            layer.collision_enabled,
            tile_set_id,
            hash(layer.tile_map_data),
        ])
    return "\n".join(parts)


func _rebuild_void_body() -> void:
    _clear_void_body()
    if not is_void or shape.is_empty() or Engine.is_editor_hint():
        return
    var body := StaticBody2D.new()
    body.name = "VoidBody"
    body.collision_layer = 1 << 3
    body.collision_mask = 0
    add_child(body)
    for cell: Vector2i in shape:
        var collision := CollisionShape2D.new()
        var rect := RectangleShape2D.new()
        rect.size = Vector2(cell_size, cell_size)
        collision.shape = rect
        collision.position = (Vector2(cell) + Vector2(0.5, 0.5)) * float(cell_size)
        body.add_child(collision)


func _clear_void_body() -> void:
    var old := get_node_or_null("VoidBody")
    if old != null:
        old.free()


func _ensure_highlight() -> void:
    if _highlight != null and is_instance_valid(_highlight):
        return
    _highlight = PuzzleTilePieceHighlight.new()
    _highlight.name = String(HIGHLIGHT_NODE_NAME)
    _highlight.z_index = 20
    _highlight.visible = false
    add_child(_highlight)


func _update_highlight() -> void:
    if _highlight == null or not is_instance_valid(_highlight):
        return
    _highlight.setup(cell_size, shape)


static func _cell_comes_before(a: Vector2i, b: Vector2i) -> bool:
    if a.y != b.y:
        return a.y < b.y
    return a.x < b.x
