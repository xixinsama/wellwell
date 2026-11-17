shader_type canvas_item;
render_mode unshaded, blend_mix;

// Animated fog-of-war mask.
//
// The CPU only writes one texel block per map cell:
//   .a = fog opacity (0 = revealed, 1 = fogged, in between while it evaporates)
//   .r = reveal flash (1 on the frame the cell opens, then falls to 0)
//   .g = signed distance to the border, encoded around 0.5 (see distance_range)
// Everything else is generated here, so the border is organic instead of
// following the cell grid:
//   1. the distance field (bilinear between cell centres) becomes a continuous
//      border, so the cut can sit anywhere between two cells
//   2. three noise layers push that cut around: coarse lobes (tendrils), fine
//      grain, and a slow low frequency swell (the breathing)
//   3. a 4x4 ordered dither cuts the last pixels of the cut into pixel grain
//
// All of it lives on the GPU: the fog no longer costs a draw_rect per cell per
// frame, and the mask texture is only rewritten when the revealed set changes.
// Pixel coordinates come from UV and are floored, so the noise and the dither
// are anchored to the mask and never crawl while the camera moves.

uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// The mask is bound explicitly rather than read through TEXTURE so helper
// functions could sample it (canvas TEXTURE is only visible inside fragment()).
uniform sampler2D mask_tex : filter_nearest, repeat_disable;
// One mask texel is one world pixel; this is the texture size in pixels.
uniform vec2 mask_pixels = vec2(320.0, 180.0);
// Map cell size in pixels: the distance field is sampled between cell centres.
uniform vec2 cell_pixels = vec2(8.0, 8.0);
// Must match MASK_DISTANCE_PIXELS in fog_of_war.gd. The distance channel is
// 0.5 + distance / (2 * distance_range), so this is how far it reaches in px.
uniform float distance_range = 64.0;

// --- edge shape -----------------------------------------------------------
// How far the noise may push the border out or in, in pixels.
uniform float tendril_pixels = 7.0;
// Half width of the anti-aliased cut in pixels (0 = hard pixel edge).
uniform float edge_softness = 1.6;
uniform float noise_scale = 13.0;
uniform float noise_grain = 3.2;
uniform float noise_speed = 0.55;
uniform float noise_warp = 0.65;

// --- breathing ------------------------------------------------------------
// A very low frequency swell added to the cut, so the whole shadow slowly
// inhales and exhales instead of only shimmering along its border.
uniform float breath_pixels = 3.0;
uniform float breath_scale = 46.0;
uniform float breath_speed = 0.16;

// --- pixel grain ----------------------------------------------------------
uniform float dither_strength = 0.6;
uniform float dither_scale = 1.0;

// --- reveal ---------------------------------------------------------------
uniform float flash_strength = 0.45;
uniform bool animate = true;
// --- light ----------------------------------------------------------------
// The room light map (see LightField). Light does not reveal anything: it only
// pushes the wobbling cut back, so a lit border recedes while the dark cells
// behind it stay black.
uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform vec2 light_pixels = vec2(320.0, 180.0);
uniform float light_push_px = 10.0;
uniform float light_gain = 1.0;
// --- focus ----------------------------------------------------------------
// focus_room spotlight. It is a shader term and not a mask channel on purpose:
// the bubble is centred on the hero body and follows it every frame, so baking
// it into the mask would cost one fill_rect per cell per frame.
uniform vec2 focus_center_px = vec2(-99999.0, -99999.0);
// x, y, w, h of the authored zone in mask pixels; the zone itself stays lit.
uniform vec4 focus_rect_px = vec4(-99999.0, -99999.0, 0.0, 0.0);
uniform float focus_strength = 0.0;
uniform float focus_alpha = 0.0;
uniform float focus_radius_px = 34.0;
uniform float focus_falloff_px = 34.0;
// Test hook: 1 draws the sign of the distance field, 2 draws the two bilinear
// fields as colour and 3 draws the final shape, so captures can be measured.
uniform float debug_view = 0.0;

// Distance from a pixel to a rectangle, zero inside it.
float rect_outside(vec2 p, vec4 rect) {
	vec2 half_size = rect.zw * 0.5;
	vec2 delta = abs(p - (rect.xy + half_size)) - half_size;
	return length(max(delta, vec2(0.0)));
}

// The spotlight: the lit stage is the authored zone plus a bubble around the
// hero, and everything else fades to focus_alpha over focus_falloff_px. The
// bubble starts wide and closes onto the hero while the fade runs in, which is
// the "the room closes in around you" beat. Nothing here can open a fogged
// cell: the shader only adds darkness, and the final alpha is a max().
float focus_at(vec2 px) {
	if (focus_strength <= 0.001 || focus_alpha <= 0.001 || focus_rect_px.z <= 0.0) {
		return 0.0;
	}
	float strength = clamp(focus_strength, 0.0, 1.0);
	float radius = mix(focus_radius_px * 2.6, focus_radius_px, strength);
	float lit_distance = min(
		rect_outside(px, focus_rect_px),
		max(length(px - focus_center_px) - radius, 0.0)
	);
	float ramp = smoothstep(0.0, max(focus_falloff_px, 1.0), lit_distance);
	return ramp * strength * focus_alpha;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Three octaves, normalised back to 0..1.
float fbm3(vec2 p) {
	float value = 0.5 * value_noise(p);
	p = p * 2.03 + vec2(17.1, 9.2);
	value += 0.25 * value_noise(p);
	p = p * 2.01 + vec2(31.5, 45.5);
	value += 0.125 * value_noise(p);
	return value / 0.875;
}

// 4x4 ordered dither built as M4 = 4 * M2(inner) + M2(outer), which avoids an
// array lookup and keeps the pattern exact.
float bayer4(vec2 p) {
	vec2 c = floor(mod(p, 4.0));
	float inner = mod(3.0 * mod(c.y, 2.0) + 2.0 * mod(c.x, 2.0), 4.0);
	float outer = mod(
		3.0 * floor(mod(c.y, 4.0) * 0.5) + 2.0 * floor(mod(c.x, 4.0) * 0.5),
		4.0
	);
	return (4.0 * inner + outer + 0.5) / 16.0;
}

// Bilinear read of the per-cell distance field, interpolated between cell
// centres so the border is continuous inside a cell instead of a staircase.
float cell_distance(vec2 cell_pos) {
	vec2 base = floor(cell_pos);
	vec2 f = cell_pos - base;
	vec2 corner = (base + 0.5) * cell_pixels / mask_pixels;
	vec2 step_uv = cell_pixels / mask_pixels;
	float d00 = texture(mask_tex, corner).g;
	float d10 = texture(mask_tex, corner + vec2(step_uv.x, 0.0)).g;
	float d01 = texture(mask_tex, corner + vec2(0.0, step_uv.y)).g;
	float d11 = texture(mask_tex, corner + step_uv).g;
	return mix(mix(d00, d10, f.x), mix(d01, d11, f.x), f.y);
}

void fragment() {
	vec2 px = floor(UV * mask_pixels);
	float focus_amount = focus_at(px);
	vec4 centre = texture(mask_tex, (px + 0.5) / mask_pixels);

	// Cell-space position of this fragment, measured so integer values land on
	// cell centres (the distance field is stored per cell centre).
	vec2 cell_pos = (px + 0.5) / cell_pixels - 0.5;
	// Positive inside the fog, negative inside the revealed area.
	float distance_px = (cell_distance(cell_pos) - 0.5) * 2.0 * distance_range;

	if (debug_view < 0.5 && centre.r <= 0.0 && distance_px < -distance_range * 0.98
			&& focus_amount <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		float t = animate ? TIME : 0.0;
		vec2 drift = vec2(t * 0.31, t * 0.23) * noise_speed;

		// Tendrils: domain-warped fbm so the border grows tongues instead of
		// just getting a noisy offset.
		vec2 lobe_uv = px / noise_scale;
		vec2 warp = vec2(
			value_noise(lobe_uv * 0.6 + drift * 0.7),
			value_noise(lobe_uv * 0.6 - drift * 0.9 + vec2(41.7, 12.3))
		) - 0.5;
		float lobes = fbm3(lobe_uv + warp * noise_warp + drift);
		float grain = value_noise(px / noise_grain + drift * 2.1) - 0.5;
		float swell = value_noise(
			px / breath_scale + vec2(t * breath_speed, -t * breath_speed * 0.7)
		) - 0.5;

		float wobble = (lobes - 0.5) * 2.0 * tendril_pixels;
		wobble += grain * 0.6 * tendril_pixels;
		wobble += swell * 2.0 * breath_pixels;
		// Light pushes the cut outwards, so the shadow recedes where it is lit.
		// The mask is untouched: this moves the border, it never opens a cell
		// that is still unexplored.
		if (light_push_px != 0.0) {
			vec3 light_sample = texture(light_tex, (px + 0.5) / light_pixels).rgb;
			float light = clamp(
				dot(light_sample, vec3(0.3, 0.59, 0.11)) * light_gain, 0.0, 1.0
			);
			wobble += light * light_push_px;
		}

		float soft = max(edge_softness, 0.001);
		float shape = smoothstep(-soft, soft, distance_px - wobble);

		// A cell that is fogged, fading or dimmed keeps exactly its own
		// opacity, so the reveal wave and the focus spotlight stay truthful.
		// Only a fully revealed cell can still be covered by a tongue, and that
		// one is solid at the cut and thins out towards its tip.
		//
		// The tongue share is scaled by (1 - opacity) instead of switching at a
		// threshold: a hard step made the whole border pop the moment a cell
		// crossed the threshold, which read as a flicker at the start and the end
		// of every authored zone fade.
		float past = max(0.0, wobble - distance_px);
		float tongue = 1.0 - smoothstep(0.0, max(tendril_pixels, 0.5), past);
		float value = max(centre.a, tongue * (1.0 - centre.a));

		// Ordered dither only where the cut is in flight, so the fog interior
		// stays clean and the border breaks into chunky pixel grain.
		float border = 1.0 - abs(shape * 2.0 - 1.0);
		float dither = step(bayer4(px / dither_scale), shape);
		shape = mix(shape, dither, dither_strength * border);

		float fog_amount = fog_color.a * shape * value;
		float flash_amount = centre.r * flash_strength * flash_color.a;
		if (flash_amount > 0.0) {
			// Trace a 1px outline inside the revealed cell instead of a blob.
			vec2 in_cell = fract(px / cell_pixels) * cell_pixels;
			vec2 edge_dist = min(in_cell, cell_pixels - in_cell);
			flash_amount *= 1.0 - step(1.0, min(edge_dist.x, edge_dist.y));
		}
		float out_alpha = max(max(fog_amount, flash_amount), focus_amount);
		// The dip only wins when it is the strongest term; a pixel that holds
		// nothing but the focus spotlight must stay `fog_color`, otherwise a
		// step(0, 0) would paint it with the white flash colour.
		vec3 rgb = fog_color.rgb;
		if (flash_amount > 0.0 && flash_amount >= max(fog_amount, focus_amount)) {
			rgb = flash_color.rgb;
		}
		if (debug_view > 0.5 && debug_view < 1.5) {
			COLOR = vec4(step(0.0, distance_px), step(0.0, -distance_px), 0.0, 1.0);
		} else if (debug_view > 1.5 && debug_view < 2.5) {
			COLOR = vec4(value, shape, centre.a, 1.0);
		} else if (debug_view > 2.5) {
			COLOR = vec4(shape, value, 0.0, 1.0);
		} else {
			COLOR = vec4(rgb, out_alpha);
		}
	}
}
