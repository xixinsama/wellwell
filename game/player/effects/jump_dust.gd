extends "res://addons/pixelfx/core/effect.gd"

const Px := preload("res://addons/pixelfx/core/px.gd")
const P := Px.P

static var meta := {
	"name": "Player jump dust", "size": [24, 20], "origin": [12, 16],
	"duration": 0.4, "loop": false, "fps": 30,
	"options": {"palette": ["#625b61", "#a39a96", "#d2c8bb"], "seed": 11},
}

var particles: Px.Particles


func create(o: Dictionary) -> void:
	var colors := Px.fit(o.palette, 3)
	var rng := Px.Rng.new(o.seed)
	particles = Px.Particles.new({"rng": rng})
	for side: int in [-1, 1]:
		for index: int in range(2):
			particles.spawn(P.DUST, side * (1.0 + index), -1.0, side * rng.range(10.0, 18.0), -rng.range(4.0, 9.0), rng.range(0.18, 0.30), colors[1], rng.range(0.7, 1.1))
	for index: int in range(3):
		particles.spawn(P.GRIT, rng.range(-2.0, 2.0), -1.0, rng.range(-5.0, 5.0), rng.range(8.0, 16.0), rng.range(0.18, 0.28), colors[0])


func update(dt: float) -> void:
	particles.update(dt)


func draw(p: Px.Painter) -> void:
	particles.draw(p)
