shader_type canvas_item;

// Stream-function step of the gas solver.
//
// The flow velocity is defined as v = curl(psi) = (dpsi/dy, -dpsi/dx), so its
// divergence is identically zero: the gas is an incompressible fluid by
// construction. This pass advects psi with that velocity (plus the wind) and
// feeds it from the density gradients: a heavy gas peak twists psi one way, a
// light gas peak the other, which is what makes the plumes roll and sink or rise
// instead of piling up as a static layer.
//
// One psi texel per 4 px cell; HDR viewport so psi can be negative.

uniform sampler2D psi_previous : filter_linear, repeat_disable;
uniform sampler2D density_previous : filter_linear, repeat_disable;
uniform sampler2D mask_texture : filter_nearest, repeat_disable;
uniform vec2 field_size = vec2(320.0, 180.0);
uniform vec2 mask_cell_count = vec2(40.0, 23.0);
uniform float cell_size = 4.0;
uniform float delta = 0.0333333;
// psi decays over time (1/s) so old swirls fade out.
uniform float dissipation = 0.6;
// Uniform drift in pixels per second; a constant field is divergence free too.
uniform vec2 wind = vec2(7.0, -1.5);
// psi source per gas channel: x = heavy (sinks), y = neutral, z = light (rises).
uniform vec3 buoyancy = vec3(0.9, 0.0, 0.8);
uniform bool initialize = false;

float solid_at(vec2 fuv) {
	vec2 mask_uv = fuv * (field_size / (8.0 * max(mask_cell_count, vec2(1.0))));
	return texture(mask_texture, clamp(mask_uv, vec2(0.0), vec2(1.0))).r;
}

void fragment() {
	vec2 fuv = UV;
	float result = 0.0;
	if (solid_at(fuv) < 0.5 && !initialize) {
		vec2 texel = vec2(cell_size / field_size.x, cell_size / field_size.y);
		float left = texture(psi_previous, fuv - vec2(texel.x, 0.0)).r;
		float right = texture(psi_previous, fuv + vec2(texel.x, 0.0)).r;
		float up = texture(psi_previous, fuv - vec2(0.0, texel.y)).r;
		float down = texture(psi_previous, fuv + vec2(0.0, texel.y)).r;
		vec2 velocity = vec2(down - up, left - right) / (2.0 * cell_size) + wind;

		vec2 back = clamp(fuv - velocity * delta / field_size, vec2(0.0), vec2(1.0));
		float psi = texture(psi_previous, back).r;
		psi *= max(0.0, 1.0 - dissipation * delta);

		// Horizontal density gradients twist the stream function.
		float heavy_left = texture(density_previous, fuv - vec2(texel.x, 0.0)).r;
		float heavy_right = texture(density_previous, fuv + vec2(texel.x, 0.0)).r;
		float light_left = texture(density_previous, fuv - vec2(texel.x, 0.0)).b;
		float light_right = texture(density_previous, fuv + vec2(texel.x, 0.0)).b;
		psi += buoyancy.x * (heavy_right - heavy_left) * delta;
		psi += buoyancy.z * (light_left - light_right) * delta;
		result = clamp(psi, -2.0, 2.0);
	}
	COLOR = vec4(result, 0.0, 0.0, 1.0);
}
