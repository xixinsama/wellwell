shader_type canvas_item;
render_mode blend_mul, unshaded;

// Background drop shadow, lit by the hero's own lantern.
//
// The model, and why:
//
// - **The hero's lantern is the key light.** The shadow direction is the reverse of
//   the hero's position in the room, so walking around swings the backdrop shadow the
//   other way -- the strongest depth cue this layer can give, and the reason it is
//   drawn above the light passes at all.
// - **The shadow only exists inside the lantern's reach.** A shadow is cast *by*
//   light, so beyond the hero's bubble the plate is left alone instead of gaining
//   black bands in the dark.
// - **Lamps are fill light.** Other lights do not create more shadow; they brighten
//   what is already there (`1 - fill`), which is how a second lamp in a room softens
//   the shadow of the first. Gating on the *sum* of all light (the previous model)
//   made every lamp darken the plate, which read backwards.
// - **It never gets darker than `max_darkness`.** It is a depth cue, not the subject.
//
// The quad is drawn after every additive pass (the shade at z 8, the glow and bloom
// composite at 9) and before the fog, and the shader subtracts the *un-offset*
// silhouette so tiles themselves are never darkened.

uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec2 mask_pixels = vec2(320.0, 180.0);
// Room-local hero lantern: where the key light is and how far it reaches.
uniform vec2 key_pos_px = vec2(-99999.0, -99999.0);
uniform float key_radius_px = 110.0;
// Shadow displacement: direction is set per room from the hero's position, length is
// `offset_px`. One global direction per frame, so the whole layer moves as one.
uniform vec2 offset_px = vec2(0.0);
uniform float blur_px = 3.0;
uniform float strength = 0.85;
uniform float max_darkness = 0.5;
// Fill lights: xy = room pixel position, z = radius in pixels, w = energy. Up to four.
uniform vec4 fill0 = vec4(0.0);
uniform vec4 fill1 = vec4(0.0);
uniform vec4 fill2 = vec4(0.0);
uniform vec4 fill3 = vec4(0.0);
uniform float fill_count = 0.0;
// How much a full-strength fill light removes from the shadow, 0..1.
uniform float fill_erase = 0.85;
uniform vec4 shadow_tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

const int TAP_COUNT = 16;
const float GOLDEN_ANGLE = 2.39996323;

float mask_at(vec2 uv) {
	return texture(mask_tex, clamp(uv, vec2(0.0), vec2(1.0))).a;
}

// Falloff of one fill light at a room pixel, 0..1.
float fill_at(vec2 px, vec4 light) {
	if (light.z <= 0.5) {
		return 0.0;
	}
	float distance = length(px - light.xy);
	return clamp(1.0 - distance / light.z, 0.0, 1.0) * light.w;
}

void fragment() {
	vec2 px = floor(UV * mask_pixels);
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
			float weight = exp(-ring * ring * 3.0);
			vec2 direction = vec2(cos(angle), sin(angle)) * radius * ring * 3.0;
			total += mask_at(uv + direction) * weight;
			weight_sum += weight;
		}
		float coverage = clamp(total / weight_sum, 0.0, 1.0);
		float free = 1.0 - smoothstep(0.05, 0.75, tile);
		// Key: only inside the hero's lantern, fading out towards its edge.
		float key = 1.0 - smoothstep(key_radius_px * 0.55, key_radius_px, length(px - key_pos_px));
		// Fill: lamps brighten the shadow away instead of adding more of it.
		float fill = 0.0;
		if (fill_count > 0.5) { fill = max(fill, fill_at(px, fill0)); }
		if (fill_count > 1.5) { fill = max(fill, fill_at(px, fill1)); }
		if (fill_count > 2.5) { fill = max(fill, fill_at(px, fill2)); }
		if (fill_count > 3.5) { fill = max(fill, fill_at(px, fill3)); }
		float amount = coverage * strength * free * key * (1.0 - fill * fill_erase);
		amount = min(amount, max_darkness);
		if (amount < 0.004) {
			COLOR = vec4(1.0);
		} else {
			COLOR = vec4(mix(vec3(1.0), shadow_tint.rgb, amount), 1.0);
		}
	}
}
