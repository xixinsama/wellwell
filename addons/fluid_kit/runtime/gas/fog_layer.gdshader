shader_type canvas_item;
render_mode blend_mix;

// Draws the three-gas field.
//
// The field texture (R = heavy, G = neutral, B = light) comes from the GPU
// simulation viewport, or from a CPU fallback image. Each gas has its own color
// and opacity, so the density difference is visible: the heavy gas pools on the
// floor in warm rust, the neutral gas drifts through the room in cool cyan and
// the light gas gathers under the ceiling in pale gold.
//
// World space comes from the quad's UVs, never from VERTEX (a canvas_item
// fragment's VERTEX is not guaranteed to stay in the item's local space). The
// solid mask is one texel per terrain tile, so the gas is cut exactly at the
// collision silhouette. Keep the light falloff in sync with
// FogGrid.sample_light().

uniform sampler2D gas_texture : filter_linear, repeat_disable;
uniform sampler2D solid_texture : filter_nearest, repeat_disable;
uniform vec2 field_origin = vec2(0.0, 180.0);
uniform vec2 field_size = vec2(320.0, 180.0);
uniform vec2 mask_cell_count = vec2(40.0, 23.0);

uniform vec4 heavy_color : source_color = vec4(0.86, 0.5, 0.26, 1.0);
uniform vec4 neutral_color : source_color = vec4(0.42, 0.78, 0.92, 1.0);
uniform vec4 light_color : source_color = vec4(1.0, 0.93, 0.64, 1.0);
uniform vec3 gas_alpha = vec3(0.46, 0.26, 0.2);
uniform vec3 gas_noise_scale = vec3(0.09, 0.17, 0.3);
uniform vec4 lit_tint : source_color = vec4(1.0, 0.9, 0.72, 1.0);
uniform float base_alpha = 0.55;
uniform float light_alpha = 0.9;
uniform float noise_amount = 0.6;

uniform vec4 light0 = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec4 light0_color : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform vec4 light1 = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec4 light1_color : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform vec4 light2 = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec4 light2_color : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform vec4 light3 = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec4 light3_color : source_color = vec4(1.0, 0.8, 0.5, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 4x4 ordered dither in [0, 1).
float bayer4(vec2 p) {
	vec2 q = floor(mod(p, 4.0));
	float x = q.x;
	float y = q.y;
	float v = mod(x, 2.0) * 8.0 + mod(y, 2.0) * 4.0
		+ mod(floor(x * 0.5), 2.0) * 2.0 + mod(floor(y * 0.5), 2.0);
	return v / 16.0;
}

float light_term(vec2 world, vec4 light, vec4 tint, inout vec3 sum) {
	if (light.w <= 0.001) {
		return 0.0;
	}
	float distance = length(world - light.xy);
	float falloff = pow(clamp(1.0 - distance / max(light.z, 1.0), 0.0, 1.0), 1.6) * light.w;
	sum += tint.rgb * falloff;
	return falloff;
}

void fragment() {
	// QuadMesh UVs run bottom-up, the field is authored top-down.
	vec2 quad_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 world = field_origin + quad_uv * field_size;
	vec2 mask_uv = quad_uv * (field_size / (8.0 * mask_cell_count));
	if (texture(solid_texture, mask_uv).r > 0.5) {
		discard;
	}

	vec3 gas = texture(gas_texture, clamp(quad_uv, vec2(0.0), vec2(0.9999))).rgb;
	// Each gas gets its own wisp pattern so the layers interleave instead of
	// averaging into one flat veil.
	vec3 wisp = vec3(
		value_noise(world * gas_noise_scale.x + vec2(TIME * 0.06, -TIME * 0.04)),
		value_noise(world * gas_noise_scale.y - vec2(TIME * 0.11, TIME * 0.03)),
		value_noise(world * gas_noise_scale.z + vec2(TIME * 0.18, -TIME * 0.08))
	);
	gas *= mix(vec3(1.0 - noise_amount), vec3(1.0 + noise_amount), wisp);

	float heavy = clamp(gas.r, 0.0, 1.0);
	float neutral = clamp(gas.g, 0.0, 1.0);
	float light = clamp(gas.b, 0.0, 1.0);
	float total = heavy + neutral + light;
	if (total <= 0.01) {
		discard;
	}
	float opacity = heavy * gas_alpha.x + neutral * gas_alpha.y + light * gas_alpha.z;
	vec3 color = (heavy_color.rgb * heavy + neutral_color.rgb * neutral + light_color.rgb * light) / max(total, 0.001);

	float lit = 0.0;
	vec3 light_sum = vec3(0.0);
	lit += light_term(world, light0, light0_color, light_sum);
	lit += light_term(world, light1, light1_color, light_sum);
	lit += light_term(world, light2, light2_color, light_sum);
	lit += light_term(world, light3, light3_color, light_sum);

	color = mix(color, lit_tint.rgb * color * 1.6, clamp(lit * 0.55, 0.0, 0.8));
	color += light_sum * 0.22;
	float alpha = clamp(opacity * (base_alpha + light_alpha * min(lit, 1.5)), 0.0, 0.92);
	float dither = bayer4(world);
	alpha = floor(alpha * 8.0 + dither) / 8.0;
	if (alpha <= 0.02) {
		discard;
	}
	COLOR = vec4(color, alpha);
}
