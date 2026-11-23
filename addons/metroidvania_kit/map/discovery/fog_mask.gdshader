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
// Half width of the anti-aliased cut in pixels (0 = hard pixel edge).
uniform float edge_softness = 1.6;
uniform float noise_scale = 13.0;
uniform float noise_grain = 3.2;
uniform float noise_speed = 0.55;
uniform float noise_warp = 0.65;

// --- edge placement -------------------------------------------------------
// Where the animated border sits relative to the cell edge, in pixels, and how far
// it may swing from there:
//
//   offset = edge_center_px + spatial + temporal, clamped to
//            edge_center_px +- tendril_pixels
//
// Positive = the border retreats *into* the fog, which reveals more of the room
// (that is why the centre is negative: the picture is brighter than the mask's
// cells). Negative = the fog spills out over the revealed side. With the shipped
// -2 px centre and 4 px swing the edge runs from -6 px (thinnest) to +2 px
// (thickest).
//
// Every point of the border comes out of the same continuous band, so a retreat
// can never create the detached patches the old tongue term did - that bug needed
// the fringe to be grown *outwards* from an independent per-cell opacity, not a
// cut that moves.
//
// This replaced a sum of five one-signed terms (base creep + grain + breath +
// surge): that could only ever grow the fog, the depth was something you had to
// add up in your head, and there was no way to ask for "a bit brighter".
uniform float edge_center_px = -2.0;
uniform float tendril_pixels = 4.0;
// Share of the swing the coarse lobes take; the rest is left for the temporal
// terms so the breathing can actually reach the ends of the range.
uniform float lobe_depth = 0.75;

// --- breathing / surge ----------------------------------------------------
// The two temporal terms move the border inside that range; they are what makes a
// standing shadow read as alive instead of as a hole cut into the picture. Both
// are signed (they can thin or thicken the fog), and both are in pixels.
//
// `breath_*` is the slow whole-silhouette inhale: a sine whose phase is offset by
// a low-frequency noise field, so the room does not pulse in unison.
uniform float breath_pixels = 1.2;
uniform float breath_scale = 46.0;
uniform float breath_speed = 0.16;
// `surge_*` is the finer wave that *travels along* the border, which is the "surge"
// in the report: a swell that runs along the edge reads as movement, a swell that
// only changes in place reads as a pulse.
uniform float surge_pixels = 1.8;
uniform float surge_scale = 15.0;
uniform float surge_speed = 0.5;

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
uniform float light_push_px = 3.0;
uniform float light_gain = 1.0;
// --- hero recess ----------------------------------------------------------
// The fog gives way around the hero on *every* side, not only where the lantern
// happens to light something. The light map alone could only ever do the floor:
// walls and ceilings are occluded, so their border never moved (measured: the
// light push changed rows 168..173 and the top band, and nothing along a wall).
// This term is radial and bounded, so the border can never slide more than a few
// pixels, which is what keeps the recess reading as "the mist leans away" instead
// of "a whole row of fog vanished".
uniform vec2 hero_center_px = vec2(-99999.0, -99999.0);
uniform float hero_push_px = 5.0;
uniform float hero_push_radius_px = 44.0;
// Hard ceiling on how far the border may be pushed away in one frame (recession),
// shared by the hero and the light terms. The fringe on the other side is bounded
// by tendril_pixels instead.
uniform float max_push_px = 7.0;
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

// Bilinear read of one cell channel, interpolated between cell centres so the
// value is continuous inside a cell instead of a staircase. The mask stores one
// value per cell, so anything read per pixel with `filter_nearest` would paint
// every cell as a hard 8 px square.
vec4 cell_sample(vec2 cell_pos) {
	vec2 base = floor(cell_pos);
	vec2 f = cell_pos - base;
	vec2 corner = (base + 0.5) * cell_pixels / mask_pixels;
	vec2 step_uv = cell_pixels / mask_pixels;
	vec4 a00 = texture(mask_tex, corner);
	vec4 a10 = texture(mask_tex, corner + vec2(step_uv.x, 0.0));
	vec4 a01 = texture(mask_tex, corner + vec2(0.0, step_uv.y));
	vec4 a11 = texture(mask_tex, corner + step_uv);
	return mix(mix(a00, a10, f.x), mix(a01, a11, f.x), f.y);
}

void fragment() {
	vec2 px = floor(UV * mask_pixels);
	float focus_amount = focus_at(px);
	vec4 centre = texture(mask_tex, (px + 0.5) / mask_pixels);

	// Cell-space position of this fragment, measured so integer values land on
	// cell centres (the fields are stored per cell centre).
	vec2 cell_pos = (px + 0.5) / cell_pixels - 0.5;
	// Both fields are read bilinearly between cell centres: the distance so the
	// cut can sit anywhere, the opacity so a cell that is still fading is a soft
	// patch instead of a hard 8 px square.
	vec4 cell = cell_sample(cell_pos);
	// Positive inside the fog, negative inside the revealed area.
	float distance_px = (cell.g - 0.5) * 2.0 * distance_range;
	float body = cell.a;

	if (debug_view < 0.5 && centre.r <= 0.0 && distance_px < -distance_range * 0.98
			&& focus_amount <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		float t = animate ? TIME : 0.0;
		vec2 drift = vec2(t * 0.31, t * 0.23) * noise_speed;

		// Tendrils: domain-warped fbm gives the border its shape. The shape only
		// decides *where in the range* the edge sits (see `edge_offset` below); it is
		// not an independent depth any more.
		vec2 lobe_uv = px / noise_scale;
		vec2 warp = vec2(
			value_noise(lobe_uv * 0.6 + drift * 0.7),
			value_noise(lobe_uv * 0.6 - drift * 0.9 + vec2(41.7, 12.3))
		) - 0.5;
		float lobes = fbm3(lobe_uv + warp * noise_warp + drift);
		float grain = value_noise(px / noise_grain + drift * 2.1) - 0.5;

		// Slow inhale: a sine, but with the phase offset by a low frequency field so
		// one wall breathes a beat behind the other instead of the room pulsing as
		// a single block.
		float breath_phase = value_noise(px / max(breath_scale, 1.0)) * TAU;
		float breath01 = 0.5 + 0.5 * sin(t * breath_speed * TAU + breath_phase);
		// The surge runs *along* the border: the same noise field translated over
		// time, at a wavelength short enough to read as a swell travelling along the
		// edge and slow enough not to look like static. Two octaves, because a
		// single 15 px lobe leaves long flat stretches where the border sits still
		// for a second and the breathing reads as a stutter.
		float surge_coarse = value_noise(
			px / max(surge_scale, 1.0) + vec2(t * surge_speed, -t * surge_speed * 0.55)
		);
		float surge_fine = value_noise(
			px / max(surge_scale * 0.55, 1.0) + vec2(-t * surge_speed * 1.7, t * surge_speed * 1.1) + vec2(19.3, 7.1)
		);
		float surge01 = (surge_coarse + 0.45 * surge_fine) / 1.45;

		// Where the fog's edge sits, in pixels: the shape fills the swing, the inhale
		// and the surge move it inside that range, and the total is clamped to
		// `edge_center_px +- tendril_pixels` so the picture can never be dimmer than
		// the thickest setting or brighter than the thinnest one.
		// Positive = the fog spills out over the revealed side.
		float spatial = (clamp(lobes, 0.0, 1.0) - 0.5) * 2.0 * (tendril_pixels * lobe_depth);
		spatial += max(grain, 0.0) * 0.2 * tendril_pixels;
		float temporal = (breath01 - 0.5) * 2.0 * breath_pixels
			+ (surge01 - 0.5) * 2.0 * surge_pixels;
		float edge_offset = clamp(
			edge_center_px + spatial + temporal,
			edge_center_px - tendril_pixels,
			edge_center_px + tendril_pixels
		);

		// Thin-feature guard. A retreat may not eat *through* a thin strip of fog: a
		// 12 px band retreating 6 px from its inner edge leaves a sliver, and a ring of
		// such bands comes apart into separate patches (measured on test_fog_start:
		// 2 large blobs at a -2 px centre, 9 at -6 px). The gradient of the distance
		// field points into the fog, so two probes at 2x and 3x the retreat say whether
		// the fog is thick enough to survive it; where it is not, the retreat is
		// scaled away and the band stays whole. Only the inward half needs this.
		if (edge_offset < 0.0) {
			vec2 gradient = vec2(
				cell_sample(cell_pos + vec2(1.0, 0.0)).g - cell.g,
				cell_sample(cell_pos + vec2(0.0, 1.0)).g - cell.g
			);
			float magnitude = length(gradient);
			if (magnitude > 1e-5) {
				vec2 inward = gradient / magnitude;
				float retreat_cells = -edge_offset / max(cell_pixels.y, 1.0);
				float probe_a = cell_sample(cell_pos + inward * (2.0 * retreat_cells)).g;
				float probe_b = cell_sample(cell_pos + inward * (3.0 * retreat_cells)).g;
				// 0.5 is the border itself; above it is still inside the fog.
				float survives = smoothstep(0.46, 0.54, min(probe_a, probe_b));
				edge_offset *= survives;
			}
		}

		// Recession, the other direction: the hero leans the mist away on every
		// side, and the light map pushes it back further where the room is lit.
		// Both are bounded per pixel, so the border cannot slide a whole row.
		float push = 0.0;
		if (hero_push_px != 0.0) {
			float hero_distance = length(px - hero_center_px);
			push += hero_push_px * (
				1.0 - smoothstep(hero_push_radius_px * 0.35, hero_push_radius_px, hero_distance)
			);
		}
		// Light pushes the cut outwards, so the shadow recedes where it is lit.
		// The mask is untouched: this moves the border, it never opens a cell
		// that is still unexplored.
		if (light_push_px != 0.0) {
			vec3 light_sample = texture(light_tex, (px + 0.5) / light_pixels).rgb;
			float light = clamp(
				dot(light_sample, vec3(0.3, 0.59, 0.11)) * light_gain, 0.0, 1.0
			);
			push += light * light_push_px;
		}
		push = min(push, max_push_px);

		// The hero and the light add on top of the breathing, in the same direction:
		// both of them lean the border away from the light. `wobble` is the *cut*
		// position, which is the opposite sign of the fog edge above: a positive cut
		// means the fog has to reach further in before it is drawn, i.e. it recedes.
		float wobble = push - edge_offset;
		float soft = max(edge_softness, 0.001);
		float band = smoothstep(-soft, soft, distance_px - wobble);

		// Ordered dither only where the band is in flight, so the fog interior
		// stays clean and the border breaks into chunky pixel grain.
		float border = 1.0 - abs(band * 2.0 - 1.0);
		float dither = step(bayer4(px / dither_scale), band);
		band = mix(band, dither, dither_strength * border);

		// Two terms, because a pixel can be dark for two different reasons:
		//   * the cell itself is fogged (or still fading) -> its own opacity, but
		//     only inside the band: a cell that is far from the border and still
		//     evaporating must stay invisible, otherwise the whole reveal wave
		//     turns into a grey flash across the room (the mask deliberately
		//     flips a cell to "revealed" the moment its fade starts).
		//   * the fringe spills over cells that are already revealed -> the band
		//     alone, at full strength.
		// Which of the two applies is decided by the *distance* sign, not by the
		// cell opacity: the opacity is bilinear, so it is already 0.2 well inside
		// the revealed side, and using it there diluted the fringe to about half.
		// `body_sharp` keeps the bilinear fade from eating 8 px into the fog on
		// every border (the smear made the fog look thinner, not softer).
		float body_sharp = smoothstep(0.30, 0.70, body);
		float fog_side = smoothstep(-1.5, 1.5, distance_px);
		float value = band * mix(1.0, body_sharp, fog_side);
		float fog_amount = fog_color.a * value;
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
			COLOR = vec4(value, band, body, 1.0);
		} else if (debug_view > 2.5) {
			COLOR = vec4(band, value, push / max(max_push_px, 0.001), 1.0);
		} else {
			COLOR = vec4(rgb, out_alpha);
		}
	}
}
