extends "res://addons/pixelfx/core/effect.gd"

const Px := preload("res://addons/pixelfx/core/px.gd")
const P := Px.P

static var meta := {
	"name": "Player run dust", "size": [16, 14], "origin": [8, 11],
	"duration": 0.32, "loop": false, "fps": 30,
	"options": {"palette": ["#625b61", "#a39a96", "#d2c8bb"], "seed": 23},
}

var particles: Px.Particles


func create(o: Dictionary) -> void:
	var colors := Px.fit(o.palette, 3)
	var rng := Px.Rng.new(o.seed)
	particles = Px.Particles.new({"rng": rng})
	for index: int in range(2):
		particles.spawn(P.DUST, -2.0 - index, -1.0, -rng.range(9.0, 16.0), -rng.range(3.0, 8.0), rng.range(0.18, 0.27), colors[1], rng.range(0.65, 1.0))


func update(dt: float) -> void:
	particles.update(dt)


func draw(p: Px.Painter) -> void:
	particles.draw(p)
