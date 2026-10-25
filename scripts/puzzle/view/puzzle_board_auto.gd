@tool
class_name PuzzleBoardAuto
extends PuzzleBoard

## Builds an equal-size sliding puzzle by splitting authored TileMapLayers.
##
## Paint the whole picture on a source TileMapLayer (walls, one-way platforms
## and background tiles can all live on that one layer: [PuzzleTilePiece] reads
## each tile's physics to classify it). Optionally paint a second layer whose
## cells mark void sliders. Then set [member puzzle_size] and [member piece_size]
## and the board cuts the painted area into that many equal chunks, creating one
## [PuzzleTilePiece] per chunk (with a local [code]SolidTiles[/code] or
## [code]VoidTiles[/code] child layer) and a matching session.
##
## The work happens in the editor: generated nodes are owned by the edited scene
## root, saved into the room source scene and baked with it. At runtime the
## board only rebuilds its session from the saved pieces.
##
## Put the source layers outside [code]RoomContent[/code] (for example under
## [code]PreviewOnly[/code]) so the bake never sees them, and place this board at
## the puzzle's top-left corner: the source layers only provide content, the
## board node decides where the puzzle appears in the room.

const GENERATED_META := &"puzzle_generated"
const AUTHORED_CELL_META := &"authored_cell"
const GENERATED_PIECE_PREFIX := "Piece_"
const SOLID_LAYER_NAME := &"SolidTiles"
const VOID_LAYER_NAME := &"VoidTiles"
const REFRESH_DEBOUNCE_SECONDS := 0.2

## Number of slider columns / rows.
@export var puzzle_size: Vector2i = Vector2i(3, 3):
	set(value):
		puzzle_size = Vector2i(maxi(1, value.x), maxi(1, value.y))
		queue_redraw()
## Cells per slider along each axis.
@export var piece_size: Vector2i = Vector2i(7, 7):
	set(value):
		piece_size = Vector2i(maxi(1, value.x), maxi(1, value.y))
		queue_redraw()
## TileMapLayer holding the whole picture (editor input, never modified).
@export var source_layer_path: NodePath = ^""
## Optional TileMapLayer whose painted cells mark void slider footprints.
@export var void_layer_path: NodePath = ^""
## Whether generated void sliders may be driven directly by input.
@export var void_enable: bool = false

@export_tool_button("Regenerate", "Reload") var regenerate_action = _regenerate_from_tool_button

## Signature of the inputs that produced the current generated pieces. Saved so
## reopening a scene does not regenerate (and dirty) when nothing changed.
@export_storage var _source_signature: String = ""

var _refresh_debounce: float = -1.0
var _pending_signature: String = ""


func _ready() -> void:
	board_size = puzzle_size * piece_size
	super._ready()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		super._process(delta)
		return
	var signature := _current_signature()
	if signature == _source_signature:
		_refresh_debounce = -1.0
		_pending_signature = ""
		return
	if signature != _pending_signature:
		_pending_signature = signature
		_refresh_debounce = 0.0
		return
	_refresh_debounce += delta
	if _refresh_debounce < REFRESH_DEBOUNCE_SECONDS:
		return
	_refresh_debounce = -1.0
	_pending_signature = ""
	generate_pieces()


# --- Generation ---------------------------------------------------------------

## Split the source layers and rebuild every generated piece. Returns false when
## the source layer is missing or holds no cells; the board is left untouched in
## that case.
func generate_pieces() -> bool:
	var source := _get_source_layer()
	var void_source := _get_void_layer()
	_source_signature = _current_signature(source, void_source)
	if source == null:
		push_warning(
			"PuzzleBoardAuto %s: source_layer_path must point at a painted TileMapLayer." % name
		)
		return false
	var layout := _split_layout(source, void_source)
	var chunks: Dictionary = layout["chunks"]
	if chunks.is_empty():
		push_warning("PuzzleBoardAuto %s: the source layers hold no cells to split." % name)
		return false
	_clear_generated_pieces()
	board_size = puzzle_size * piece_size
	for chunk: Vector2i in chunks:
		_create_piece(chunk, chunks[chunk], source, void_source)
	return true


## Pieces created by the last generation pass, in tree order.
func get_generated_pieces() -> Array[PuzzleTilePiece]:
	var pieces: Array[PuzzleTilePiece] = []
	for child: Node in get_children():
		if child is PuzzleTilePiece and child.has_meta(GENERATED_META):
			pieces.append(child as PuzzleTilePiece)
	return pieces


func _regenerate_from_tool_button() -> void:
	generate_pieces()


func _clear_generated_pieces() -> void:
	for child: Node in get_children():
		if child.has_meta(GENERATED_META):
			child.free()


func _create_piece(
	chunk: Vector2i,
	entries: Array,
	source: TileMapLayer,
	void_source: TileMapLayer
) -> void:
	var has_void := false
	for entry: Dictionary in entries:
		if entry["void"]:
			has_void = true
			break
	var piece := PuzzleTilePiece.new()
	piece.name = "%s%d_%d" % [GENERATED_PIECE_PREFIX, chunk.x, chunk.y]
	piece.cell_size = cell_size
	piece.position = Vector2(chunk * piece_size) * float(cell_size)
	piece.x_move_distance = piece_size.x
	piece.y_move_distance = piece_size.y
	piece.movement_mode = PieceDefinition.MovementMode.FREE
	piece.enable = void_enable if has_void else true
	piece.is_void = has_void
	piece.z_index = 1 if has_void else 0
	piece.set_meta(GENERATED_META, true)
	piece.set_meta(AUTHORED_CELL_META, chunk * piece_size)

	var layer := TileMapLayer.new()
	layer.name = String(VOID_LAYER_NAME if has_void else SOLID_LAYER_NAME)
	layer.collision_enabled = not has_void
	var template := void_source if has_void else source
	if template != null and template.tile_set != null:
		layer.tile_set = template.tile_set
	for entry: Dictionary in entries:
		if bool(entry["void"]) != has_void:
			continue
		layer.set_cell(entry["cell"], entry["source_id"], entry["atlas_coords"], entry["alternative"])
	piece.add_child(layer)

	add_child(piece)
	var scene_owner := _generated_owner()
	if scene_owner != null:
		piece.owner = scene_owner
		layer.owner = scene_owner


func _generated_owner() -> Node:
	if owner != null:
		return owner
	if Engine.is_editor_hint() and is_inside_tree():
		return get_tree().edited_scene_root
	return null


# --- Layout analysis ----------------------------------------------------------

## Buckets every painted cell into its chunk. Entries carry the tile data plus
## the piece-local cell and whether the cell comes from the void layer.
func _split_layout(source: TileMapLayer, void_source: TileMapLayer) -> Dictionary:
	var source_cells := _collect_cells(source)
	var void_cells := _collect_cells(void_source)
	var origin := _layout_origin(source_cells, void_cells)
	var board_cells := puzzle_size * piece_size
	var chunks: Dictionary = {}
	var outside := 0
	for cell: Vector2i in source_cells:
		var rel := cell - origin
		if not _fits(rel, board_cells):
			outside += 1
			continue
		_add_to_chunk(chunks, rel, source_cells[cell], false)
	for cell: Vector2i in void_cells:
		var rel := cell - origin
		if not _fits(rel, board_cells):
			outside += 1
			continue
		_add_to_chunk(chunks, rel, void_cells[cell], true)
	var hybrid := 0
	for chunk: Vector2i in chunks:
		var has_void := false
		var has_solid := false
		for entry: Dictionary in chunks[chunk]:
			if entry["void"]:
				has_void = true
			else:
				has_solid = true
		if has_void and has_solid:
			hybrid += 1
	return {
		"origin": origin,
		"chunks": chunks,
		"outside": outside,
		"hybrid": hybrid,
	}


func _collect_cells(layer: TileMapLayer) -> Dictionary:
	var cells: Dictionary = {}
	if layer == null:
		return cells
	for cell: Vector2i in layer.get_used_cells():
		cells[cell] = {
			"source_id": layer.get_cell_source_id(cell),
			"atlas_coords": layer.get_cell_atlas_coords(cell),
			"alternative": layer.get_cell_alternative_tile(cell),
		}
	return cells


func _layout_origin(source_cells: Dictionary, void_cells: Dictionary) -> Vector2i:
	var origin := Vector2i(1 << 30, 1 << 30)
	var found := false
	for cells: Dictionary in [source_cells, void_cells]:
		for cell: Vector2i in cells:
			origin.x = mini(origin.x, cell.x)
			origin.y = mini(origin.y, cell.y)
			found = true
	return origin if found else Vector2i.ZERO


func _fits(rel: Vector2i, board_cells: Vector2i) -> bool:
	return rel.x >= 0 and rel.y >= 0 and rel.x < board_cells.x and rel.y < board_cells.y


func _add_to_chunk(chunks: Dictionary, rel: Vector2i, data: Dictionary, is_void: bool) -> void:
	var chunk := Vector2i(
		floori(float(rel.x) / float(piece_size.x)),
		floori(float(rel.y) / float(piece_size.y))
	)
	var entry := data.duplicate()
	entry["cell"] = rel - chunk * piece_size
	entry["void"] = is_void
	var entries: Array = chunks.get(chunk, [])
	entries.append(entry)
	chunks[chunk] = entries


# --- Editor refresh -----------------------------------------------------------

func _current_signature(source: TileMapLayer = null, void_source: TileMapLayer = null) -> String:
	if source == null:
		source = _get_source_layer()
	if void_source == null:
		void_source = _get_void_layer()
	return "%d,%d|%d,%d|%d|%s|%s" % [
		puzzle_size.x,
		puzzle_size.y,
		piece_size.x,
		piece_size.y,
		cell_size,
		_layer_signature(source),
		_layer_signature(void_source),
	]


func _layer_signature(layer: TileMapLayer) -> String:
	if layer == null:
		return "-"
	var tile_set_path := ""
	if layer.tile_set != null:
		tile_set_path = layer.tile_set.resource_path
	var data: PackedByteArray = layer.tile_map_data
	return "%s:%s:%d:%d" % [layer.name, tile_set_path, data.size(), hash(data)]


func _get_source_layer() -> TileMapLayer:
	if source_layer_path.is_empty():
		return null
	return get_node_or_null(source_layer_path) as TileMapLayer


func _get_void_layer() -> TileMapLayer:
	if void_layer_path.is_empty():
		return null
	return get_node_or_null(void_layer_path) as TileMapLayer


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var source := _get_source_layer()
	if source == null:
		warnings.append("Assign source_layer_path to the TileMapLayer that holds the whole puzzle picture.")
		return warnings
	if source.get_used_cells().is_empty():
		warnings.append("The source TileMapLayer has no painted cells.")
	if source.tile_set != null and source.tile_set.tile_size.x != cell_size:
		warnings.append(
			"Source TileSet tile width %d does not match cell_size %d."
			% [source.tile_set.tile_size.x, cell_size]
		)
	var void_source := _get_void_layer()
	if void_source != null and void_source.tile_set != null and void_source.tile_set.tile_size.x != cell_size:
		warnings.append(
			"Void TileSet tile width %d does not match cell_size %d."
			% [void_source.tile_set.tile_size.x, cell_size]
		)
	var layout := _split_layout(source, void_source)
	var outside := int(layout["outside"])
	if outside > 0:
		warnings.append(
			"%d painted cell(s) fall outside the %dx%d board and are ignored."
			% [outside, puzzle_size.x * piece_size.x, puzzle_size.y * piece_size.y]
		)
	var hybrid := int(layout["hybrid"])
	if hybrid > 0:
		warnings.append("%d chunk(s) mix solid and void cells; void wins." % hybrid)
	var chunks: Dictionary = layout["chunks"]
	if chunks.size() == puzzle_size.x * puzzle_size.y:
		var has_void := false
		for chunk: Vector2i in chunks:
			for entry: Dictionary in chunks[chunk]:
				if entry["void"]:
					has_void = true
					break
			if has_void:
				break
		if not has_void:
			warnings.append(
				"The board is fully covered by sliders and has no void slider, so nothing can move."
			)
	return warnings
