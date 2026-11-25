shader_type canvas_item;
render_mode blend_add, unshaded;

// Warm glow on top of the darkness pass, so the lantern reads as light instead
// of only as "not dark". Same light map as the shade; the alpha is ignored by
// the additive blend and only the colour matters.
//
// The optional relief term reuses the shade's normals and light direction so a
// surface that faces the lantern glows a little harder than one that faces away.
// It is deliberately half strength: the glow is a highlight, not the shading.

uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform vec2 light_pixels = vec2(320.0, 180.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform float glow_gain = 0.45;
// Only the bright part of a light glows: the dim spill that reaches across the
// room must not lift the whole screen.
uniform float glow_floor = 0.22;
uniform float glow_ceil = 0.8;
// Quantise the glow to N steps. 0 keeps it continuous; a low N makes it banded.
uniform float steps = 0.0;
// Same fuzzy rim as the shade pass, so the halo ends in hair instead of a
// circle, while the inside of the light stays clean.
uniform float rim_fuzz = 2.0;
uniform float rim_fuzz_scale = 2.2;

// Relief, handed over by LightField together with the normal buffer: 0 flat,
// 1 derived from the screen, 2 authored.
uniform sampler2D normal_tex : filter_nearest, repeat_disable;
uniform vec2 normal_pixels = vec2(320.0, 180.0);
uniform float normal_mode = 0.0;
uniform float relief_strength = 0.0;
uniform float relief_radius_px = 2.0;
uniform float relief_softness = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec2 screen_pixels = vec2(320.0, 180.0);

const float DERIVED_NORMAL_SCALE = 8.0;

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

float light_lum(vec2 px) {
	return clamp(dot(light_at(px), vec3(0.3, 0.59, 0.11)), 0.0, 1.0);
}

float screen_lum(vec2 uv) {
	return clamp(dot(texture(screen_tex, uv).rgb, vec3(0.3, 0.59, 0.11)), 0.0, 1.0);
}

vec2 screen_gradient(vec2 uv, vec2 step_uv) {
	return vec2(
		screen_lum(uv + vec2(step_uv.x, 0.0)) - screen_lum(uv - vec2(step_uv.x, 0.0)),
		screen_lum(uv + vec2(0.0, step_uv.y)) - screen_lum(uv - vec2(0.0, step_uv.y))
	);
}

// Same band-passed sobel as the shade pass: see light_overlay.gdshader for why
// the raw gradient of the screen would only relight the whole room uniformly.
vec3 derived_normal(vec2 screen_uv) {
	vec2 pixel = 1.0 / max(screen_pixels, vec2(1.0));
	vec2 fine_step = pixel;
	vec2 coarse_step = pixel * max(relief_radius_px, 2.0);
	vec2 detail = screen_gradient(screen_uv, fine_step) - screen_gradient(screen_uv, coarse_step);
	return normalize(vec3(-detail * DERIVED_NORMAL_SCALE, 1.0));
}

float relief_factor(vec2 px, vec2 screen_uv, float own) {
	if (normal_mode < 0.5 || relief_strength <= 0.0) {
		return 0.0;
	}
	vec3 normal = vec3(0.0, 0.0, 1.0);
	if (normal_mode > 1.5) {
		vec3 authored = texture(normal_tex, (px + 0.5) / normal_pixels).rgb * 2.0 - 1.0;
		normal = normalize(authored);
	} else {
		normal = derived_normal(screen_uv);
	}
	float step_px = max(relief_radius_px, 1.0);
	vec2 gradient = vec2(
		light_lum(px + vec2(step_px, 0.0)) - light_lum(px - vec2(step_px, 0.0)),
		light_lum(px + vec2(0.0, step_px)) - light_lum(px - vec2(0.0, step_px))
	);
	float magnitude = length(gradient);
	if (magnitude < 0.002) {
		return 0.0;
	}
	vec2 light_dir = -gradient / magnitude;
	float ndl = dot(normal.xy, -light_dir);
	ndl = sign(ndl) * pow(abs(ndl), 1.0 + clamp(relief_softness, 0.0, 1.0) * 2.0);
	float mask = smoothstep(0.02, 0.35, own);
	return clamp(ndl * relief_strength * mask, -1.0, 1.0);
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
	// Stacked lights add up past 1 in the core; clamp before using them as an
	// additive colour or the lamp blows the whole tile out to white.
	vec3 lit = clamp(light, vec3(0.0), vec3(1.0));
	vec3 glow = glow_color.rgb * lit * glow_gain;
	// Mask by how bright the light is here, so the far spill adds nothing.
	float curve = clamp(dot(lit, vec3(0.3, 0.59, 0.11)), 0.0, 1.0);
	glow *= smoothstep(glow_floor, glow_ceil, curve);
	// Relief is a highlight: half strength, and only on pixels the light reaches.
	float relief = relief_factor(px, SCREEN_UV, curve);
	glow *= clamp(1.0 + relief * 0.5, 0.0, 2.0);
	if (steps > 0.5) {
		glow = floor(glow * steps + 0.5) / steps;
	}
	COLOR = vec4(glow, 1.0);
}
