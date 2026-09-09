class_name AbilityDefinition
extends Resource

@export var ability_id: StringName
@export var cooldown_seconds := 0.0
@export var enabled := true
@export var required_tags: Array[StringName] = []
@export var blocked_tags: Array[StringName] = []
@export var runtime_script: Script
