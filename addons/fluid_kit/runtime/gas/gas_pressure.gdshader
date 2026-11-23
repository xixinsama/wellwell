shader_type canvas_item;

// Navier-Stokes pressure solve. Solves the discrete Poisson equation
//
//     laplacian(p) = divergence(u*)      (grid spacing h = 1 cell)
//
// with Jacobi iterations
//
//     p_new = (p_left + p_right + p_up + p_down - divergence) / 4
//
// The divergence uses a BACKWARD difference and the projection uses a FORWARD
// difference, so the two compose into exactly the compact 5-point Laplacian the
// Jacobi solver inverts. That makes the projected velocity divergence free in the
// discrete scheme instead of leaving the O(1) residual a central difference pair
// produces. Solid cells get p = 0; the velocity at solid cells is zero, which is
// the no-penetration boundary condition.

uniform sampler2D velocity_texture : filter_linear, repeat_disable;
uniform sampler2D pressure_texture : filter_linear, repeat_disable;
uniform sampler2D mask_texture : filter_nearest, repeat_disable;
uniform vec2 grid_size = vec2(80.0, 45.0);
uniform vec2 mask_cell_count = vec2(40.0, 23.0);
uniform vec2 field_size = vec2(320.0, 180.0);
uniform bool first_iteration = false;

float solid_at(vec2 fuv) {
	vec2 mask_uv = fuv * (field_size / (8.0 * max(mask_cell_count, vec2(1.0))));
	return texture(mask_texture, clamp(mask_uv, vec2(0.0), vec2(1.0))).r;
}

void fragment() {
	vec2 fuv = UV;
	vec2 texel = vec2(1.0 / grid_size.x, 1.0 / grid_size.y);
	float result = 0.0;
	if (solid_at(fuv) < 0.5) {
		float u_center = texture(velocity_texture, fuv).r;
		float v_center = texture(velocity_texture, fuv).g;
		float u_left = texture(velocity_texture, clamp(fuv - vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).r;
		float v_up = texture(velocity_texture, clamp(fuv - vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).g;
		float divergence = (u_center - u_left) + (v_center - v_up);

		if (first_iteration) {
			result = -divergence * 0.25;
		} else {
			float p_left = texture(pressure_texture, clamp(fuv - vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).r;
			float p_right = texture(pressure_texture, clamp(fuv + vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).r;
			float p_up = texture(pressure_texture, clamp(fuv - vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).r;
			float p_down = texture(pressure_texture, clamp(fuv + vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).r;
			result = (p_left + p_right + p_up + p_down - divergence) * 0.25;
		}
	}
	COLOR = vec4(result, 0.0, 0.0, 1.0);
}
