shader_type canvas_item;
render_mode blend_mix;

// One falling water stream: a small continuous water body, in the same palette
// as the pools. The WaterField spawns a series of these when water spills over a
// lip, so the fall is simulated water (mass) rather than a texture or particles.

uniform vec4 shallow_color : source_color = vec4(0.26, 0.66, 0.94, 0.62);
uniform vec4 deep_color : source_color = vec4(0.05, 0.18, 0.42, 0.9);
uniform vec4 crest_color : source_color = vec4(0.85, 0.97, 1.0, 0.95);
uniform vec4 foam_color : source_color = vec4(0.96, 1.0, 1.0, 0.9);

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

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	float edge = smoothstep(0.0, 0.32, uv.x) * (1.0 - smoothstep(0.68, 1.0, uv.x));
	float streak = value_noise(vec2(uv.x * 5.0, uv.y * 4.0 - TIME * 7.0));
	vec3 color = mix(shallow_color.rgb, crest_color.rgb, 0.3 + streak * 0.4);
	color = mix(color, foam_color.rgb, smoothstep(0.7, 1.0, uv.y) * 0.45);
	float alpha = mix(shallow_color.a, deep_color.a, 0.35) * 0.95;
	alpha *= edge;
	COLOR = vec4(color, clamp(alpha, 0.0, 1.0));
}
