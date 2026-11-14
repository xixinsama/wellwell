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


class RespawnOnlyPlayer:
	extends Node2D
	var respawn_count := 0

	func respawn_at(_target: Vector2) -> void:
		respawn_count += 1


class RespawnWithoutHurtPlayer:
	extends Node2D
	var spawn_position := Vector2(32, 96)
	var respawn_count := 0

	func respawn_at(target: Vector2) -> void:
		global_position = target
		respawn_count += 1


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
	var invalid_player := RespawnOnlyPlayer.new()
	invalid_player.add_to_group("player")
	add_child(invalid_player)
	zone.body_entered.emit(invalid_player)
	if invalid_player.respawn_count != 0:
		failures.append("player without spawn_position should be ignored")
	var player_without_hurt := RespawnWithoutHurtPlayer.new()
	player_without_hurt.add_to_group("player")
	add_child(player_without_hurt)
	zone.body_entered.emit(player_without_hurt)
	if player_without_hurt.respawn_count != 1 or player_without_hurt.global_position != player_without_hurt.spawn_position:
		failures.append("missing hurt-effect interface must not block respawn")
	zone.free()
	player.free()
	bystander.free()
	invalid_player.free()
	player_without_hurt.free()
	return failures
