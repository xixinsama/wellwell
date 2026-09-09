extends Node2D

const ABILITY_DEFINITION := preload("res://addons/platformer_abilities/runtime/ability_definition.gd")
const ABILITY_CONTEXT := preload("res://addons/platformer_abilities/runtime/ability_context.gd")

@onready var controller: Node = $AbilityController
@onready var status: Label = $Status


func _ready() -> void:
    var definition: Resource = ABILITY_DEFINITION.new()
    definition.ability_id = &"lab_dash"
    definition.cooldown_seconds = 0.5
    controller.add_definition(definition)
    var context: RefCounted = ABILITY_CONTEXT.new()
    controller.try_activate(&"lab_dash", context)
    status.text = "Ability: lab_dash\nActive: true\nCooldown: 0.5 s"
