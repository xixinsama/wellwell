class_name PlayerTuning
extends "res://addons/platformer_kit/character/resources/movement_profile.gd"

@export var ground_accel: float:
	get:
		return ground_acceleration
	set(value):
		ground_acceleration = value

@export var ground_decel: float:
	get:
		return ground_deceleration
	set(value):
		ground_deceleration = value

@export var air_accel: float:
	get:
		return air_acceleration
	set(value):
		air_acceleration = value

@export var air_decel: float:
	get:
		return air_deceleration
	set(value):
		air_deceleration = value
