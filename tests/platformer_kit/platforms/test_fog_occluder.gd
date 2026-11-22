extends Node

## Contract for FogOccluderComponent2D: it publishes the host body's collision
## footprint to the fog, and it only asks the fog to rebuild when that footprint
## crosses an 8 px cell.

const OCCLUDER_SCRIPT: Script = preload(
	"res://addons/platformer_kit/platforms/components/fog_occluder_component_2d.gd"
)
const OCCLUDER_GROUP := &"fog_occluder"


class FakeFog extends Node:
	var refreshes := 0

	func _ready() -> void:
		add_to_group(&"fog_of_war")

	func request_refresh() -> void:
		refreshes += 1


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_footprint_follows_shapes(failures)
	_assert_state_changes_registration(failures)
	_assert_refresh_only_on_cell_change(failures)
	_assert_size_override(failures)
	return failures


func _make_body(offset: Vector2, shape_size: Vector2, shape_offset: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = offset
	var shape_node := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = shape_size
	shape_node.shape = rectangle
	shape_node.position = shape_offset
	body.add_child(shape_node)
	return body


func _assert_footprint_follows_shapes(failures: Array[String]) -> void:
	var body := _make_body(Vector2(40.0, 24.0), Vector2(16.0, 8.0), Vector2(8.0, 4.0))
	add_child(body)
	var occluder: Node = OCCLUDER_SCRIPT.new()
	body.add_child(occluder)
	if not occluder.is_in_group(OCCLUDER_GROUP):
		failures.append("fog occluder did not join the fog_occluder group")
	if not bool(occluder.call("is_occluding")):
		failures.append("enabled fog occluder does not occlude")
	if occluder.call("get_world_rect") != Rect2(40.0, 24.0, 16.0, 8.0):
		failures.append("fog occluder rect does not follow the host collision shape")
	body.free()


func _assert_state_changes_registration(failures: Array[String]) -> void:
	var body := _make_body(Vector2.ZERO, Vector2(8.0, 16.0), Vector2(4.0, 8.0))
	add_child(body)
	var occluder: Node = OCCLUDER_SCRIPT.new()
	body.add_child(occluder)
	occluder.call("set_blocking", false)
	if bool(occluder.call("is_occluding")):
		failures.append("a see-through fog occluder still occludes")
	if not occluder.is_in_group(OCCLUDER_GROUP):
		failures.append("clearing blocks_sight dropped the occluder from the group")
	occluder.call("set_blocking", true)
	if not bool(occluder.call("is_occluding")):
		failures.append("restoring blocks_sight did not re-enable occlusion")
	occluder.call("set_enabled", false)
	if bool(occluder.call("is_occluding")) or occluder.is_in_group(OCCLUDER_GROUP):
		failures.append("disabled fog occluder stayed registered")
	occluder.call("set_enabled", true)
	if not occluder.is_in_group(OCCLUDER_GROUP) or not bool(occluder.call("is_occluding")):
		failures.append("re-enabling the fog occluder did not register it again")
	body.free()


func _assert_refresh_only_on_cell_change(failures: Array[String]) -> void:
	var fog := FakeFog.new()
	add_child(fog)
	var body := _make_body(Vector2.ZERO, Vector2(4.0, 4.0), Vector2(2.0, 2.0))
	add_child(body)
	var occluder: Node = OCCLUDER_SCRIPT.new()
	body.add_child(occluder)
	if bool(occluder.call("refresh_if_moved")):
		failures.append("fog occluder refreshed without moving")
	body.position += Vector2(4.0, 0.0)
	if bool(occluder.call("refresh_if_moved")):
		failures.append("fog occluder refreshed inside the same cell")
	if fog.refreshes != 0:
		failures.append("fog occluder asked the fog to rebuild inside the same cell")
	body.position += Vector2(1.0, 0.0)
	if not bool(occluder.call("refresh_if_moved")):
		failures.append("fog occluder did not refresh after crossing a cell")
	if fog.refreshes != 1:
		failures.append("fog occluder did not reach the fog_of_war group exactly once")
	occluder.call("refresh")
	if fog.refreshes != 2:
		failures.append("explicit refresh did not reach the fog_of_war group")
	fog.free()
	body.free()


func _assert_size_override(failures: Array[String]) -> void:
	var body := _make_body(Vector2.ZERO, Vector2(8.0, 8.0), Vector2(4.0, 4.0))
	add_child(body)
	var occluder: Node = OCCLUDER_SCRIPT.new()
	occluder.set("size_override", Vector2(8.0, 16.0))
	occluder.set("position", Vector2(16.0, 24.0))
	body.add_child(occluder)
	if occluder.call("get_world_rect") != Rect2(16.0, 24.0, 8.0, 16.0):
		failures.append("size override did not replace the host footprint")
	occluder.set("footprint_offset", Vector2(2.0, 2.0))
	if occluder.call("get_world_rect") != Rect2(18.0, 26.0, 8.0, 16.0):
		failures.append("footprint offset was not applied to the size override")
	occluder.set("size_override", Vector2.ZERO)
	if occluder.call("get_world_rect") != Rect2(0.0, 0.0, 8.0, 8.0):
		failures.append("clearing the size override did not restore the host footprint")
	body.free()
