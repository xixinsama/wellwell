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
// How far each ripple carries, in px: the 1/e distance of its swell. WaterGrid
// measures the water body the impact landed in and hands its half-width over, so
// one landing moves the *whole* body instead of a patch around the impact point.
uniform float ripple_reach_0 = 24.0;
uniform float ripple_reach_1 = 24.0;
uniform float ripple_reach_2 = 24.0;
uniform float ripple_amplitude = 3.6;
uniform float ripple_speed = 64.0;
uniform float ripple_damping = 1.1;
// Highest the surface may ride above the top of its cell because of a ripple.
uniform float ripple_limit = 6.0;
// Room light map (see LightField). The surface mirrors the light that reaches it:
// a bright band right under the surface plus a drifting sparkle, so a lantern
// next to a pool shows up in the water.
uniform sampler2D light_tex : filter_nearest, repeat_disable;
uniform vec2 light_pixels = vec2(320.0, 180.0);
uniform float light_gain = 1.0;
uniform float reflection_strength = 0.8;

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

float light_at(vec2 world) {
	vec2 uv = (world + 0.5) / light_pixels;
	vec3 light = texture(light_tex, uv).rgb;
	return clamp(dot(light, vec3(0.3, 0.59, 0.11)) * light_gain, 0.0, 1.0);
}

// Height of the water surface from one impact.
//
// The landing sends a ring train outwards: the pattern is a cosine of how far the
// crest has travelled (`speed` px/s), so the rings visibly leave the impact point,
// and the train fades out at `ripple_damping` per second. Purely visual - the body
// never moves.
//
// The amplitude must not die next to the impact. This ripple is the only thing that
// moves the surface of a settled pool, so an envelope that is gone after a cell or
// two does not read as a quiet ripple: it reads as a hard vertical edge through the
// middle of one pool, with half of the same body wobbling and the other half frozen
// flat (the old `exp(-distance / (18 + 22 * w))` envelope plus a +-25 px Gaussian on
// the ring front dropped below one rendered pixel about 40 px from the landing).
// `reach` is therefore the measured half-width of the water body the impact landed
// in (WaterGrid measures it from the simulation), which keeps the swell inside its
// own body and above the one pixel that makes it visible everywhere in that body.
//
// The ripple is a point on *one* surface, so it also decays with the vertical
// distance to that surface: a pool above or below the impact is a different body
// and must not wobble when the hero jumps somewhere else.
float ripple_offset(vec4 ripple, float reach, float world_x, float world_y) {
	if (ripple.w <= 0.001) {
		return 0.0;
	}
	float vertical = exp(-abs(world_y - ripple.y) / 5.0);
	if (vertical < 0.01) {
		return 0.0;
	}
	float distance = abs(world_x - ripple.x);
	float envelope = exp(-distance / max(reach, 1.0));
	float front = ripple_speed * ripple.z;
	float wave = cos((distance - front) * 0.8);
	float decay = exp(-ripple.z * ripple_damping);
	return wave * envelope * decay * vertical * ripple.w * ripple_amplitude;
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
			float ripple = ripple_offset(ripple_0, ripple_reach_0, world.x, surface_world_y)
				+ ripple_offset(ripple_1, ripple_reach_1, world.x, surface_world_y)
				+ ripple_offset(ripple_2, ripple_reach_2, world.x, surface_world_y);
			surface -= clamp(ripple, -ripple_limit, ripple_limit);
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
			// Reflection: a *surface* highlight, not a glow filling the body. The
			// crest pixel takes the light, then a couple of hard rows under it,
			// thinning out with depth and scattered per pixel, so it stays pixel
			// art instead of a smooth gradient inside the rectangle.
			float lit = light_at(world);
			if (lit > 0.02) {
				float level = clamp(lit * reflection_strength, 0.0, 1.0);
				if (below_surface < 1.0) {
					color = mix(color, crest_color.rgb, clamp(level * 1.7, 0.0, 1.0));
				} else {
					float rows = floor(below_surface);
					float reach = 1.0 + level * 3.0;
					float fall = clamp(1.0 - (rows - 1.0) / reach, 0.0, 1.0);
					float stepped = floor(fall * 3.0 + 0.5) / 3.0;
					if (hash21(floor(world)) < stepped * level) {
						color = mix(color, crest_color.rgb, 0.7 * level);
					}
				}
				alpha = clamp(alpha + level * 0.12, 0.0, 1.0);
			}
			result = vec4(color, alpha);
		}
	}
	COLOR = result;
}
