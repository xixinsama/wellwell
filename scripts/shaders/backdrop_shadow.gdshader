shader_type canvas_item;
render_mode blend_mul, unshaded;

// Background drop shadow: the room's background tile layer, blurred and pushed
// away from the nearest light.
//
// This quad sits between the backdrop plate (z -1) and the background tile layer
// (z 0), so it darkens the plate only where the tile layer *is not*: the offset
// silhouette reads as the tiles casting a shadow onto the plate behind them. The
// layer draws over it afterwards, so the tiles themselves keep their own values.
//
// The mask is the room-sized silhouette produced by `backdrop_shadow_mask.gdshader`.
// Blur and offset both happen here, on the CPU-side texture, which is why one
// quad can shadow a whole room of tiles: blurring per tile would stop at the tile
// border, because an opaque 8x8 tile has no soft edge inside itself.
//
// `blend_mul` multiplies the plate, so the shadow never brightens anything and a
// transparent mask pixel (multiplier 1) leaves the plate untouched.

uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec2 mask_pixels = vec2(320.0, 180.0);
// Shadow displacement in mask pixels. Fixed per project: one global direction, so
// the shadow never changes shape while a lamp swings.
uniform vec2 offset_px = vec2(0.0);
// Radius of the soft edge, in mask pixels.
uniform float blur_px = 2.5;
// How strongly the shadow darkens the plate, 0..1.
uniform float strength = 0.55;
// Multiplier colour of the darkest pixel. Black makes a real shadow; a tint reads
// as coloured glass over the plate.
uniform vec4 shadow_tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// Golden-angle disc: 16 taps in two rings, so the blur is round instead of a
// cross, which is what keeps an 8 px tile shadow from looking like a plus sign.
const int TAP_COUNT = 16;
const float GOLDEN_ANGLE = 2.39996323;

float mask_at(vec2 uv) {
	return texture(mask_tex, clamp(uv, vec2(0.0), vec2(1.0))).a;
}

void fragment() {
	vec2 uv = UV - offset_px / mask_pixels;
	float radius = max(blur_px, 0.001) / mask_pixels.x;
	float total = mask_at(uv) * 1.0;
	float weight_sum = 1.0;
	for (int index = 0; index < TAP_COUNT; index++) {
		float t = float(index) + 0.5;
		float ring = 0.45 + 0.55 * (t / float(TAP_COUNT));
		float angle = t * GOLDEN_ANGLE;
		// Gaussian-ish falloff: closer taps matter more, the outer ring only
		// softens the silhouette edge.
		float weight = exp(-ring * ring * 3.0);
		vec2 direction = vec2(cos(angle), sin(angle)) * radius * ring * 3.0;
		total += mask_at(uv + direction) * weight;
		weight_sum += weight;
	}
	float coverage = clamp(total / weight_sum, 0.0, 1.0);
	float amount = clamp(coverage * strength, 0.0, 1.0);
	COLOR = vec4(mix(vec3(1.0), shadow_tint.rgb, amount), 1.0);
}
