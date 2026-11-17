shader_type canvas_item;
render_mode blend_mix;

// Backdrop treatment: a soft plate with a fine heat-haze drift.
//
// The motion is deliberately NOT a twist. Every source scanline slides
// sideways on its own, with a dense wavelength (a few rows per wave), so the
// plate reads as moving air rather than a wobbling picture. Amplitude stays
// under a pixel; the soft blur turns the offsets into shimmer instead of
// jitter.
//
// The blur lives inside fragment() on purpose: TEXTURE and TEXTURE_PIXEL_SIZE
// are fragment-stage builtins and are rejected inside a helper function.

uniform float blur_radius : hint_range(0.0, 6.0) = 1.2;
// Horizontal travel of one scanline, in source pixels.
uniform float sway_amount : hint_range(0.0, 4.0) = 0.75;
// Waves per scanline. Higher = denser; 0.22 is roughly one wave every 4 rows.
uniform float sway_frequency : hint_range(0.02, 1.0) = 0.22;
// Wave cycles per second.
uniform float sway_speed : hint_range(0.0, 3.0) = 0.35;
uniform vec4 tint : source_color = vec4(0.62, 0.9, 1.0, 1.0);
uniform float brightness : hint_range(0.0, 3.0) = 2.5;
uniform float vignette : hint_range(0.0, 1.5) = 0.22;

void fragment() {
	float rows = 1.0 / TEXTURE_PIXEL_SIZE.y;
	float phase = UV.y * rows * sway_frequency * 6.2831853 + TIME * sway_speed * 6.2831853;
	float fine = sin(phase);
	// A second, faster wave keeps the rows from marching in step.
	float detail = sin(phase * 2.31 - TIME * sway_speed * 2.7 * 6.2831853) * 0.55;

	vec2 uv = UV;
	uv.x += (fine + detail) * sway_amount * TEXTURE_PIXEL_SIZE.x;

	// gaussian soften: centre + two rings of eight taps
	vec2 px = TEXTURE_PIXEL_SIZE * max(blur_radius, 0.0001);
	vec4 col = texture(TEXTURE, uv) * 0.24;
	float weight = 0.24;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.7853982;
		vec2 dir = vec2(cos(angle), sin(angle));
		col += texture(TEXTURE, uv + dir * px) * 0.055;
		col += texture(TEXTURE, uv + dir * px * 2.15) * 0.06;
		weight += 0.115;
	}
	col /= weight;

	// corners ease off so the middle of the frame carries the mood
	vec2 centered = UV - vec2(0.5);
	float falloff = clamp(1.0 - vignette * dot(centered, centered) * 2.4, 0.0, 1.0);
	col.rgb *= falloff;
	col.rgb *= tint.rgb * brightness;
	COLOR = vec4(col.rgb, 1.0);
}
