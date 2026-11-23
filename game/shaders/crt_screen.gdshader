shader_type canvas_item;

// Screen-space CRT finish. Drawn on a full-screen ColorRect in the topmost
// canvas layer, so it covers the world, the HUD and the menus alike.
//
// This is the "little bulbs" look: every game pixel becomes one elliptical
// phosphor dot, with a dark grid between the dots (the beam profile falls off in
// both axes), and no screen curvature.
//
// Brightness contract: the dot mask is normalised by its own average
// transmission, computed by CrtOverlay for the current upscale and passed in as
// `dot_average`. That is the energy normalisation CRT shader packs use; the mean
// brightness of the frame stays the same instead of gaining an additive bloom.
// Near-white pixels widen their dot (like a bright CRT beam) so highlights and UI
// text keep their brightness instead of turning into a sparse dot grid.
//
// Pixel alignment contract:
//   - every texture tap is snapped to the window pixel grid
//     (`(floor(pixel) + 0.5) / screen_pixels`, the same trick as CRT-Hyllian);
//   - the dot phase is measured from the integer-scaled game pixel grid
//     (`grid_origin` + `pixel_scale`), never from the window size, so the pattern
//     cannot drift or shimmer when the window is resized.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

// Window size in pixels, the window-space origin of game pixel (0, 0), and the
// integer upscale between one game pixel and one window pixel. CrtOverlay pushes
// these every time the viewport layout changes.
uniform vec2 screen_pixels = vec2(1280.0, 720.0);
uniform vec2 grid_origin = vec2(0.0, 0.0);
uniform float pixel_scale = 4.0;

// Dot lattice. `dot_average` is kept in sync by CrtOverlay
// (`1/n^2 * sum(profile)` over the same n x n window-pixel samples the shader
// evaluates), so changing size/aspect in the inspector stays brightness-neutral.
uniform float dot_strength : hint_range(0.0, 0.9) = 0.75;
uniform float dot_size : hint_range(0.3, 1.2) = 0.82;
uniform float dot_aspect : hint_range(0.6, 1.4) = 0.9;
uniform float dot_average : hint_range(0.0, 1.0) = 0.24;

uniform float aberration : hint_range(0.0, 2.0) = 0.35;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform float brightness : hint_range(0.9, 1.1) = 1.0;

void fragment() {
	vec2 p = SCREEN_UV * screen_pixels;
	vec2 uv = (floor(p) + vec2(0.5)) / screen_pixels;
	float scale = max(pixel_scale, 1.0);

	// Colour split uses whole window pixels, so it never samples between texels.
	float shift_pixels = aberration > 0.001 ? max(1.0, floor(aberration * scale + 0.5)) : 0.0;
	vec2 shift = vec2(shift_pixels / screen_pixels.x, 0.0);

	vec3 col;
	col.r = texture(screen_texture, uv + shift).r;
	col.g = texture(screen_texture, uv).g;
	col.b = texture(screen_texture, uv - shift).b;

	// One ellipse per game pixel. `cell` is -1..1 inside the current pixel, so the
	// profile is independent of the window size; only the integer upscale decides
	// how many window pixels sample it.
	vec2 cell = fract((p - grid_origin) / scale) * 2.0 - 1.0;
	cell.y *= dot_aspect;
	float radius2 = dot(cell, cell) / max(dot_size * dot_size, 0.0001);
	float profile = pow(max(0.0, 1.0 - radius2), 2.0);

	// A bright pixel widens its dot until it nearly fills the cell, which keeps
	// highlights and UI text bright and legible. Mid-tones keep the full lattice.
	float peak = max(col.r, max(col.g, col.b));
	float widen = smoothstep(0.78, 1.0, peak) * 0.85;
	float shape = mix(profile, 1.0, widen);

	// Energy normalisation. `dot_average` is the mean of `profile` over the cell at
	// this upscale; the widened average is a linear mix of that and 1.
	float average_shape = mix(dot_average, 1.0, widen);
	float transmission = max(1.0 - dot_strength * (1.0 - average_shape), 0.001);
	vec3 mask = vec3(1.0 - dot_strength * (1.0 - shape));

	// Optional corner falloff, off by default: a vignette always lowers the mean
	// brightness, which is the opposite of what this pass is for.
	vec2 edge = SCREEN_UV - vec2(0.5);
	float corner = 1.0 - vignette * dot(edge, edge) * 2.0;
	col = col * mask / transmission * corner * brightness;

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
