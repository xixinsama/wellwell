extends "res://addons/pixelfx/core/effect.gd"

## Pixel water splash for the hero entering (or hopping out of) a pool.
##
## One effect covers the whole speed range: `power` (0.15 .. 2.5) scales the
## droplet count, spray speed, crown width and mist. Droplets are random per
## impact; there are deliberately no round ring ripples, because the game is a
## side view and rings only read from above.

const Px := preload("res://addons/pixelfx/core/px.gd")
const Water := preload("res://addons/pixelfx/fx/water/_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Hero water splash",
	"size": [72, 52],
	"origin": [36, 46],
	"duration": 1.05,
	"loop": false,
	"fps": 30,
	"options": {"palette": Water.WATER, "power": 1.0, "seed": 17},
}

var o: Dictionary
var C: Array
var R: Px.Rng
var drops: Water.Drops
var mist: Water.Mist
var lights: Px.Lights
var power := 1.0
var t := 0.0
var _sprayed := false
var _foamed := false


func create(o_: Dictionary) -> void:
	o = o_
	power = clampf(float(o.get("power", 1.0)), 0.15, 2.5)
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	drops = Water.Drops.new({"sy": 0.55, "g": 760.0})
	mist = Water.Mist.new()
	lights = Px.Lights.new()
	t = 0.0
	_sprayed = false
	_foamed = false


func update(dt: float) -> void:
	t += dt
	if not _sprayed:
		_sprayed = true
		_spray()
	if not _foamed and t >= 0.16:
		_foamed = true
		_foam()
	drops.update(dt)
	mist.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	drops.draw(p, C, "back")


func draw(p: Px.Painter) -> void:
	if t < 0.14:
		var flash := 1.0 - t / 0.14
		p.ellipse(0.0, 0.0, 5.0 + 9.0 * power, 2.0, func(d: float, _a: float):
			return WHITE if d < 0.55 else null)
		Px.sparkle(p, 0.0, -2.0, 3.0 + 3.0 * power * flash, C[6], WHITE, 0.35)
	Water.lace(p, 0.0, 0.0, 6.0 + 12.0 * power, 2.2 + 2.0 * power, clampf(1.0 - t * 0.7, 0.0, 1.0), C, t, float(o.seed))
	drops.draw(p, C, "front")
	mist.draw(p, C[5])
	lights.draw(p)
	p.glow(0.0, -1.0, 10.0 + 12.0 * power, C[4], 0.22 * clampf(1.0 - t, 0.0, 1.0))


func _spray() -> void:
	lights.add(0.0, -2.0, 26.0 + 22.0 * power, C[5], 0.34 * power, 0.3)
	var count := int(round(9.0 + 14.0 * power))
	for index: int in count:
		var rng := Px.rng(o.seed, index, 31)
		var spread := rng.range(-1.0, 1.0)
		var speed := rng.range(28.0, 70.0) * power
		var lift := rng.range(70.0, 165.0) * (0.55 + 0.45 * power)
		var size := 3.0 if rng.chance(0.25 * power) else (2.0 if rng.chance(0.5) else 1.0)
		drops.add({
			"x": spread * 2.0,
			"z": rng.range(-3.0, 3.0),
			"h": rng.range(1.0, 4.0),
			"vx": spread * speed,
			"vz": rng.range(-10.0, 10.0),
			"vh": lift,
			"s": size,
			"life": rng.range(0.9, 1.3),
		})


func _foam() -> void:
	for index: int in int(3.0 + 4.0 * power):
		var rng := Px.rng(o.seed, index, 77)
		mist.add(
			rng.range(-6.0, 6.0) * power,
			-rng.range(1.0, 5.0),
			rng.range(-30.0, 30.0) * power,
			-rng.range(4.0, 14.0),
			rng.range(1.5, 3.0),
			rng.range(4.0, 8.0) * (0.7 + 0.5 * power),
			rng.range(0.45, 0.8),
			C[6],
			rng.range(0.18, 0.3)
		)
