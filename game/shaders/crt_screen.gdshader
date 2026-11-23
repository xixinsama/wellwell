shader_type canvas_item;

// Screen-space CRT finish. Drawn on a full-screen ColorRect in the topmost
// canvas layer, so it covers the world, the HUD and the menus alike.
//
// Two looks share this shader, selected by `crt_mode`:
//   0  Scanline   one vertical beam profile per game pixel row, energy-normalised
//   1  Phosphor   one soft elliptical dot per game pixel (wider than tall)
//
// Both keep the same contracts:
//   Brightness: the mask is normalised by its own average transmission, so the
//   mean brightness of the frame does not change and no additive bloom is used.
//   Near-white pixels widen the beam/dot so highlights and UI text stay solid.
//
//   Pixel alignment: every texture tap is snapped to the window pixel grid
//   (`(floor(pixel) + 0.5) / screen_pixels`, as in CRT-Hyllian), and all phases
//   come from the integer-scaled game grid (`grid_origin` + `pixel_scale`), never
//   from the window size.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

// Window size in pixels, the window-space origin of game pixel (0, 0), and the
// integer upscale between one game pixel and one window pixel. CrtOverlay pushes
// these every time the viewport layout changes.
uniform vec2 screen_pixels = vec2(1280.0, 720.0);
uniform vec2 grid_origin = vec2(0.0, 0.0);
uniform float pixel_scale = 4.0;

// 0 = scanline, 1 = phosphor dots. CrtOverlay drives this from the CRT Mode
// setting; the scanline look is kept as a selectable mode.
uniform int crt_mode = 1;

// Scanline tuning (mode 0).
uniform float scanline_strength : hint_range(0.0, 0.8) = 0.12;

// Dot tuning (mode 1). `dot_average` is the mean coverage of `core` at the
// current upscale, computed by CrtOverlay; the dot is an ellipse with a larger
// X radius (dot_aspect > 1 squeezes Y).
uniform float dot_strength : hint_range(0.0, 0.9) = 0.70;
uniform float dot_size : hint_range(0.3, 1.2) = 1.0;
uniform float dot_aspect : hint_range(0.6, 2.0) = 1.15;
uniform float dot_softness : hint_range(0.1, 0.9) = 0.45;
uniform float dot_average : hint_range(0.0, 1.0) = 0.46;

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

	float peak = max(col.r, max(col.g, col.b));
	vec3 mask;
	float transmission;

	if (crt_mode == 0) {
		// Scanline: one cycle per game pixel row, dark at the row boundary and
		// full at the row centre. Bright pixels widen the beam.
		float row = (p.y - grid_origin.y) / scale;
		float phase = fract(row);
		float dark = 1.0 - smoothstep(0.0, 0.5, min(phase, 1.0 - phase));
		float lit = smoothstep(0.45, 0.92, peak);
		float beam = mix(1.0 - scanline_strength * dark, 1.0, lit);
		mask = vec3(beam);
		transmission = max(1.0 - scanline_strength * 0.5 * (1.0 - lit), 0.001);
	} else {
		// Phosphor dot: soft radial profile centred in the game pixel. Squeezing Y
		// makes the X radius larger, i.e. a horizontal ellipse.
		vec2 cell = fract((p - grid_origin) / scale) - vec2(0.5);
		cell.y *= dot_aspect;
		float distance_from_centre = length(cell) / max(0.5 * dot_size, 0.001);
		float core = 1.0 - smoothstep(1.0 - dot_softness, 1.0, distance_from_centre);
		float widen = smoothstep(0.78, 1.0, peak) * 0.85;
		float shape = mix(core, 1.0, widen);
		float average_shape = mix(dot_average, 1.0, widen);
		transmission = max(1.0 - dot_strength * (1.0 - average_shape), 0.001);
		mask = vec3(1.0 - dot_strength * (1.0 - shape));
	}

	// Optional corner falloff, off by default: a vignette lowers the mean
	// brightness, which is the opposite of what this pass is for.
	vec2 edge = SCREEN_UV - vec2(0.5);
	float corner = 1.0 - vignette * dot(edge, edge) * 2.0;
	col = col * mask / transmission * corner * brightness;

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
