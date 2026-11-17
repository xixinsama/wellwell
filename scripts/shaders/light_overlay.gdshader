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
// Bounce: light bleeding a few pixels into the shadow, so a cast shadow is dark
// deep inside and lighter towards its silhouette (the light reflecting off the
// lit surfaces next to it).
uniform float bounce = 0.45;
uniform float bounce_radius = 10.0;
// Fuzzy rim: the lit side is pushed outwards by up to this many pixels, using a
// dense noise offset and a maximum (never a subtraction), so light grows hair
// instead of the darkness eating inwards. The inside of a light is untouched.
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

float light_lum(vec2 px) {
	vec3 light = texture(light_tex, (px + 0.5) / light_pixels).rgb;
	return clamp(dot(light, vec3(0.3, 0.59, 0.11)), 0.0, 1.0);
}

// Light at this pixel, grown outwards by the fuzz: four offset samples taken at
// a noise-driven direction, and only the brightest of them is kept.
float fuzzed_light_lum(vec2 px) {
	float own = light_lum(px);
	if (rim_fuzz <= 0.0) {
		return own;
	}
	vec2 base = px / rim_fuzz_scale;
	for (int index = 0; index < 3; index++) {
		float angle = noise_at(base + float(index) * 37.0) * 6.2831853;
		float reach = (0.55 + 0.45 * noise_at(base * 1.7 + float(index) * 11.0)) * rim_fuzz;
		own = max(own, light_lum(px + vec2(cos(angle), sin(angle)) * reach));
	}
	return own;
}

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
	float own = fuzzed_light_lum(px);
	float lit = own;
	if (bounce > 0.0) {
		// Brightest light within the bounce radius, decaying with distance.
		float bleed = 0.0;
		for (int index = 0; index < 8; index++) {
			float angle = float(index) * 0.7853982;
			vec2 direction = vec2(cos(angle), sin(angle));
			bleed = max(bleed, light_lum(px + direction * bounce_radius) * 0.55);
			bleed = max(bleed, light_lum(px + direction * bounce_radius * 0.5) * 0.8);
		}
		lit = max(lit, bleed * bounce);
	}
	lit = clamp(lit + ambient, 0.0, 1.0);

	float dark = 1.0 - lit;
	float band = 1.0 - abs(dark * 2.0 - 1.0);
	dark = mix(dark, step(bayer4(px), dark), dither_strength * band);
	COLOR = vec4(shade_color.rgb, shade_color.a * dark);
}
