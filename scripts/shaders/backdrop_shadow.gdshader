shader_type canvas_item;
render_mode blend_mul, unshaded;

// Background drop shadow: the room's background tile layer, blurred and pushed in
// one fixed direction.
//
// The quad is drawn **above the light shade** on purpose. Under the shade it was
// mathematically there but invisible: the shade multiplies the whole plate by the
// light map, so on the lab's dark plate a 30% shadow of an almost black pixel is
// still almost black (measured: 4022 px touched but only 1.46/255 mean change).
// Above the shade it darkens the *final* plate colour, so it keeps its contrast
// wherever the plate is visible at all.
//
// Drawing above the tiles would darken the tiles themselves, so the shader keeps the
// un-offset silhouette as an exclusion mask: the shadow is multiplied by
// `1 - tile coverage`, which leaves every tile pixel alone and only marks the plate
// showing between and around the tiles.
//
// The mask is the room-sized silhouette from `backdrop_shadow_mask.gdshader`. Blur and
// offset both happen here, on the CPU-side texture, which is why one quad can shadow
// a whole room of tiles: blurring per tile would stop at the tile border, because an
// opaque 8x8 tile has no soft edge inside itself.

uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec2 mask_pixels = vec2(320.0, 180.0);
// The room light map (see LightField). A shadow is cast *by* light, so the shadow
// only exists where the plate is lit: gating the darkening with this map is both
// physically right and what keeps it from painting black bands through the dark
// parts of the room, where it would steal attention without adding depth.
uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform vec2 light_pixels = vec2(320.0, 180.0);
// Below `light_floor` there is no shadow at all, above `light_ceil` it is at full
// strength; in between it fades in with the light.
uniform float light_floor = 0.06;
uniform float light_ceil = 0.5;
// Shadow displacement in mask pixels. Fixed per project: one global direction, so
// the shadow never changes shape while a lamp swings.
uniform vec2 offset_px = vec2(0.0);
// Radius of the soft edge, in mask pixels.
uniform float blur_px = 3.0;
// How strongly the shadow darkens a fully lit plate, 0..1.
uniform float strength = 0.85;
// Hard ceiling on the darkening, even where the plate is brightest. The shadow is
// there for depth, not to become the subject of the picture.
uniform float max_darkness = 0.5;
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
	// Exclusion: 1 where a background tile is drawn, so the tiles stay untouched.
	float tile = mask_at(UV);
	if (tile > 0.98) {
		COLOR = vec4(1.0);
	} else {
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
		// The tile edge is 1 px wide in the mask, so fade the exclusion over that
		// pixel instead of stepping: a hard edge would ring along every tile.
		float free = 1.0 - smoothstep(0.05, 0.75, tile);
		float light = dot(
			texture(light_tex, (floor(UV * light_pixels) + 0.5) / light_pixels).rgb,
			vec3(0.3, 0.59, 0.11)
		);
		float lit = smoothstep(light_floor, light_ceil, light);
		float amount = min(coverage * strength * free * lit, max_darkness);
		if (amount < 0.004) {
			COLOR = vec4(1.0);
		} else {
			COLOR = vec4(mix(vec3(1.0), shadow_tint.rgb, amount), 1.0);
		}
	}
}
