extends "res://addons/pixelfx/core/effect.gd"

const Px := preload("res://addons/pixelfx/core/px.gd")
const P := Px.P

static var meta := {
	"name": "Player land dust", "size": [32, 20], "origin": [16, 16],
	"duration": 0.52, "loop": false, "fps": 30,
	"options": {"palette": ["#625b61", "#a39a96", "#d2c8bb"], "seed": 37},
}

var particles: Px.Particles


func create(o: Dictionary) -> void:
	var colors := Px.fit(o.palette, 3)
	var rng := Px.Rng.new(o.seed)
	particles = Px.Particles.new({"rng": rng})
	for side: int in [-1, 1]:
		for index: int in range(3):
			particles.spawn(P.DUST, side * rng.range(1.0, 3.0), -rng.range(0.5, 1.5), side * rng.range(12.0, 24.0), -rng.range(6.0, 14.0), rng.range(0.30, 0.44), colors[1], rng.range(0.8, 1.35), index * 0.015)


func update(dt: float) -> void:
	particles.update(dt)


func draw(p: Px.Painter) -> void:
	particles.draw(p)
