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
// The water body each ripple landed in: the world x of its left and right edge.
// WaterGrid measures them from the simulation, so the mirrors below are real walls of
// the body and never an arbitrary distance.
uniform vec2 ripple_wall_0 = vec2(0.0);
uniform vec2 ripple_wall_1 = vec2(0.0);
uniform vec2 ripple_wall_2 = vec2(0.0);
// How far each ripple carries, in px: the 1/e distance of its swell. WaterGrid
// measures the water body the impact landed in and hands its half-width over, so the
// crest still lifts the far side of the body it belongs to.
uniform float ripple_reach_0 = 24.0;
uniform float ripple_reach_1 = 24.0;
uniform float ripple_reach_2 = 24.0;
uniform float ripple_amplitude = 3.6;
// Crest speed in px/s. The crest has to cross the body inside one ripple life, so
// this is fast enough to cross a two hundred pixel pool and come back.
uniform float ripple_speed = 150.0;
// Ring-down of one crest after it passed a column, per second.
uniform float ripple_damping = 1.4;
// Angular frequency of one crest, rad/s. One cycle is a single heavy swell.
uniform float ripple_omega = 7.5;
// Share of the crest that comes back off the edges of the body.
uniform float ripple_reflection = 0.55;
// Highest the surface may ride above the top of its cell because of a ripple.
uniform float ripple_limit = 6.0;
// Multi-layer surface. The same wave is drawn three times with its own age offset,
// speed and amplitude, and the three crests sit at slightly different depths: the
// back one lower and darker, the front one higher and brighter. A passing wave then
// shows three crests out of phase instead of one flat line, which is what gives the
// body thickness (Rain World builds its water the same way).
uniform float layer_back_delay = 0.10;
uniform float layer_back_speed = 0.92;
uniform float layer_back_amplitude = 0.60;
uniform float layer_back_drop = 1.5;
uniform float layer_back_shade = 0.22;
uniform float layer_front_delay = -0.06;
uniform float layer_front_speed = 1.12;
uniform float layer_front_amplitude = 0.50;
uniform float layer_front_rise = 1.5;
uniform float layer_front_lift = 0.55;

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

// One crest that has been travelling for `age` seconds and is `distance` px from the
// source it belongs to.
//
// Zero until the crest arrives: this is the whole point of the model. The surface of
// a pool must stay exactly at rest ahead of the wave, so the disturbance spreads out
// from the impact instead of the whole body lifting at once (the previous model had a
// static envelope times a cosine of `distance - speed * age`, which at small ages puts
// every column at nearly the same phase: the entire pool bulged together, and then
// stayed in a standing oscillation for the rest of the ripple's life).
//
// After arrival the surface rises once and falls once (`ripple_omega`), rings down at
// `ripple_damping`, and is quieter the further it travelled (`reach`).
float retarded_wave(float age, float distance, float speed, float reach) {
	float travel = distance / max(speed, 1.0);
	if (age <= travel) {
		return 0.0;
	}
	float local = age - travel;
	float swell = sin(local * ripple_omega) * exp(-local * ripple_damping);
	return swell * exp(-distance / max(reach, 1.0));
}

// Displacement of one surface of a body from one impact, at one column.
//
// The direct crest plus its two mirrors in the body edges (method of images): a crest
// that hits the edge comes back, so a column `d` px from the impact that also sits
// `e` px from a wall moves again about `(d + e) / speed` after the landing. The
// mirrors are the measured edges of the body, so the echo can only exist inside the
// pool that was actually splashed - never across a dry gap.
//
// `age_offset`, `speed_factor` and `amplitude_factor` are per layer: the three
// visible surfaces run the same wave, shifted in time and scaled, so they drift out of
// phase while the crest passes.
//
// The ripple is a point on *one* surface, so it also decays with the vertical distance
// to that surface: a pool above or below the impact is a different body and must not
// wobble when the hero jumps somewhere else.
float ripple_surface(
	vec4 ripple, vec2 walls, float reach,
	float age_offset, float speed_factor, float amplitude_factor,
	float world_x, float world_y
) {
	if (ripple.w <= 0.001) {
		return 0.0;
	}
	float vertical = exp(-abs(world_y - ripple.y) / 5.0);
	if (vertical < 0.01) {
		return 0.0;
	}
	float age = ripple.z - age_offset;
	if (age <= 0.0) {
		return 0.0;
	}
	float speed = ripple_speed * speed_factor;
	float total = retarded_wave(age, abs(world_x - ripple.x), speed, reach);
	total += ripple_reflection
		* retarded_wave(age, abs(world_x - (2.0 * walls.x - ripple.x)), speed, reach);
	total += ripple_reflection
		* retarded_wave(age, abs(world_x - (2.0 * walls.y - ripple.x)), speed, reach);
	return total * vertical * ripple.w * ripple_amplitude * amplitude_factor;
}

// The three surfaces of the body at one column, from the three ripple slots.
// Layer 0 is the back surface, 1 the simulated one and 2 the front one.
float ripple_layer(int layer, float world_x, float world_y) {
	float age_offset = layer == 0 ? layer_back_delay
		: (layer == 2 ? layer_front_delay : 0.0);
	float speed_factor = layer == 0 ? layer_back_speed
		: (layer == 2 ? layer_front_speed : 1.0);
	float amplitude_factor = layer == 0 ? layer_back_amplitude
		: (layer == 2 ? layer_front_amplitude : 1.0);
	return ripple_surface(ripple_0, ripple_wall_0, ripple_reach_0,
			age_offset, speed_factor, amplitude_factor, world_x, world_y)
		+ ripple_surface(ripple_1, ripple_wall_1, ripple_reach_1,
			age_offset, speed_factor, amplitude_factor, world_x, world_y)
		+ ripple_surface(ripple_2, ripple_wall_2, ripple_reach_2,
			age_offset, speed_factor, amplitude_factor, world_x, world_y);
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
		// The three surfaces of this column. Only the top cell of a column carries
		// them: shifting a full cell deep inside the body would punch a hole in it, and
		// only the top cell can show water above its own floor. `surface_world_y` is
		// where the simulated surface sits in the world, so a ripple knows which body
		// it belongs to.
		float mid_top = surface;
		float back_top = surface + layer_back_drop;
		float front_top = surface - layer_front_rise;
		float y_local = (local.y - index.y) * cell_pixels;
		// Which of the three surfaces this pixel belongs to: 0 = the raised front lip,
		// 1 = the band between the front and the back surface, 2 = the water behind the
		// back surface. -1 means "not layered", which is every cell below the top one:
		// tinting those would stripe the whole body once per cell.
		float layer_band = -1.0;
		if (cell.g < 0.002) {
			float surface_world_y = field_origin.y + index.y * cell_pixels + surface;
			mid_top = surface
				- clamp(ripple_layer(1, world.x, surface_world_y), -ripple_limit, ripple_limit);
			back_top = surface + layer_back_drop
				- clamp(ripple_layer(0, world.x, surface_world_y), -ripple_limit, ripple_limit);
			front_top = surface - layer_front_rise
				- clamp(ripple_layer(2, world.x, surface_world_y), -ripple_limit, ripple_limit);
			float mid_draw = clamp(mid_top, 0.0, cell_pixels);
			float back_draw = clamp(back_top, 0.0, cell_pixels);
			layer_band = y_local < mid_draw ? 0.0 : (y_local >= back_draw ? 2.0 : 1.0);
		}
		// The nearest surface is the front one, so it decides where the water starts.
		float water_top = clamp(mid_top, 0.0, cell_pixels);
		float front_draw = clamp(front_top, 0.0, cell_pixels);
		if (y_local >= front_draw) {
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
			// Multi-layer depth: the band above the simulated surface is the raised
			// lip of the nearest water (brightest, foamiest), and everything below the
			// back surface is water seen through all three layers (darker, less
			// saturated). Each layer runs the wave with its own delay, so the three
			// bands wave out of phase instead of moving as one line.
			if (layer_band == 0.0) {
				color = mix(color, foam_color.rgb, layer_front_lift);
				alpha = mix(alpha, foam_color.a, layer_front_lift);
			} else if (layer_band == 2.0) {
				color = mix(color, deep_color.rgb, layer_back_shade);
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
