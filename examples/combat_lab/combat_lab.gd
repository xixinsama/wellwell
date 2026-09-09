extends Node2D

@onready var health: Node = $HealthComponent
@onready var hitbox: Area2D = $Hitbox
@onready var hurtbox: Area2D = $Hurtbox
@onready var invulnerability: Node = $Invulnerability
@onready var knockback: Node = $Knockback
@onready var status: Label = $Status


func _ready() -> void:
	health.reset_to_max()
	hurtbox.bind_components(health, invulnerability, knockback)
	hitbox.deliver_to(hurtbox)
	status.text = "Health: %.0f / %.0f\nKnockback: %s" % [
		health.current_health,
		health.max_health,
		str(knockback.get_velocity()),
	]
