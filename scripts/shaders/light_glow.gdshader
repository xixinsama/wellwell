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

void fragment() {
	vec2 px = floor(UV * light_pixels);
	vec2 uv = (px + 0.5) / light_pixels;
	vec3 light = texture(light_tex, uv).rgb;
	vec3 glow = glow_color.rgb * light * glow_gain;
	if (steps > 0.5) {
		glow = floor(glow * steps + 0.5) / steps;
	}
	COLOR = vec4(glow, 1.0);
}
