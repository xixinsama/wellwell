shader_type canvas_item;
render_mode blend_add, unshaded;

// Warm glow on top of the darkness pass, so the lantern reads as light instead
// of only as "not dark". Same light map as the shade; the alpha is ignored by
// the additive blend and only the colour matters.

uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform vec2 light_pixels = vec2(320.0, 180.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform float glow_gain = 0.45;
// Quantise the glow to N steps. 0 keeps it continuous; a low N makes it banded.
uniform float steps = 0.0;
// Same fuzzy rim as the shade pass, so the halo ends in hair instead of a
// circle, while the inside of the light stays clean.
uniform float rim_fuzz = 2.0;
uniform float rim_fuzz_scale = 2.2;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise_at(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 light_at(vec2 px) {
	return texture(light_tex, (px + 0.5) / light_pixels).rgb;
}

void fragment() {
	vec2 px = floor(UV * light_pixels);
	vec3 light = light_at(px);
	if (rim_fuzz > 0.0) {
		vec2 base = px / rim_fuzz_scale;
		for (int index = 0; index < 3; index++) {
			float angle = noise_at(base + float(index) * 37.0) * 6.2831853;
			float reach = (0.55 + 0.45 * noise_at(base * 1.7 + float(index) * 11.0)) * rim_fuzz;
			light = max(light, light_at(px + vec2(cos(angle), sin(angle)) * reach));
		}
	}
	vec3 glow = glow_color.rgb * light * glow_gain;
	if (steps > 0.5) {
		glow = floor(glow * steps + 0.5) / steps;
	}
	COLOR = vec4(glow, 1.0);
}
