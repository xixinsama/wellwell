shader_type canvas_item;
render_mode unshaded;

// Bloom pass 2: the other axis of the gaussian blur.
//
// The bright pass already applied the same kernel horizontally, so together the
// two passes are one separable gaussian. `direction` is the axis in texels.

uniform sampler2D source : filter_linear, repeat_disable;
uniform vec2 texel_size = vec2(1.0, 1.0);
uniform vec2 direction = vec2(0.0, 1.0);
uniform float radius = 6.0;

const float WEIGHTS[5] = {0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216};

void fragment() {
	vec2 step_uv = texel_size * direction * max(radius, 0.5) * 0.5;
	vec3 sum = texture(source, UV).rgb * WEIGHTS[0];
	for (int index = 1; index < 5; index++) {
		vec2 offset = step_uv * float(index);
		sum += texture(source, UV + offset).rgb * WEIGHTS[index];
		sum += texture(source, UV - offset).rgb * WEIGHTS[index];
	}
	COLOR = vec4(sum, 1.0);
}
