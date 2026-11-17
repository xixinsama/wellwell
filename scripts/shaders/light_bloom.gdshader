shader_type canvas_item;
render_mode blend_add, unshaded;

// Pixel bloom over the light map.
//
// A world-space pass rather than a screen-space one: the halo is anchored to the
// sprite pixels, so it does not swim under the camera and it stays inside the
// 320x180 grid. The map is gathered with a small box, thresholded so only bright
// cores bloom, then quantised through a 4x4 ordered dither so the falloff is made
// of hard pixels instead of a smooth gradient.
//
// Additive with alpha 1, so a black result adds nothing.

uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform vec2 light_pixels = vec2(320.0, 180.0);
uniform vec4 bloom_color : source_color = vec4(1.0, 0.8, 0.55, 1.0);
uniform float strength = 0.55;
// Radius of the gather in pixels; this is how far the halo reaches.
uniform float radius = 7.0;
// Only light above this blooms, so a dim room does not glow everywhere.
uniform float threshold = 0.45;
// Ordered dither levels for the halo; higher is smoother, 0 disables it.
uniform float levels = 5.0;

float bayer4(vec2 p) {
	vec2 q = floor(mod(p, 4.0));
	float inner = mod(3.0 * mod(q.y, 2.0) + 2.0 * mod(q.x, 2.0), 4.0);
	float outer = mod(
		3.0 * floor(mod(q.y, 4.0) * 0.5) + 2.0 * floor(mod(q.x, 4.0) * 0.5),
		4.0
	);
	return (4.0 * inner + outer + 0.5) / 16.0;
}

float light_at(vec2 px) {
	vec2 uv = (px + 0.5) / light_pixels;
	vec3 light = texture(light_tex, uv).rgb;
	return clamp(dot(light, vec3(0.3, 0.59, 0.11)), 0.0, 1.0);
}

void fragment() {
	vec2 px = floor(UV * light_pixels);
	// Two rings of eight taps: a cheap, readable gather at pixel resolution.
	float sum = 0.0;
	for (int index = 0; index < 8; index++) {
		float angle = float(index) * 0.7853982;
		vec2 direction = vec2(cos(angle), sin(angle));
		sum += light_at(px + direction * radius);
		sum += light_at(px + direction * radius * 0.5) * 0.5;
	}
	float gathered = sum / 12.0;
	float bloom = smoothstep(threshold, 1.0, gathered);
	if (bloom <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		float value = bloom * strength;
		if (levels > 0.5) {
			value = floor(value * levels + bayer4(px)) / levels;
		}
		COLOR = vec4(bloom_color.rgb * value, 1.0);
	}
}
