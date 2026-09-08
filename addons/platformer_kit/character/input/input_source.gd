class_name InputSource
extends RefCounted

const CHARACTER_INTENT := preload("res://addons/platformer_kit/character/input/character_intent.gd")


func get_intent() -> CHARACTER_INTENT:
	return CHARACTER_INTENT.new()

