extends Node

## Coverage for the WorldStack resource: the authored "multi-layer world" that
## the editor's 3D view draws. Pure data, no file IO.

const STACK := preload("res://addons/platformer_kit/world/data/world_stack_data.gd")
const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_layer_lookup(failures)
	_assert_normalize(failures)
	_assert_insert_and_remove(failures)
	_assert_move_layer(failures)
	return failures


func _make_world(world_id: String) -> WorldData:
	var world := WORLD_DATA.new() as WorldData
	world.world_id = world_id
	return world


func _assert_layer_lookup(failures: Array[String]) -> void:
	var stack: WorldStack = STACK.new() as WorldStack
	if stack.get_layer_count() != 0 or stack.has_world("a") or stack.get_layer_index("a") != -1:
		failures.append("an empty WorldStack reports layers it does not have")
	var a := _make_world("a")
	var b := _make_world("b")
	stack.layers.assign([a, b])
	if stack.get_layer_index("b") != 1:
		failures.append("WorldStack.get_layer_index did not find the second layer")
	if not stack.has_world("a"):
		failures.append("WorldStack.has_world missed an authored layer")
	if stack.get_world_ids() != (["a", "b"] as Array[String]):
		failures.append("WorldStack.get_world_ids did not keep the layer order: %s" % str(stack.get_world_ids()))
	if stack.get_layer_index("missing") != -1:
		failures.append("WorldStack.get_layer_index invented a layer")


func _assert_normalize(failures: Array[String]) -> void:
	var stack: WorldStack = STACK.new() as WorldStack
	var a := _make_world("a")
	var b := _make_world("b")
	var duplicate := _make_world("a")
	var blank := WORLD_DATA.new() as WorldData
	stack.layers.assign([a, null, b, duplicate, blank])
	stack.normalize()
	if stack.get_layer_count() != 2:
		failures.append("normalize did not drop nulls, blank ids and duplicates: %d" % stack.get_layer_count())
	if stack.get_world_ids() != (["a", "b"] as Array[String]):
		failures.append("normalize changed the authored order: %s" % str(stack.get_world_ids()))


func _assert_insert_and_remove(failures: Array[String]) -> void:
	var stack: WorldStack = STACK.new() as WorldStack
	var a := _make_world("a")
	var b := _make_world("b")
	if not stack.insert_world(a) or not stack.insert_world(b):
		failures.append("insert_world rejected a valid world")
	if stack.insert_world(b):
		failures.append("insert_world accepted a duplicate world")
	if stack.insert_world(null) or stack.insert_world(WORLD_DATA.new() as WorldData):
		failures.append("insert_world accepted a null or id-less world")
	var c := _make_world("c")
	stack.insert_world(c, 1)
	if stack.get_world_ids() != (["a", "c", "b"] as Array[String]):
		failures.append("insert_world ignored the requested layer index: %s" % str(stack.get_world_ids()))
	if not stack.remove_world("c") or stack.get_world_ids() != (["a", "b"] as Array[String]):
		failures.append("remove_world did not drop the requested layer")
	if stack.remove_world("missing"):
		failures.append("remove_world reported removing a layer that is not there")


func _assert_move_layer(failures: Array[String]) -> void:
	var stack: WorldStack = STACK.new() as WorldStack
	stack.layers.assign([_make_world("a"), _make_world("b"), _make_world("c")])
	if not stack.move_layer(0, 2) or stack.get_world_ids() != (["b", "c", "a"] as Array[String]):
		failures.append("move_layer did not move the bottom layer to the top: %s" % str(stack.get_world_ids()))
	if not stack.move_layer(2, 0) or stack.get_world_ids() != (["a", "b", "c"] as Array[String]):
		failures.append("move_layer did not move the top layer to the bottom: %s" % str(stack.get_world_ids()))
	if stack.move_layer(5, 0):
		failures.append("move_layer accepted an out-of-range source index")
	if stack.move_layer(0, 0):
		failures.append("move_layer reported a move to the same index")
	if not stack.move_layer(0, 99) or stack.get_world_ids() != (["b", "c", "a"] as Array[String]):
		failures.append("move_layer did not clamp a target past the end: %s" % str(stack.get_world_ids()))
