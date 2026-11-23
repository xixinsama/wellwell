class_name OneWayDashPiercer
extends Node

## Lets a dash cross a one-way surface when the dash travels in the direction
## that surface blocks (down into a floor platform, right into a right-facing
## wall platform, and so on).
##
## Tile-based one-way platforms always block downward in Godot: tile collision
## carries no per-tile one-way direction, so only a downward dash pierces them.
## They live on the dedicated `one_way` physics layer (project layer 5) so the
## dash can drop that bit without losing solid ground.
##
## Node-based one-way platforms use CollisionShape2D.one_way_collision_direction
## (Godot 4.7+) and may face any of the four cardinal directions. A matching dash
## ignores that body through a temporary collision exception.

const DEFAULT_TILE_ONE_WAY_LAYER_MASK := 1 << 4

@export var tile_one_way_layer_mask: int = DEFAULT_TILE_ONE_WAY_LAYER_MASK
@export var pierce_tile_one_ways := true
@export var pierce_node_one_ways := true
## How far off a cardinal direction still counts as piercing along it.
@export_range(0.0, 0.5, 0.01) var cardinal_tolerance := 0.01
## How far ahead of the player to look for matching one-way bodies.
@export_range(1.0, 256.0, 1.0) var sweep_distance := 48.0

var _body: CharacterBody2D
var _shape: CollisionShape2D
var _tile_layer_disabled := false
var _piercing := false
var _pierced_bodies: Array[Node] = []


func configure(body: CharacterBody2D) -> bool:
	_body = body
	_shape = _find_collision_shape(body)
	_pierced_bodies.clear()
	_tile_layer_disabled = false
	_piercing = false
	if _body == null:
		return false
	_body.collision_mask |= tile_one_way_layer_mask
	return true


## Called every physics frame before move_and_slide().
func update(dash_active: bool, dash_velocity: Vector2) -> void:
	if _body == null:
		return
	var cardinal := cardinal_direction(dash_velocity, cardinal_tolerance)
	if not dash_active or cardinal == Vector2i.ZERO:
		_release()
		return
	if _piercing:
		return
	_piercing = true
	if pierce_tile_one_ways and cardinal == Vector2i(0, 1):
		_set_tile_layer_disabled(true)
	if pierce_node_one_ways:
		_pierce_matching_bodies(cardinal)


## Restores every temporary change. Use it on respawn, control locks, or
## whenever the player leaves normal play.
func clear() -> void:
	_piercing = false
	_clear_exceptions()
	_set_tile_layer_disabled(false)


func is_piercing() -> bool:
	return _piercing


func is_tile_layer_disabled() -> bool:
	return _tile_layer_disabled


func get_pierced_bodies() -> Array[Node]:
	return _pierced_bodies.duplicate()


## The cardinal direction of a dash, or Vector2i.ZERO for diagonals and zero
## motion. Only cardinal dashes pierce one-way surfaces.
static func cardinal_direction(velocity: Vector2, tolerance: float = 0.01) -> Vector2i:
	if velocity.is_zero_approx():
		return Vector2i.ZERO
	var direction := velocity.normalized()
	var pinched := maxf(0.0, 1.0 - tolerance)
	if absf(direction.y) >= pinched and absf(direction.x) <= tolerance:
		return Vector2i(0, 1 if direction.y > 0.0 else -1)
	if absf(direction.x) >= pinched and absf(direction.y) <= tolerance:
		return Vector2i(1 if direction.x > 0.0 else -1, 0)
	return Vector2i.ZERO


## True when the surface blocks movement in [param cardinal], which is exactly
## the dash direction that crosses it.
static func blocks_direction(
	surface_direction: Vector2,
	cardinal: Vector2i,
	tolerance: float = 0.01
) -> bool:
	if cardinal == Vector2i.ZERO or surface_direction.is_zero_approx():
		return false
	return surface_direction.normalized().dot(Vector2(cardinal)) >= 1.0 - tolerance


func _release() -> void:
	_piercing = false
	_clear_exceptions()
	if not _tile_layer_disabled:
		return
	# A dash can end while the body still overlaps a platform it is crossing;
	# keep the layer open until the overlap is gone so the player never gets
	# caught inside a one-way surface.
	if _overlaps_tile_one_way():
		return
	_set_tile_layer_disabled(false)


func _set_tile_layer_disabled(disabled: bool) -> void:
	if _body == null:
		return
	if disabled:
		if _tile_layer_disabled:
			return
		_body.collision_mask &= ~tile_one_way_layer_mask
	else:
		if not _tile_layer_disabled:
			return
		_body.collision_mask |= tile_one_way_layer_mask
	_tile_layer_disabled = disabled


func _overlaps_tile_one_way() -> bool:
	if _shape == null or _shape.shape == null or not _body.is_inside_tree():
		return false
	var space := _body.get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape.shape
	query.transform = _shape.global_transform
	query.collision_mask = tile_one_way_layer_mask
	query.collide_with_areas = false
	query.exclude = [_body.get_rid()]
	return not space.intersect_shape(query, 1).is_empty()


func _pierce_matching_bodies(cardinal: Vector2i) -> void:
	if _shape == null or _shape.shape == null or not _body.is_inside_tree():
		return
	var space := _body.get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var sweep := RectangleShape2D.new()
	sweep.size = _shape.shape.get_rect().size + Vector2(cardinal).abs() * sweep_distance
	query.shape = sweep
	query.transform = Transform2D(0.0, _shape.global_position + Vector2(cardinal) * sweep_distance * 0.5)
	query.collision_mask = _body.collision_mask & ~tile_one_way_layer_mask
	query.collide_with_areas = false
	query.exclude = [_body.get_rid()]
	for hit: Dictionary in space.intersect_shape(query, 16):
		var collider := hit.get("collider") as Node
		if collider == null or _pierced_bodies.has(collider):
			continue
		if not _is_matching_one_way_body(collider, cardinal):
			continue
		_body.add_collision_exception_with(collider)
		_pierced_bodies.append(collider)


func _is_matching_one_way_body(node: Node, cardinal: Vector2i) -> bool:
	var matched := false
	for child: Node in node.find_children("*", "CollisionShape2D", true, false):
		var collision := child as CollisionShape2D
		if collision == null or not collision.one_way_collision:
			# A regular solid shape would be ignored together with this body, so
			# mixed bodies never get an exception.
			return false
		var world_direction := collision.global_transform.basis_xform(
			collision.one_way_collision_direction
		).normalized()
		if not blocks_direction(world_direction, cardinal, cardinal_tolerance):
			return false
		matched = true
	return matched


func _clear_exceptions() -> void:
	if _body != null:
		for node: Node in _pierced_bodies:
			if is_instance_valid(node):
				_body.remove_collision_exception_with(node)
	_pierced_bodies.clear()


func _find_collision_shape(body: CharacterBody2D) -> CollisionShape2D:
	if body == null:
		return null
	for child: Node in body.get_children():
		var collision := child as CollisionShape2D
		if collision != null:
			return collision
	return null
