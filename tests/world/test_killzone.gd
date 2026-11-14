extends Node

class FakePlayer:
	extends Node2D
	var spawn_position := Vector2(68, 140)
	var events: Array[String] = []

	func respawn_at(target: Vector2) -> void:
		global_position = target
		events.append("respawn")

	func play_hurt_effect() -> void:
		events.append("hurt:%s" % str(global_position))


func run() -> Array[String]:
	var failures: Array[String] = []
	var packed := load("res://scenes/world/killzone.tscn") as PackedScene
	if packed == null:
		return ["reusable Killzone scene is missing"]
	var zone := packed.instantiate() as Area2D
	add_child(zone)
	if zone.collision_layer != 0 or zone.collision_mask != 2:
		failures.append("Killzone must detect player collision layer 2")
	var player := FakePlayer.new()
	player.add_to_group("player")
	add_child(player)
	zone.body_entered.emit(player)
	var expected := ["respawn", "hurt:%s" % str(player.spawn_position)]
	if player.events != expected:
		failures.append("Killzone must respawn before hurt feedback: %s" % str(player.events))
	var bystander := Node2D.new()
	add_child(bystander)
	zone.body_entered.emit(bystander)
	if player.events.size() != 2:
		failures.append("non-player contact retriggered Killzone")
	zone.free()
	player.free()
	bystander.free()
	return failures
