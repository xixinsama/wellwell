shader_type canvas_item;

// Screen-space CRT finish. Drawn on a full-screen ColorRect in the topmost
// canvas layer, so it covers the world, the HUD and the menus alike.
//
// The rule that shapes this shader: bright pixels keep their brightness.
// Scanlines, the slot mask and the corner falloff are multiplied only into
// pixels that are not already bright, and the phosphor glow is added on top, so
// highlights stay white instead of dimming with the rest of the picture.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
// Size of the game picture before the integer upscale, used to keep the
// scanline pitch, the mask and the colour split at pixel-art scale.
uniform vec2 source_size = vec2(322.0, 182.0);
uniform float scanline_rows = 180.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.2;
uniform float mask_strength : hint_range(0.0, 0.5) = 0.1;
uniform float aberration : hint_range(0.0, 3.0) = 0.35;
uniform float bloom_strength : hint_range(0.0, 2.0) = 0.55;
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.6;
uniform float vignette : hint_range(0.0, 1.0) = 0.25;
uniform float lift : hint_range(0.0, 0.2) = 0.015;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / max(source_size, vec2(1.0));
	float shift = aberration * px.x;

	// slight colour split towards the edges only
	vec2 edge = uv - vec2(0.5);
	shift *= 0.35 + length(edge) * 1.4;

	vec3 col;
	col.r = texture(screen_texture, uv + vec2(shift, 0.0)).r;
	col.g = texture(screen_texture, uv).g;
	col.b = texture(screen_texture, uv - vec2(shift, 0.0)).b;

	// phosphor glow: bright neighbours bleed into this pixel
	vec3 glow = texture(screen_texture, uv + vec2(px.x * 1.2, 0.0)).rgb;
	glow += texture(screen_texture, uv - vec2(px.x * 1.2, 0.0)).rgb;
	glow += texture(screen_texture, uv + vec2(0.0, px.y * 1.2)).rgb;
	glow += texture(screen_texture, uv - vec2(0.0, px.y * 1.2)).rgb;
	glow *= 0.25;
	glow = max(glow - vec3(bloom_threshold), vec3(0.0)) / max(1.0 - bloom_threshold, 0.001);

	// scanlines + slot mask
	float row = fract(uv.y * scanline_rows);
	float scan = 0.5 + 0.5 * cos(row * 6.2831853);
	float slot = 0.5 + 0.5 * cos(uv.x * source_size.x * 6.2831853);
	float shade = mix(1.0, scan, scanline_strength) * mix(1.0, 0.6 + 0.4 * slot, mask_strength);

	// corner falloff
	float corner = 1.0 - vignette * dot(edge, edge) * 2.0;
	shade *= corner;

	// bright pixels ignore the shade and only gain glow
	float lum = max(col.r, max(col.g, col.b));
	float keep = smoothstep(0.45, 0.95, lum);

	col = col * mix(shade, 1.0, keep);
	col += glow * bloom_strength * (0.35 + 0.65 * keep);
	col += vec3(lift); // keeps the tube from crushing to pure black
	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
