class_name Hitbox
extends Area2D

signal hit_confirmed(hurtbox: Area2D)

@export var damage_data: Resource
@export var team: StringName


func _ready() -> void:
    area_entered.connect(_on_area_entered)


func deliver_to(hurtbox: Area2D) -> bool:
    if hurtbox == null or not hurtbox.has_method("receive_damage"):
        return false
    if not bool(hurtbox.call("receive_damage", damage_data, self, team)):
        return false
    hit_confirmed.emit(hurtbox)
    return true


func _on_area_entered(area: Area2D) -> void:
    deliver_to(area)
