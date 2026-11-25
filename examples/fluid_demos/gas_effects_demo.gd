extends Node

## Demo: the three gas effects cycle forever on the gas lab room.
##
##   A. the three vents blast at several times their normal rate;
##   B. an explosion at the middle of the room;
##   C. a 1x4-cell pillar sweeps left and right and shreds the gas into turbulence.
##
## Run this scene windowed (F6) and watch; it never stops.

const RUNNER := preload("res://scenes/levels/test_world/runners/gas_lab_runner.tscn")
const PILLAR_SIZE := Vector2(8.0, 32.0)
const ROOM_EXPLOSION := Vector2(176.0, 92.0)
const ROOM_SWEEP_CENTER := Vector2(128.0, 96.0)
const SWEEP_AMPLITUDE := 64.0
const SWEEP_SPEED := 2.6

const PHASES: Array[String] = ["jets", "explosion", "pillar"]
const PHASE_SECONDS: Array[float] = [2.8, 2.6, 3.4]

var _runner: Node
var _world_root: Node
var _atmosphere: Node
var _room: Rect2
var _pillar: ColorRect
var _vents: Array[Node] = []
var _phase := -1
var _phase_time := 0.0
var _sweep_time := 0.0
var _last_pillar_x := 0.0


func _ready() -> void:
	_runner = RUNNER.instantiate()
	add_child(_runner)
	await get_tree().create_timer(1.2).timeout
	_world_root = _runner.get_node("SubViewportContainer/SubViewport/WorldRoot")
	_atmosphere = _world_root.get_node_or_null("Atmosphere")
	_room = _atmosphere.call("get_room_rect") if _atmosphere != null else Rect2()
	_activate_phase(0)


func _process(delta: float) -> void:
	if _phase < 0:
		return
	_phase_time += delta
	if PHASES[_phase] == "pillar":
		_update_pillar(delta)
	if _phase_time >= PHASE_SECONDS[_phase]:
		_activate_phase((_phase + 1) % PHASES.size())


func _activate_phase(index: int) -> void:
	_phase = index
	_phase_time = 0.0
	var phase := PHASES[index]
	print("phase: %s" % phase)
	if phase != "pillar":
		if _atmosphere != null:
			_atmosphere.call("clear_gas_mover")
		if _pillar != null:
			_pillar.visible = false
	match phase:
		"jets":
			_restore_vents()
			_boost_vents(4.0, 3.0)
		"explosion":
			_restore_vents()
			if _atmosphere != null:
				_atmosphere.call("trigger_explosion", _room.position + ROOM_EXPLOSION, 34.0, 190.0, 1.1)
		"pillar":
			_sweep_time = 0.0
			_last_pillar_x = _room.position.x + ROOM_SWEEP_CENTER.x
			_show_pillar()


func _boost_vents(rate_scale: float, jet_scale: float) -> void:
	_vents.clear()
	for node: Node in get_tree().get_nodes_in_group(&"gas_vent"):
		if not is_instance_valid(node):
			continue
		_vents.append(node)
		node.set("rate", float(node.get("rate")) * rate_scale)
		node.set("jet_speed", float(node.get("jet_speed")) * jet_scale)
	if _atmosphere != null:
		_atmosphere.call("refresh_vents")


func _restore_vents() -> void:
	if _vents.is_empty():
		return
	for node: Node in _vents:
		if not is_instance_valid(node):
			continue
		node.set("rate", float(node.get("rate")) / 4.0)
		node.set("jet_speed", float(node.get("jet_speed")) / 3.0)
	_vents.clear()
	if _atmosphere != null:
		_atmosphere.call("refresh_vents")


func _show_pillar() -> void:
	if _pillar == null:
		_pillar = ColorRect.new()
		_pillar.color = Color(0.72, 0.76, 0.84, 1.0)
		_pillar.z_index = 12
		_pillar.size = PILLAR_SIZE
		_world_root.add_child(_pillar)
	_pillar.position = Vector2(
		_room.position.x + ROOM_SWEEP_CENTER.x - PILLAR_SIZE.x * 0.5,
		_room.position.y + ROOM_SWEEP_CENTER.y - PILLAR_SIZE.y * 0.5
	)
	_pillar.visible = true


func _update_pillar(delta: float) -> void:
	_sweep_time += delta
	var center_x := _room.position.x + ROOM_SWEEP_CENTER.x + sin(_sweep_time * SWEEP_SPEED) * SWEEP_AMPLITUDE
	var velocity := Vector2((center_x - _last_pillar_x) / maxf(delta, 0.001), 0.0)
	_last_pillar_x = center_x
	if _pillar != null:
		_pillar.position.x = center_x - PILLAR_SIZE.x * 0.5
	if _atmosphere != null:
		_atmosphere.call("set_gas_mover", Vector2(center_x, _room.position.y + ROOM_SWEEP_CENTER.y), PILLAR_SIZE * 0.5, velocity)
