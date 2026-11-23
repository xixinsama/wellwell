extends Node

## Buoyancy, swimming and entry behaviour of the player water component.
##
## The component talks to the water field only through is_ready / get_surface_y_at
## / get_depth_at / get_flow_velocity_at / request_splash, so a stub field is
## enough to drive it deterministically without a room.

const PLAYER_WATER_MOTION := preload("res://game/player/player_water_motion.gd")
const MOVEMENT_CONTEXT := preload("res://addons/platformer_kit/character/motor/movement_context.gd")
const CHARACTER_INTENT := preload("res://addons/platformer_kit/character/input/character_intent.gd")
const ENVIRONMENT_SNAPSHOT := preload("res://addons/platformer_kit/character/environment/character_environment_snapshot.gd")
const PROFILE := preload("res://resources/player/default_player_tuning.tres")

const STEP := 1.0 / 120.0


class StubWaterField extends Node2D:
	var surface_y := 100.0
	var flow := 0.0
	var splashes: Array[float] = []

	func is_ready() -> bool:
		return true

	func get_surface_y_at(_world_x: float) -> float:
		return surface_y

	func get_depth_at(_world_x: float) -> float:
		return 80.0

	func get_flow_velocity_at(_world_x: float) -> float:
		return flow

	func request_splash(_world_x: float, impact_speed: float) -> void:
		splashes.append(impact_speed)


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_body_floats_to_the_surface(failures)
	_assert_entry_speed_deepens_the_body(failures)
	_assert_shallow_water_leaves_the_motor_alone(failures)
	_assert_surface_hop_leaves_the_water(failures)
	_assert_flow_pushes_the_body_sideways(failures)
	return failures


func _assert_body_floats_to_the_surface(failures: Array[String]) -> void:
	var rig := _make_rig()
	var body: CharacterBody2D = rig["body"]
	body.global_position = Vector2(0.0, 112.0)
	var context := MOVEMENT_CONTEXT.new()
	var intent := CHARACTER_INTENT.new()
	for _frame: int in 600:
		_step(rig, context, intent)
	var bottom := body.global_position.y
	if bottom < 101.0:
		failures.append("submerged body did not settle near the surface: y=%.2f" % bottom)
	if bottom > 107.0:
		failures.append("body sank instead of floating: y=%.2f" % bottom)
	if absf(body.velocity.y) > 12.0:
		failures.append("floating body still moves vertically: vy=%.2f" % body.velocity.y)
	_free_rig(rig)


func _assert_entry_speed_deepens_the_body(failures: Array[String]) -> void:
	var rig := _make_rig()
	var body: CharacterBody2D = rig["body"]
	var field: StubWaterField = rig["field"]
	var context := MOVEMENT_CONTEXT.new()
	var intent := CHARACTER_INTENT.new()
	var fast := _entry_velocity(rig, context, intent, 300.0)
	if field.splashes.is_empty():
		failures.append("fast water entry did not request a splash")
	elif field.splashes[0] < 200.0:
		failures.append("fast entry splash used the impact speed poorly: %.1f" % field.splashes[0])
	var slow := _entry_velocity(rig, context, intent, 80.0)
	if fast <= slow + 20.0:
		failures.append(
			"entry depth did not follow impact speed: fast=%.1f slow=%.1f" % [fast, slow]
		)
	_free_rig(rig)


func _assert_shallow_water_leaves_the_motor_alone(failures: Array[String]) -> void:
	var rig := _make_rig()
	var body: CharacterBody2D = rig["body"]
	body.global_position = Vector2(0.0, 100.4)
	var context := MOVEMENT_CONTEXT.new()
	var intent := CHARACTER_INTENT.new()
	var handled := _step(rig, context, intent)
	if handled:
		failures.append("shallow water claimed the frame from the normal motor")
	var motion: Node2D = rig["motion"]
	if bool(motion.call("is_in_water")):
		failures.append("shallow water reported the body as swimming")
	_free_rig(rig)


func _assert_surface_hop_leaves_the_water(failures: Array[String]) -> void:
	var rig := _make_rig()
	var body: CharacterBody2D = rig["body"]
	body.global_position = Vector2(0.0, 102.0)
	var context := MOVEMENT_CONTEXT.new()
	var intent := CHARACTER_INTENT.new()
	for _frame: int in 4:
		_step(rig, context, intent)
	intent.jump_pressed = true
	var handled := _step(rig, context, intent)
	if not handled:
		failures.append("surface hop did not claim the frame")
	if context.velocity.y >= -150.0:
		failures.append("surface hop did not push the body up: vy=%.2f" % context.velocity.y)
	if not bool(context.just_jumped):
		failures.append("surface hop did not report just_jumped")
	_free_rig(rig)


func _assert_flow_pushes_the_body_sideways(failures: Array[String]) -> void:
	var rig := _make_rig()
	var body: CharacterBody2D = rig["body"]
	var field: StubWaterField = rig["field"]
	field.flow = 60.0
	body.global_position = Vector2(0.0, 102.0)
	var context := MOVEMENT_CONTEXT.new()
	var intent := CHARACTER_INTENT.new()
	for _frame: int in 40:
		_step(rig, context, intent)
	if context.velocity.x <= 0.0:
		failures.append("water flow did not push the body downstream: vx=%.2f" % context.velocity.x)
	_free_rig(rig)


func _entry_velocity(
	rig: Dictionary,
	context: RefCounted,
	intent: RefCounted,
	impact: float
) -> float:
	var body: CharacterBody2D = rig["body"]
	var motion: Node2D = rig["motion"]
	motion.call("reset")
	body.global_position = Vector2(0.0, 104.0)
	body.velocity = Vector2(0.0, impact)
	context.set("velocity", body.velocity)
	context.set("just_jumped", false)
	motion.call("step", context, intent, ENVIRONMENT_SNAPSHOT.new(), PROFILE, STEP)
	body.velocity = Vector2(context.get("velocity"))
	return body.velocity.y


func _step(rig: Dictionary, context: RefCounted, intent: RefCounted) -> bool:
	var body: CharacterBody2D = rig["body"]
	var motion: Node2D = rig["motion"]
	context.set("velocity", body.velocity)
	var handled := bool(motion.call("step", context, intent, ENVIRONMENT_SNAPSHOT.new(), PROFILE, STEP))
	if handled:
		body.velocity = Vector2(context.get("velocity"))
	else:
		# Stand in for the movement motor while the body is out of the water.
		body.velocity.y = minf(body.velocity.y + float(PROFILE.get("gravity")) * STEP, float(PROFILE.get("max_fall_speed")))
		body.velocity.x *= 0.99
	body.global_position += body.velocity * STEP
	return handled


func _make_rig() -> Dictionary:
	var field := StubWaterField.new()
	add_child(field)
	field.add_to_group(&"water_field")
	var body := CharacterBody2D.new()
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(6.0, 6.0)
	collision.shape = rectangle
	collision.position = Vector2(0.0, -3.0)
	body.add_child(collision)
	add_child(body)
	var motion := PLAYER_WATER_MOTION.new() as Node2D
	motion.name = "WaterMotion"
	body.add_child(motion)
	return {"field": field, "body": body, "motion": motion}


func _free_rig(rig: Dictionary) -> void:
	var body: CharacterBody2D = rig["body"]
	var field: Node2D = rig["field"]
	field.remove_from_group(&"water_field")
	field.queue_free()
	body.queue_free()
