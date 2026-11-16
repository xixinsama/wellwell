shader_type canvas_item;
render_mode blend_mix;

// Draws the GridWater 2D fluid from a cell texture.
//
// Each texel stores one simulation cell:
//   R = water fill of the cell (0..1 of cell_pixels)
//   G = water depth above the cell, normalized by depth_scale
//   B = motion of the last step (0..1), used for foam and for the fall edges
//   A = 255 water, 0 dry or solid (both draw nothing)
//
// World space comes from the quad's UVs, never from VERTEX: a canvas_item
// fragment's VERTEX is not guaranteed to stay in the item's local space.
//
// Empty cells write a transparent colour instead of using `discard`: a
// discarded fragment on a MeshInstance2D quad paints opaque black over the
// terrain in this renderer, while an alpha-zero fragment blends to nothing.
//
// The surface is drawn from a height field interpolated between cell centres,
// not from the raw texel grid: a pool surface is a continuous line and a falling
// stream gets soft diagonal edges instead of a staircase of whole cells. That is
// what makes a 4 px or 8 px simulation read as smooth water.

uniform sampler2D grid_texture : filter_nearest, repeat_disable;
uniform vec2 field_origin = vec2(0.0, 0.0);
uniform vec2 field_size = vec2(320.0, 180.0);
uniform vec2 grid_size = vec2(40.0, 23.0);
uniform float cell_pixels = 8.0;
uniform float depth_scale = 90.0;

uniform vec4 shallow_color : source_color = vec4(0.24, 0.66, 0.95, 0.72);
uniform vec4 deep_color : source_color = vec4(0.04, 0.16, 0.42, 0.92);
uniform vec4 crest_color : source_color = vec4(0.85, 0.97, 1.0, 0.95);
uniform vec4 foam_color : source_color = vec4(0.96, 1.0, 1.0, 0.9);
uniform float caustic_strength = 0.14;
// Impact ripples: xy = impact point, z = age in seconds, w = strength.
uniform vec4 ripple_0 = vec4(0.0);
uniform vec4 ripple_1 = vec4(0.0);
uniform vec4 ripple_2 = vec4(0.0);
uniform float ripple_amplitude = 2.2;

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

vec4 cell_at(vec2 index) {
	vec2 clamped = clamp(index, vec2(0.0), grid_size - vec2(1.0));
	return texture(grid_texture, (clamped + 0.5) / grid_size);
}

// Height of the water surface from one impact.
//
// The peak sits exactly on the impact point and the wave travels outwards from
// there: the ring front moves at `speed` px/s, the envelope falls off with
// distance (so the neighbours are quieter than the landing point) and the whole
// thing fades in about a second. Purely visual - the body never moves.
//
// The ripple is a point on *one* surface, so it also decays with the vertical
// distance to that surface: a pool above or below the impact is a different body
// and must not wobble when the hero jumps somewhere else.
float ripple_offset(vec4 ripple, float world_x, float world_y) {
	if (ripple.w <= 0.001) {
		return 0.0;
	}
	float age = ripple.z;
	float vertical = exp(-abs(world_y - ripple.y) / 5.0);
	if (vertical < 0.01) {
		return 0.0;
	}
	float distance = abs(world_x - ripple.x);
	float width = 16.0 + 20.0 * ripple.w;
	float envelope = exp(-distance / width);
	float front = 120.0 * age;
	float ring = exp(-pow((distance - front) / (8.0 + 8.0 * ripple.w), 2.0));
	float wave = cos((distance - front) * 0.85);
	float decay = exp(-age * 2.0);
	return wave * ring * envelope * decay * vertical * ripple.w * ripple_amplitude;
}

void fragment() {
	// QuadMesh UVs run bottom-up, the field is authored top-down.
	vec2 quad_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 world = field_origin + quad_uv * field_size;
	vec2 local = (world - field_origin) / cell_pixels;
	vec2 index = clamp(floor(local), vec2(0.0), grid_size - vec2(1.0));
	vec4 cell = cell_at(index);
	vec4 result = vec4(0.0);
	if (cell.a >= 0.75) {
		// Surface height: blend towards the neighbour cell on the near side, so a
		// height change between two cells becomes one short slope instead of a
		// step. A dry neighbour pulls the surface down to the cell floor (the edge
		// of the water); a wall neighbour mirrors it, so the water does not taper
		// into the wall it rests against.
		float fx = fract(local.x);
		vec4 left = cell_at(index - vec2(1.0, 0.0));
		vec4 right = cell_at(index + vec2(1.0, 0.0));
		bool left_wall = left.a > 0.25 && left.a < 0.75;
		bool right_wall = right.a > 0.25 && right.a < 0.75;
		float fill = cell.r;
		if (fx < 0.5) {
			fill = mix(left.r, fill, left_wall ? 1.0 : (0.5 + fx));
		} else {
			fill = mix(fill, right.r, right_wall ? 0.0 : (fx - 0.5));
		}
		// Interior of a falling stream: a cell in transit holds water that is
		// between two places, so drawing only its fill would dash the column.
		if (cell.b > 0.15 && cell_at(index + vec2(0.0, 1.0)).a >= 0.75) {
			fill = max(fill, 0.9);
		}
		float surface = cell_pixels - clamp(fill, 0.0, 1.0) * cell_pixels;
		// A ripple only moves the top cell of a column: shifting a full cell deep
		// inside the body would punch a hole in it. `surface_world_y` is where that
		// top cell's surface sits in the world, so a ripple knows which body it
		// belongs to.
		if (cell.g < 0.002) {
			float surface_world_y = field_origin.y + index.y * cell_pixels + surface;
			float ripple = ripple_offset(ripple_0, world.x, surface_world_y)
				+ ripple_offset(ripple_1, world.x, surface_world_y)
				+ ripple_offset(ripple_2, world.x, surface_world_y);
			surface -= clamp(ripple, -3.5, 3.5);
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
