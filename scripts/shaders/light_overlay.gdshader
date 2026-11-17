shader_type canvas_item;
render_mode blend_mix, unshaded;

// Full-room darkness pass driven by the light map.
//
// The light map is the room-sized viewport LightField renders: additive 2D
// lights over a black canvas, so it already carries the falloff and the shadows
// cast by the terrain occluders. Ambient is added here instead of being baked
// into the map, so every consumer agrees on the same ambient value.
//
// The dither only bites where the shade is mid-way, so fully lit and fully dark
// pixels stay clean and the falloff reads as pixel art instead of a gradient.

uniform sampler2D light_tex : filter_linear, repeat_disable;
// Size of the light map in pixels; the quad covers exactly the same rectangle.
uniform vec2 light_pixels = vec2(320.0, 180.0);
uniform float ambient = 0.55;
uniform vec4 shade_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float dither_strength = 0.4;

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
	vec2 px = floor(UV * light_pixels);
	vec2 uv = (px + 0.5) / light_pixels;
	vec3 light = texture(light_tex, uv).rgb;
	float lit = clamp(dot(light, vec3(0.3, 0.59, 0.11)) + ambient, 0.0, 1.0);

	float dark = 1.0 - lit;
	float band = 1.0 - abs(dark * 2.0 - 1.0);
	dark = mix(dark, step(bayer4(px), dark), dither_strength * band);
	COLOR = vec4(shade_color.rgb, shade_color.a * dark);
}
