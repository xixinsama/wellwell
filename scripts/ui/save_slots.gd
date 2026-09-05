class_name SaveSlots
extends Control

signal slot_chosen(slot: int)

@export var slot_count := 3
@onready var list: VBoxContainer = %SlotList

func _ready() -> void:
    _refresh()

func _refresh() -> void:
    for child: Node in list.get_children():
        child.queue_free()
    for slot: int in range(1, slot_count + 1):
        var button := Button.new()
        button.custom_minimum_size = Vector2(180, 60)
        button.text = _slot_text(slot)
        button.pressed.connect(func() -> void: slot_chosen.emit(slot))
        list.add_child(button)

func _slot_text(slot: int) -> String:
    var manager := get_node_or_null("/root/SaveManager")
    if manager == null:
        return "Slot %d" % slot
    var summary: Dictionary = manager.get_slot_summary(slot)
    return "Slot %d%s" % [slot, "  (used)" if summary.occupied else "  (empty)"]
