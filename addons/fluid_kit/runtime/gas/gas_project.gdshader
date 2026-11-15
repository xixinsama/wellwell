shader_type canvas_item;

// Navier-Stokes projection: subtract the pressure gradient from the
// intermediate velocity, which makes it divergence free (incompressible):
//
//     u = u* - gradient(p)
//
// The gradient is a FORWARD difference, the exact adjoint of the BACKWARD
// difference divergence used by the pressure solve, so
//
//     divergence(u) = divergence(u*) - laplacian(p) = 0
//
// in the same discrete scheme. Next to a wall the pressure is taken from the
// centre cell (zero gradient), so no flow is pushed through the wall.

uniform sampler2D velocity_texture : filter_linear, repeat_disable;
uniform sampler2D pressure_texture : filter_linear, repeat_disable;
uniform sampler2D mask_texture : filter_nearest, repeat_disable;
uniform vec2 grid_size = vec2(80.0, 45.0);
uniform vec2 mask_cell_count = vec2(40.0, 23.0);
uniform vec2 field_size = vec2(320.0, 180.0);
uniform bool initialize = false;

float solid_at(vec2 fuv) {
	vec2 mask_uv = fuv * (field_size / (8.0 * max(mask_cell_count, vec2(1.0))));
	return texture(mask_texture, clamp(mask_uv, vec2(0.0), vec2(1.0))).r;
}

void fragment() {
	vec2 fuv = UV;
	vec2 velocity = vec2(0.0);
	if (!initialize && solid_at(fuv) < 0.5) {
		vec2 texel = vec2(1.0 / grid_size.x, 1.0 / grid_size.y);
		float p_center = texture(pressure_texture, fuv).r;
		float p_right = solid_at(fuv + vec2(texel.x, 0.0)) > 0.5 ? p_center : texture(pressure_texture, fuv + vec2(texel.x, 0.0)).r;
		float p_down = solid_at(fuv + vec2(0.0, texel.y)) > 0.5 ? p_center : texture(pressure_texture, fuv + vec2(0.0, texel.y)).r;
		velocity = texture(velocity_texture, fuv).rg - vec2(p_right - p_center, p_down - p_center);
	}
	COLOR = vec4(velocity, 0.0, 1.0);
}
