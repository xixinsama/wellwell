shader_type canvas_item;
render_mode blend_mix;

// Draws the GridWater 2D fluid from a cell texture.
//
// Each texel stores one simulation cell:
//   R = water fill of the cell (0..1 of cell_pixels)
//   G = water depth above the cell, normalized by depth_scale
//   B = motion of the last step (0..1), used for foam on falls
//   A = 255 water, 64 wall, 0 empty (walls are never drawn)
//
// World space comes from the quad's UVs, never from VERTEX: a canvas_item
// fragment's VERTEX is not guaranteed to stay in the item's local space.
//
// Empty cells write a transparent colour instead of using `discard`: a
// discarded fragment on a MeshInstance2D quad paints opaque black over the
// terrain in this renderer, while an alpha-zero fragment blends to nothing.
//
// The fill is sampled with a linear filter horizontally, so the surface ramps
// smoothly between neighbouring cells instead of stepping by a whole cell. The
// wall test uses the nearest texel, so water never bleeds into a wall.

uniform sampler2D grid_texture : filter_nearest, repeat_disable;
uniform vec2 field_origin = vec2(0.0, 0.0);
uniform vec2 field_size = vec2(320.0, 180.0);
uniform vec2 grid_size = vec2(40.0, 23.0);
uniform float cell_pixels = 8.0;
uniform float depth_scale = 90.0;

uniform vec4 shallow_color : source_color = vec4(0.26, 0.66, 0.94, 0.62);
uniform vec4 deep_color : source_color = vec4(0.05, 0.18, 0.42, 0.9);
uniform vec4 crest_color : source_color = vec4(0.85, 0.97, 1.0, 0.95);
uniform vec4 foam_color : source_color = vec4(0.96, 1.0, 1.0, 0.9);
uniform float caustic_strength = 0.14;
// Impact ripples: xy = impact point, z = age in seconds, w = strength.
uniform vec4 ripple_0 = vec4(0.0);
uniform vec4 ripple_1 = vec4(0.0);
uniform vec4 ripple_2 = vec4(0.0);
uniform float ripple_amplitude = 1.8;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Vertical offset of the surface from one impact: a decaying ring that travels
// outwards. Purely visual - the body never moves, the drawing does.
float ripple_offset(vec4 ripple, float world_x) {
	if (ripple.w <= 0.001) {
		return 0.0;
	}
	float age = ripple.z;
	float distance = world_x - ripple.x;
	float envelope = exp(-abs(distance) / (12.0 + 18.0 * ripple.w));
	float ring = sin(distance * 0.45 - age * 11.0);
	float decay = exp(-age * 2.6);
	return ring * envelope * decay * ripple.w * ripple_amplitude;
}

void fragment() {
	// QuadMesh UVs run bottom-up, the field is authored top-down.
	vec2 quad_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 world = field_origin + quad_uv * field_size;
	vec2 local = (world - field_origin) / cell_pixels;
	vec2 index = clamp(floor(local), vec2(0.0), grid_size - vec2(1.0));
	vec4 cell = texture(grid_texture, (index + 0.5) / grid_size);
	vec4 result = vec4(0.0);
	if (cell.a >= 0.75) {
		// Horizontal ramp between cells for a smooth surface, snapped vertically.
		vec2 fill_uv = vec2(local.x / grid_size.x, (index.y + 0.5) / grid_size.y);
		float fill = texture(grid_texture, fill_uv).r;
		// Falling water keeps its cell: a thin stream would otherwise render as
		// dashes, one per cell, instead of a continuous column.
		fill = mix(fill, 1.0, step(0.12, cell.b));
		float surface = cell_pixels - fill * cell_pixels;
		// A ripple only moves the top cell of a column: shifting a full cell deep
		// inside the body would punch a hole in it.
		if (cell.g < 0.002) {
			float ripple = ripple_offset(ripple_0, world.x)
				+ ripple_offset(ripple_1, world.x)
				+ ripple_offset(ripple_2, world.x);
			surface += clamp(ripple, -3.0, 3.0);
		}
		float water_top = clamp(surface, 0.0, cell_pixels);
		float y_local = (local.y - index.y) * cell_pixels;
		if (y_local >= water_top) {
			float below_surface = y_local - water_top;
			float depth = cell.g * depth_scale + below_surface;
			float t = clamp(depth / depth_scale, 0.0, 1.0);
			vec3 color = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 0.9, t));
			float alpha = mix(shallow_color.a, deep_color.a, t);
			if (depth < 1.0) {
				// One pixel of crest: the brightest part of the surface. It follows
				// the surface of a pool and the top of a falling stream alike.
				color = crest_color.rgb;
				alpha = crest_color.a;
			} else {
				float motion = cell.b;
				float edge = 1.0 - smoothstep(1.0, 2.5, depth);
				float streak = value_noise(vec2(world.x * 0.8, world.y * 0.22 + TIME * 7.0));
				float foam = clamp(edge * 0.35 + motion * (0.12 + streak * 0.3), 0.0, 1.0);
				if (foam > 0.02 && hash21(floor(world)) < foam * 0.7) {
					color = foam_color.rgb;
					alpha = foam_color.a;
				} else {
					float caustic = sin(world.x * 0.55 + TIME * 1.1) * sin(world.y * 0.85 - TIME * 0.7);
					color += clamp(caustic, 0.0, 1.0) * caustic_strength * (1.0 - t * 0.5);
				}
			}
			result = vec4(color, alpha);
		}
	}
	COLOR = result;
}

