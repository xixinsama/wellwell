class_name WaterSplashPixels
extends Node2D

## Cheap pixel water splash for an entry, a landing or a hop out of the water.
##
## This is intentionally not a baked PixelFX effect: baking the 72x52 splash
## costs about 300 ms, and because a baked effect is cached per option set, every
## distinct impact speed baked a new one. Jumping in and out of a pool re-baked on
## every landing and stalled the frame. Here a handful of 1-2 px droplets are
## integrated directly, which costs nothing to spawn and lets `power` stay
## continuous.
##
## The node's position is the impact point, on the water surface.

## Gravity on the droplets, px/s^2.
const GRAVITY := 620.0
## Longest droplet life, seconds.
const MAX_LIFE := 0.6
## Droplets per unit of power: the size of the splash follows the impact speed.
const DROPS_PER_POWER := 11.0
const FOAM_COLOR := Color(0.9, 0.98, 1.0, 0.95)
const SPRAY_COLOR := Color(0.62, 0.87, 1.0, 0.9)

@export var options := {}
@export var autoplay := false
@export var free_when_done := true
@export var speed_scale := 1.0

var _power := 1.0
var _drops := PackedFloat32Array()
var _count := 0
var _age := 0.0
var _started := false


func _ready() -> void:
	if autoplay:
		play()


func play() -> void:
	_power = clampf(float(options.get("power", 1.0)), 0.15, 2.5)
	_count = maxi(int(round(4.0 + DROPS_PER_POWER * _power)), 4)
	_drops.resize(_count * 5)
	for index in _count:
		var offset := index * 5
		# Two shoulders: the spray leaves the impact point mostly upwards and
		# outwards, a little wider and faster for a bigger impact.
		var side := -1.0 if index % 2 == 0 else 1.0
		var spread := randf_range(0.25, 1.0)
		_drops[offset] = randf_range(-2.0, 2.0) * _power
		_drops[offset + 1] = randf_range(-1.0, 1.0)
		_drops[offset + 2] = side * spread * (42.0 + 46.0 * _power)
		_drops[offset + 3] = -(52.0 + 96.0 * _power) * randf_range(0.55, 1.0)
		_drops[offset + 4] = randf_range(0.3, MAX_LIFE) * (0.8 + 0.2 * _power)
	_age = 0.0
	_started = true
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if not _started:
		return
	var step := maxf(delta, 0.0)
	_age += step
	var alive := 0
	for index in _count:
		var offset := index * 5
		var life := _drops[offset + 4]
		if life <= 0.0:
			continue
		_drops[offset] += _drops[offset + 2] * step
		_drops[offset + 1] += _drops[offset + 3] * step
		_drops[offset + 3] += GRAVITY * step
		_drops[offset + 4] = life - step
		if _drops[offset + 4] > 0.0:
			alive += 1
	queue_redraw()
	if alive == 0 and free_when_done:
		queue_free()


func _draw() -> void:
	if not _started:
		return
	var fade := clampf(1.0 - _age / (MAX_LIFE + 0.15), 0.0, 1.0)
	var crown := clampf(1.0 - _age / 0.18, 0.0, 1.0)
	if crown > 0.0:
		# A short bright crown on the surface, widening with the power.
		var half := roundf((3.0 + 6.0 * _power) * (0.4 + 0.6 * crown))
		draw_rect(Rect2(-half, 0.0, half * 2.0, 1.0), FOAM_COLOR * Color(1, 1, 1, crown))
	for index in _count:
		var offset := index * 5
		if _drops[offset + 4] <= 0.0:
			continue
		var drop := Vector2(roundf(_drops[offset]), roundf(_drops[offset + 1]))
		var color := FOAM_COLOR if index % 3 == 0 else SPRAY_COLOR
		color.a *= fade
		draw_rect(Rect2(drop, Vector2.ONE), color)
