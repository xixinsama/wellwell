class_name DashAbilityDefinition
extends "res://addons/platformer_abilities/runtime/ability_definition.gd"

const DASH_RUNTIME := preload("res://addons/platformer_abilities/abilities/dash/dash_ability_runtime.gd")

@export_range(0.0, 2000.0, 1.0, "or_greater") var dash_speed := 240.0
@export_range(0.01, 5.0, 0.01, "or_greater") var dash_duration := 0.16


func _init() -> void:
    ability_id = &"dash"
    runtime_script = DASH_RUNTIME
