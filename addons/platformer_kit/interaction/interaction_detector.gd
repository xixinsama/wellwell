class_name InteractionDetector
extends Area2D

signal candidate_changed(candidate: Interactable)

var _candidates: Array[Interactable] = []
var _current_candidate: Interactable


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func register_candidate(candidate: Interactable) -> void:
	if candidate == null or candidate in _candidates:
		return
	_candidates.append(candidate)
	_refresh_candidate()


func unregister_candidate(candidate: Interactable) -> void:
	_candidates.erase(candidate)
	_refresh_candidate()


func get_best_candidate(actor: Node = null) -> Interactable:
	var best: Interactable
	for candidate: Interactable in _candidates:
		if not is_instance_valid(candidate) or not candidate.can_interact(actor):
			continue
		if best == null or candidate.interaction_priority > best.interaction_priority:
			best = candidate
	return best


func interact(actor: Node) -> bool:
	var candidate := get_best_candidate(actor)
	return candidate.interact(actor) if candidate != null else false


func _refresh_candidate() -> void:
	var next_candidate := get_best_candidate()
	if next_candidate == _current_candidate:
		return
	_current_candidate = next_candidate
	candidate_changed.emit(_current_candidate)


func _on_area_entered(area: Area2D) -> void:
	var candidate := area as Interactable
	if candidate != null:
		register_candidate(candidate)


func _on_area_exited(area: Area2D) -> void:
	var candidate := area as Interactable
	if candidate != null:
		unregister_candidate(candidate)
