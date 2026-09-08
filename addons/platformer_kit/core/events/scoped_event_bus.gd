class_name ScopedEventBus
extends RefCounted

const GAME_EVENT := preload("res://addons/platformer_kit/core/events/game_event.gd")

var _subscribers: Dictionary[StringName, Array] = {}


func subscribe(topic: StringName, callback: Callable) -> bool:
	if topic.is_empty() or not callback.is_valid():
		return false
	var callbacks: Array = _subscribers.get(topic, [])
	if callbacks.has(callback):
		return false
	callbacks.append(callback)
	_subscribers[topic] = callbacks
	return true


func unsubscribe(topic: StringName, callback: Callable) -> bool:
	if not _subscribers.has(topic):
		return false
	var callbacks: Array = _subscribers[topic]
	var index := callbacks.find(callback)
	if index < 0:
		return false
	callbacks.remove_at(index)
	if callbacks.is_empty():
		_subscribers.erase(topic)
	return true


func publish(event: GAME_EVENT) -> void:
	if event == null or event.topic.is_empty():
		return
	var callbacks: Array = _subscribers.get(event.topic, []).duplicate()
	for callback: Callable in callbacks:
		if callback.is_valid():
			callback.call(event)
