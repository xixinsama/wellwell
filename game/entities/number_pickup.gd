class_name NumberPickup
extends "res://addons/platformer_kit/world/entities/pickup_entity.gd"

## A numbered collectible: the number is its identity, not a quantity.
##
## Drop it under a room's `RoomContent/Entities`, fill [member number] and bake.
## It bobs, glows faintly (an additive halo, no light system needed) and is
## collected on player contact. [Collectibles] records the number for the
## collection screen, and the inherited pickup state keeps it collected after a
## save/load.
##
## The number must be unique inside its world; the registry shows one cell per
## number so a missing one is obvious at a glance.

const REGISTRY := "/root/Collectibles"

@export var number := 1:
	set(value):
		number = maxi(1, value)
		if is_node_ready():
			_sync_number()

@export_range(0.0, 8.0, 0.1) var bob_pixels := 2.0
@export_range(0.05, 2.0, 0.01) var bob_speed := 0.5

var _time := 0.0
var _visual: Node2D
var _number_label: Label
var _glow: Array[Polygon2D] = []


func _ready() -> void:
	super()
	entity_type = "number_pickup"
	if entity_id.is_empty():
		entity_id = "number_%d" % number
	_visual = get_node_or_null("VisualRoot") as Node2D
	_number_label = get_node_or_null("VisualRoot/Number") as Label
	for glow_path: String in ["VisualRoot/GlowOuter", "VisualRoot/GlowInner"]:
		var polygon := get_node_or_null(glow_path) as Polygon2D
		if polygon != null:
			_glow.append(polygon)
	var area := get_node_or_null("ActivationArea") as Area2D
	if area != null and not area.body_entered.is_connected(_on_body_entered):
		area.body_entered.connect(_on_body_entered)
	_sync_number()
	if collected:
		_stop_effects()


## The room runtime supplies the world id here; registering earlier would file
## the number under whatever world the registry happened to be showing.
func setup_entity(context: Dictionary) -> void:
	super(context)
	_register()


func _process(delta: float) -> void:
	if collected:
		return
	_time += delta
	var phase := _time * bob_speed * TAU
	if _visual != null:
		_visual.position.y = sin(phase) * bob_pixels
	var pulse := 0.72 + 0.28 * sin(phase + 0.9)
	for polygon: Polygon2D in _glow:
		polygon.modulate.a = pulse


func collect() -> void:
	if collected:
		return
	var registry := get_node_or_null(REGISTRY)
	if registry != null and registry.has_method("collect_number"):
		registry.call("collect_number", number, _world_id())
	super()
	_stop_effects()
	request_save(true)


func apply_save_state(state: Dictionary) -> void:
	super(state)
	if collected:
		_stop_effects()


func _on_body_entered(body: Node) -> void:
	if collected or body == null:
		return
	if not body.is_in_group(&"player"):
		return
	collect()


func _register() -> void:
	var registry := get_node_or_null(REGISTRY)
	if registry != null and registry.has_method("register_number"):
		registry.call("register_number", number, _world_id())


func _world_id() -> String:
	return String(get_meta("world_id", ""))


func _sync_number() -> void:
	if _number_label != null:
		_number_label.text = str(number)


func _stop_effects() -> void:
	set_process(false)
	if _visual != null:
		_visual.visible = false
