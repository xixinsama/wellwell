shader_type canvas_item;
render_mode unshaded;

// Bloom pass 1: threshold the bright pixels, then blur along one axis.
//
// Thresholding each tap before it is weighted is the same as thresholding once
// and then blurring (the blur is linear), so this merges the bright pass and the
// horizontal pass: one read of the world texture instead of two.
//
// The source is the world viewport as it was rendered last frame (a viewport
// texture cannot be read while it is being drawn), which is invisible for a glow.
// The result is written at half resolution: the blur does not need the full grid.

uniform sampler2D source : filter_linear, repeat_disable;
uniform vec2 texel_size = vec2(1.0, 1.0);
uniform vec2 direction = vec2(1.0, 0.0);
uniform float radius = 6.0;
uniform float threshold = 0.62;
// Soft knee, so a pixel just over the threshold does not pop.
uniform float knee = 0.12;
uniform float intensity = 1.0;

const float WEIGHTS[5] = {0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216};

vec3 bright(vec2 uv) {
	vec3 colour = texture(source, uv).rgb;
	float luminance = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	float weight = smoothstep(threshold, threshold + max(knee, 0.001), luminance);
	return colour * weight * intensity;
}

void fragment() {
	vec2 step_uv = texel_size * direction * max(radius, 0.5) * 0.5;
	vec3 sum = bright(UV) * WEIGHTS[0];
	for (int index = 1; index < 5; index++) {
		vec2 offset = step_uv * float(index);
		sum += bright(UV + offset) * WEIGHTS[index];
		sum += bright(UV - offset) * WEIGHTS[index];
	}
	COLOR = vec4(sum, 1.0);
}
