shader_type canvas_item;

// Inner top-edge highlight for the solid terrain.
//
// The mask is one texel per terrain tile (the solid layer's collision
// silhouette), so a tile is either fully solid or fully open. Sampling it at
// pixel resolution with a nearest filter keeps the outline exactly on the tile
// grid: a 1-2 px bright line along the top face of every solid run, which is the
// "light catching the step" look.
//
// The quad is one full room: all coordinates below are room-local pixels, derived
// from the quad UVs (never VERTEX, which is not guaranteed to stay in local space
// in a canvas_item fragment).

uniform sampler2D mask_texture : filter_nearest, repeat_disable;
// Mask size in tiles.
uniform vec2 mask_cells = vec2(40.0, 23.0);
uniform float tile_pixels = 8.0;
uniform vec4 rim_color : source_color = vec4(0.72, 0.94, 1.0, 1.0);
uniform float rim_strength = 0.85;
// How many pixels deep the highlight reaches down from the top face.
uniform float rim_width = 2.0;
// Extra falloff inside `rim_width`. 0 is a hard pixel band, 1 fades it out.
uniform float rim_softness = 0.6;
// Horizontal jittered pixels, to keep the line from looking vector-drawn.
uniform float rim_grain = 0.18;

float solid_at(vec2 pixel) {
	vec2 cell = floor(pixel / tile_pixels);
	if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= mask_cells.x || cell.y >= mask_cells.y) {
		return 0.0;
	}
	return texture(mask_texture, (cell + 0.5) / mask_cells).r;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	// QuadMesh UVs run bottom-up, the mask is authored top-down.
	vec2 quad_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 pixel = floor(quad_uv * mask_cells * tile_pixels);
	vec4 result = vec4(0.0);
	if (solid_at(pixel) > 0.5) {
		// Depth below the top face of this solid run, in pixels. 0 means the pixel
		// above is already open air.
		float depth = 0.0;
		bool found = false;
		for (int step = 1; step <= 8; step++) {
			if (float(step) > max(rim_width, 1.0)) {
				break;
			}
			if (solid_at(pixel - vec2(0.0, float(step))) < 0.5) {
				found = true;
				break;
			}
			depth = float(step);
		}
		if (found || depth <= 0.0) {
			float fade = 1.0 - clamp(depth / max(rim_width, 1.0), 0.0, 1.0);
			fade = mix(1.0, fade, clamp(rim_softness, 0.0, 1.0));
			float grain = mix(1.0, hash21(pixel) * 2.0, clamp(rim_grain, 0.0, 1.0));
			float alpha = clamp(rim_strength * fade * grain, 0.0, 1.0);
			result = vec4(rim_color.rgb, rim_color.a * alpha);
		}
	}
	COLOR = result;
}
