shader_type canvas_item;

// Inner outline for the solid terrain.
//
// The mask is one texel per *pixel* of the layer's used rect, baked from the tile
// art alpha, so a slope, a half tile or a decorative brick keeps its real shape
// instead of being treated as a whole cell.
//
// Every solid pixel within `rim_width` of open air is lit, in all four directions,
// so the line runs all the way around the silhouette: top faces, walls and
// overhangs alike. Brightness falls off with the distance to the nearest open
// pixel, which is what makes it read as a rim rather than a stroke.
//
// The quad is one full room: all coordinates below are mask pixels, derived from
// the quad UVs (never VERTEX, which is not guaranteed to stay in local space in a
// canvas_item fragment).

uniform sampler2D mask_texture : filter_nearest, repeat_disable;
// Mask size in pixels.
uniform vec2 mask_pixels = vec2(320.0, 184.0);
// One texel per tile: 1 where the hero can reach that air, 0 where it cannot.
uniform sampler2D reach_texture : filter_nearest, repeat_disable;
uniform vec2 reach_cells = vec2(40.0, 23.0);
uniform float tile_pixels = 8.0;
// 1 only lights the side of a wall that faces air the hero can reach.
uniform float require_reach = 1.0;
uniform vec4 rim_color : source_color = vec4(0.72, 0.94, 1.0, 1.0);
uniform float rim_strength = 0.85;
// How many pixels deep the outline reaches in from the silhouette edge.
uniform float rim_width = 2.0;
// Extra falloff inside `rim_width`. 0 is a hard pixel band, 1 fades it out.
uniform float rim_softness = 0.6;
// Jittered pixels, so the line does not look vector-drawn.
uniform float rim_grain = 0.18;
// 1 lights the inside of the silhouette, 0 lights the air just outside it.
uniform float inside = 1.0;

float solid_at(vec2 pixel) {
	if (pixel.x < 0.0 || pixel.y < 0.0 || pixel.x >= mask_pixels.x || pixel.y >= mask_pixels.y) {
		return 0.0;
	}
	return texture(mask_texture, (floor(pixel) + 0.5) / mask_pixels).r;
}

// Is this pixel's tile air the hero can reach? A sealed pocket answers 0, which is
// what keeps the inside of a closed room dark.
float reachable_at(vec2 pixel) {
	if (require_reach < 0.5) {
		return 1.0;
	}
	vec2 tile = floor(pixel / tile_pixels);
	if (tile.x < 0.0 || tile.y < 0.0 || tile.x >= reach_cells.x || tile.y >= reach_cells.y) {
		return 0.0;
	}
	return texture(reach_texture, (tile + 0.5) / reach_cells).r;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Steps along the four axes until `target` is found, and returns that distance.
// `target` is 0.0 to look for air, 1.0 to look for solid. For the air case the
// first air pixel must also be reachable: otherwise this side of the wall is dark,
// because the hero cannot get to that pocket.
float distance_to(float target, vec2 pixel) {
	float best = rim_width + 1.0;
	for (int axis = 0; axis < 4; axis++) {
		vec2 direction = vec2(0.0, -1.0);
		if (axis == 1) {
			direction = vec2(0.0, 1.0);
		} else if (axis == 2) {
			direction = vec2(-1.0, 0.0);
		} else if (axis == 3) {
			direction = vec2(1.0, 0.0);
		}
		for (int step = 1; step <= 4; step++) {
			if (float(step) > rim_width) {
				break;
			}
			vec2 sample_position = pixel + direction * float(step);
			float sample_at = solid_at(sample_position);
			if (abs(sample_at - target) < 0.5) {
				if (target < 0.5 && reachable_at(sample_position) < 0.5) {
					break;
				}
				best = min(best, float(step));
				break;
			}
		}
	}
	return best;
}

void fragment() {
	// QuadMesh UVs run bottom-up, the mask is authored top-down.
	vec2 quad_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 pixel = floor(quad_uv * mask_pixels);
	float here = solid_at(pixel);
	bool lit = inside > 0.5 ? here > 0.5 : here < 0.5;
	vec4 result = vec4(0.0);
	if (lit) {
		float distance = inside > 0.5 ? distance_to(0.0, pixel) : distance_to(1.0, pixel);
		if (inside < 0.5 && reachable_at(pixel) < 0.5) {
			// The outside variant lights air, so the air itself has to be reachable.
			distance = rim_width + 1.0;
		}
		if (distance <= rim_width) {
			float fade = 1.0 - clamp((distance - 1.0) / max(rim_width, 1.0), 0.0, 1.0);
			fade = mix(1.0, fade, clamp(rim_softness, 0.0, 1.0));
			float grain = mix(1.0, hash21(pixel) * 2.0, clamp(rim_grain, 0.0, 1.0));
			result = vec4(rim_color.rgb, rim_color.a * clamp(rim_strength * fade * grain, 0.0, 1.0));
		}
	}
	COLOR = result;
}
