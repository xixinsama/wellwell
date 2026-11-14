extends "res://addons/pixelfx/core/effect.gd"

const Px := preload("res://addons/pixelfx/core/px.gd")
const P := Px.P

static var meta := {
	"name": "Player respawn hurt", "size": [24, 32], "origin": [12, 16],
	"duration": 0.58, "loop": false, "fps": 30,
	"options": {"palette": ["#6e1f35", "#c43c52", "#ff7770"], "seed": 51},
}

var particles: Px.Particles


func create(o: Dictionary) -> void:
	var colors := Px.fit(o.palette, 3)
	var rng := Px.Rng.new(o.seed)
	particles = Px.Particles.new({"rng": rng})
	for index: int in range(9):
		particles.spawn(P.FLAKE, rng.range(-3.0, 3.0), rng.range(-7.0, -2.0), rng.range(-4.0, 4.0), rng.range(12.0, 22.0), rng.range(0.30, 0.49), colors[index % colors.size()], 1.0, index * 0.006)


func update(dt: float) -> void:
	particles.update(dt)


func draw(p: Px.Painter) -> void:
	particles.draw(p)
