shader_type canvas_item;

// Screen-space CRT finish. Drawn on a full-screen ColorRect in the topmost
// canvas layer, so it covers the world, the HUD and the menus alike.
//
// Brightness contract: the pass is energy-neutral. The scanline beam is measured,
// its average transmission is computed per pixel, and the result is divided by it.
// That is the "energy normalisation" the CRT shader scene uses; it keeps the mean
// brightness identical to the source instead of adding a lift or an additive bloom
// on top (which is what made lit areas glow).
//
// Bright pixels widen the beam (Hyllian's CRT shader does the same with its beam
// min/max width), so highlights stay neutral white and are never dimmed or tinted.
//
// Pixel alignment contract:
//   - every texture tap is snapped to the window pixel grid
//     (`(floor(pixel) + 0.5) / screen_pixels`, the same trick as CRT-Hyllian);
//   - the beam and mask phases are measured from the integer-scaled game pixel
//     grid (`grid_origin` + `pixel_scale`), never from the window size, so the
//     pattern cannot drift or shimmer when the window is resized.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

// Window size in pixels, the window-space origin of game pixel (0, 0), and the
// integer upscale between one game pixel and one window pixel. The CrtOverlay
// script pushes these three every time the viewport layout changes.
uniform vec2 screen_pixels = vec2(1280.0, 720.0);
uniform vec2 grid_origin = vec2(0.0, 0.0);
uniform float pixel_scale = 4.0;

uniform float scanline_strength : hint_range(0.0, 0.8) = 0.12;
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

	// Beam: one cycle per game pixel row, dark at the row boundary and full at the
	// row centre. The phase starts at the game grid origin, so it is locked to the
	// pixel grid at any window size and integer scale.
	float row = (p.y - grid_origin.y) / scale;
	float phase = fract(row);
	float dark = 1.0 - smoothstep(0.0, 0.5, min(phase, 1.0 - phase));
	float peak = max(col.r, max(col.g, col.b));
	float lit = smoothstep(0.45, 0.92, peak);
	float beam = mix(1.0 - scanline_strength * dark, 1.0, lit);

	// Average transmission of the beam: half of one cycle is shaded. Dividing by
	// it restores the mean brightness; only near-white pixels can clip, and those
	// are exactly the pixels the beam already left alone.
	float beam_average = 1.0 - scanline_strength * 0.5 * (1.0 - lit);
	float transmission = max(beam_average, 0.001);
	vec3 shaded = col * beam;

	// Optional corner falloff, off by default: a vignette always lowers the mean
	// brightness, which is the opposite of what this pass is for.
	vec2 edge = SCREEN_UV - vec2(0.5);
	float corner = 1.0 - vignette * dot(edge, edge) * 2.0;
	col = shaded / transmission * corner * brightness;

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
