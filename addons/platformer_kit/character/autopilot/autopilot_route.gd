class_name AutopilotRoute
extends RefCounted

## An ordered list of movement legs from a start point to a goal cell.

const LEG := preload("res://addons/platformer_kit/character/autopilot/autopilot_leg.gd")

var legs: Array[AutopilotLeg] = []
var start_position := Vector2.ZERO
var goal_position := Vector2.ZERO
var goal_cell := Vector2i.ZERO


func is_empty() -> bool:
	return legs.is_empty()


func get_leg_count() -> int:
	return legs.size()


func get_frames() -> int:
	var total := 0
	for leg: AutopilotLeg in legs:
		total += leg.frames
	return total


func get_seconds(tick_rate: float = 120.0) -> float:
	if tick_rate <= 0.0:
		return 0.0
	return float(get_frames()) / tick_rate


func get_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for leg: AutopilotLeg in legs:
		for point: Vector2 in leg.samples:
			points.append(point)
	return points


## Unique action labels in route order, for status text.
func get_action_labels() -> Array[String]:
	var labels: Array[String] = []
	for leg: AutopilotLeg in legs:
		var label := leg.action_label()
		if labels.is_empty() or labels[labels.size() - 1] != label:
			labels.append(label)
	return labels


func describe() -> String:
	var labels := get_action_labels()
	if labels.is_empty():
		return "空"
	return " → ".join(labels)


func append_leg(leg: AutopilotLeg) -> void:
	if leg == null or leg.frames <= 0:
		return
	legs.append(leg)


func clear() -> void:
	legs.clear()
