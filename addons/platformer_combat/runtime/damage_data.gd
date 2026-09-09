class_name DamageData
extends Resource

@export var amount := 1.0
@export var impulse := Vector2.ZERO
@export var damage_type: StringName = &"generic"
@export var tags: Array[StringName] = []


func duplicate_damage() -> Resource:
	return duplicate(true) as Resource
