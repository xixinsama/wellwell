shader_type canvas_item;
render_mode blend_add, unshaded;

// Bloom pass 4: add the blurred bright pass back over the world.
//
// The blur runs at half resolution, so it is scaled up here with a linear
// sampler, then quantised in ordered-dither steps so the glow lands on the pixel
// grid instead of turning into a smooth modern gradient.

uniform sampler2D source : filter_linear, repeat_disable;
uniform float strength = 0.85;
uniform vec4 tint : source_color = vec4(1.0, 0.94, 0.86, 1.0);
// Ordered dither levels; 0 keeps the glow smooth.
uniform float levels = 6.0;

float bayer4(vec2 p) {
	vec2 q = floor(mod(p, 4.0));
	float inner = mod(3.0 * mod(q.y, 2.0) + 2.0 * mod(q.x, 2.0), 4.0);
	float outer = mod(
		3.0 * floor(mod(q.y, 4.0) * 0.5) + 2.0 * floor(mod(q.x, 4.0) * 0.5),
		4.0
	);
	return (4.0 * inner + outer + 0.5) / 16.0;
}

void fragment() {
	vec3 glow = texture(source, UV).rgb * strength * tint.rgb;
	if (levels > 0.5) {
		// Dither between steps on the design pixel grid.
		vec2 px = floor(UV * vec2(textureSize(source, 0)) * 2.0);
		float level = clamp(dot(glow, vec3(0.3, 0.59, 0.11)), 0.0, 1.0);
		float stepped = floor(level * levels + bayer4(px)) / levels;
		glow *= (stepped / max(level, 0.0001));
	}
	COLOR = vec4(glow, 1.0);
}
