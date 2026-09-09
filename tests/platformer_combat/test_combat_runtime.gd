extends Node

const DAMAGE_DATA_PATH := "res://addons/platformer_combat/runtime/damage_data.gd"
const HEALTH_PATH := "res://addons/platformer_combat/runtime/health_component.gd"
const HITBOX_PATH := "res://addons/platformer_combat/runtime/hitbox.gd"
const HURTBOX_PATH := "res://addons/platformer_combat/runtime/hurtbox.gd"
const INVULNERABILITY_PATH := "res://addons/platformer_combat/runtime/invulnerability.gd"
const KNOCKBACK_PATH := "res://addons/platformer_combat/runtime/knockback.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	var scripts: Array[Script] = []
	for path: String in [
		DAMAGE_DATA_PATH,
		HEALTH_PATH,
		HITBOX_PATH,
		HURTBOX_PATH,
		INVULNERABILITY_PATH,
		KNOCKBACK_PATH,
	]:
		var script := load(path) as Script
		if script == null:
			failures.append("combat runtime script is missing: %s" % path)
		else:
			scripts.append(script)
	if not failures.is_empty():
		return failures

	var damage: Resource = scripts[0].new()
	damage.set("amount", 3.0)
	damage.set("impulse", Vector2(20.0, -10.0))
	var health: Node = scripts[1].new()
	health.set("max_health", 10.0)
	health.call("_ready")
	if not is_equal_approx(float(health.get("current_health")), 10.0):
		failures.append("health component did not initialize to max health")
	var hitbox: Area2D = scripts[2].new()
	hitbox.set("damage_data", damage)
	hitbox.set("team", &"player")
	var hurtbox: Area2D = scripts[3].new()
	hurtbox.set("team", &"enemy")
	var invulnerability: Node = scripts[4].new()
	invulnerability.set("duration", 0.25)
	var knockback: Node = scripts[5].new()
	hurtbox.call("bind_components", health, invulnerability, knockback)

	if not hitbox.call("deliver_to", hurtbox):
		failures.append("hitbox did not route damage to a valid hurtbox")
	if not is_equal_approx(float(health.get("current_health")), 7.0):
		failures.append("health component did not apply routed damage")
	if knockback.call("get_velocity") != Vector2(20.0, -10.0):
		failures.append("damage impulse was not routed to knockback")
	if hitbox.call("deliver_to", hurtbox):
		failures.append("invulnerability did not reject a repeated hit")
	if not is_equal_approx(float(health.get("current_health")), 7.0):
		failures.append("rejected hit changed health")
	if not invulnerability.has_method("_process"):
		failures.append("invulnerability has no runtime frame driver")
	else:
		invulnerability.call("_process", 0.25)
		if not hitbox.call("deliver_to", hurtbox):
			failures.append("hurtbox stayed invulnerable after duration elapsed")
	if not knockback.has_method("_physics_process"):
		failures.append("knockback has no runtime physics driver")
	else:
		knockback.call("_physics_process", 0.025)
		if knockback.call("get_velocity").length() >= Vector2(20.0, -10.0).length():
			failures.append("knockback did not decay during physics processing")

	var ally_hurtbox: Area2D = scripts[3].new()
	ally_hurtbox.set("team", &"player")
	ally_hurtbox.call("bind_components", health, null, null)
	if hitbox.call("deliver_to", ally_hurtbox):
		failures.append("hitbox damaged a matching team")

	ally_hurtbox.free()
	hurtbox.free()
	hitbox.free()
	knockback.free()
	invulnerability.free()
	health.free()
	return failures
