shader_type canvas_item;
render_mode blend_mix;

// Draws a water body from a one-row column texture.
//
// Each texel of `column_texture` stores one water column:
//   R = surface y, normalized to (field_top .. field_top + field_height)
//   G = floor y, same normalization
//   A = 1 when the column holds water, 0 when it is a wall or dry
//
// World space comes from the quad's UVs (0..1 across the water field), never
// from VERTEX: a canvas_item fragment's VERTEX is not guaranteed to stay in the
// item's local space, and deriving the column from it shifted the whole body by
// a column. The quad is pixel sized, so one fragment is one game pixel.

uniform sampler2D column_texture : filter_nearest, repeat_disable;
uniform float column_count = 38.0;
uniform vec2 field_origin = vec2(8.0, 180.0);
uniform vec2 field_size = vec2(304.0, 180.0);
uniform float field_top = 180.0;
uniform float field_height = 180.0;

uniform vec4 shallow_color : source_color = vec4(0.26, 0.66, 0.94, 0.62);
uniform vec4 deep_color : source_color = vec4(0.05, 0.18, 0.42, 0.9);
uniform vec4 crest_color : source_color = vec4(0.85, 0.97, 1.0, 0.95);
uniform vec4 foam_color : source_color = vec4(0.96, 1.0, 1.0, 0.9);
uniform float caustic_strength = 0.14;
uniform float foam_height = 2.5;
// Impact ripples: xy = impact point, z = age in seconds, w = strength.
uniform vec4 ripple_0 = vec4(0.0);
uniform vec4 ripple_1 = vec4(0.0);
uniform vec4 ripple_2 = vec4(0.0);
// The water body each ripple landed in: the world x of its left and right edge.
// WaterField measures them from the simulation, so the mirrors below are real walls of
// the basin and never an arbitrary distance.
uniform vec2 ripple_wall_0 = vec2(0.0);
uniform vec2 ripple_wall_1 = vec2(0.0);
uniform vec2 ripple_wall_2 = vec2(0.0);
// How far each ripple carries, in px: the 1/e distance of its swell. WaterField
// measures the water body the impact landed in and hands its half-width over.
uniform float ripple_reach_0 = 24.0;
uniform float ripple_reach_1 = 24.0;
uniform float ripple_reach_2 = 24.0;
uniform float ripple_amplitude = 3.6;
// Crest speed in px/s. The crest has to cross the basin inside one ripple life, so
// this is fast enough to cross a two hundred pixel basin and come back.
uniform float ripple_speed = 150.0;
// Ring-down of one crest after it passed a column, per second.
uniform float ripple_damping = 1.4;
// Angular frequency of one crest, rad/s. One cycle is a single heavy swell.
uniform float ripple_omega = 7.5;
// Share of the crest that comes back off the edges of the basin.
uniform float ripple_reflection = 0.55;
// Multi-layer surface. The same wave is drawn three times with its own age offset,
// speed and amplitude, and the three crests sit at slightly different depths: the back
// one lower and darker, the front one higher and brighter. A passing wave then shows
// three crests out of phase instead of one flat line, which is what gives the body
// thickness (Rain World builds its water the same way).
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

// One crest that has been travelling for `age` seconds and is `distance` px from the
// source it belongs to.
//
// Zero until the crest arrives: the surface of a basin must stay exactly at rest ahead
// of the wave, so the disturbance spreads out from the impact instead of the whole
// body lifting at once (the previous model had a static envelope times a cosine of
// `distance - speed * age`, which at small ages puts every column at nearly the same
// phase: the entire basin bulged together).
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
// `e` px from a wall moves again about `(d + e) / speed` after the landing. The mirrors
// are the measured edges of the body, so the echo can only exist inside the basin that
// was actually splashed - never across a dry gap.
//
// `age_offset`, `speed_factor` and `amplitude_factor` are per layer: the three visible
// surfaces run the same wave, shifted in time and scaled, so they drift out of phase
// while the crest passes.
//
// The ripple is a point on *one* surface, so it also decays with the vertical distance
// to that surface: a splash in one pool cannot wobble the surface of another. Purely
// visual - the height field never moves.
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

float light_at(vec2 world) {
	vec2 uv = (world + 0.5) / light_pixels;
	vec3 light = texture(light_tex, uv).rgb;
	return clamp(dot(light, vec3(0.3, 0.59, 0.11)) * light_gain, 0.0, 1.0);
}

void fragment() {
	// QuadMesh UVs run bottom-up, the field is authored top-down.
	vec2 quad_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 world = field_origin + quad_uv * field_size;
	float column = floor(quad_uv.x * column_count);
	if (column < 0.0 || column >= column_count) {
		discard;
	}
	vec4 data = texture(column_texture, vec2((column + 0.5) / column_count, 0.5));
	if (data.a < 0.5) {
		discard;
	}
	// The three surfaces of this column: the simulated one, the back one slightly
	// deeper and the front one slightly higher. Each carries its own ripple phase.
	float mid_y = field_top + data.r * field_height;
	float back_y = mid_y + layer_back_drop;
	float front_y = mid_y - layer_front_rise;
	mid_y -= clamp(ripple_layer(1, world.x, mid_y), -6.0, 6.0);
	back_y -= clamp(ripple_layer(0, world.x, back_y), -6.0, 6.0);
	front_y -= clamp(ripple_layer(2, world.x, front_y), -6.0, 6.0);
	// The nearest surface is the front one, so it decides where the water starts.
	if (world.y < front_y) {
		discard;
	}
	float floor_y = field_top + data.g * field_height;
	if (world.y >= floor_y) {
		discard;
	}

	float depth = max(floor_y - mid_y, 1.0);
	float t = clamp((world.y - mid_y) / depth, 0.0, 1.0);
	vec3 color = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 0.8, t));
	float alpha = mix(shallow_color.a, deep_color.a, t);
	float under_surface = world.y - mid_y;

	if (under_surface < 1.0) {
		// One pixel of crest: the brightest part of the surface.
		color = crest_color.rgb;
		alpha = crest_color.a;
	} else {
		float wobble = value_noise(vec2(world.x * 0.24, TIME * 1.5 + column * 0.7));
		float foam = 1.0 - smoothstep(1.0, foam_height + wobble * 2.0, under_surface);
		if (foam > 0.0) {
			float dither = hash21(floor(world));
			if (dither < foam * 0.85) {
				color = foam_color.rgb;
				alpha = foam_color.a;
			}
		}
		// Faint light bands drifting along the bottom of the body.
		float caustic = sin(world.x * 0.55 + TIME * 1.1) * sin(world.y * 0.85 - TIME * 0.7);
		color += clamp(caustic, 0.0, 1.0) * caustic_strength * (1.0 - t * 0.5);
	}
	// Multi-layer depth: the band above the simulated surface is the raised lip of the
	// nearest water (brightest, foamiest), and everything below the back surface is
	// water seen through all three layers (darker, less saturated). Each layer runs the
	// wave with its own delay, so the three bands wave out of phase instead of moving
	// as one line.
	if (world.y < mid_y) {
		color = mix(color, foam_color.rgb, layer_front_lift);
		alpha = mix(alpha, foam_color.a, layer_front_lift);
	} else if (world.y >= back_y) {
		color = mix(color, deep_color.rgb, layer_back_shade);
	}
	// Reflection: a *surface* highlight, not a glow filling the body. The crest
	// pixel takes the light, then a couple of hard rows under it, thinning out
	// with depth and scattered per pixel, so it stays pixel art instead of a
	// smooth gradient inside the rectangle.
	float lit = light_at(world);
	if (lit > 0.02) {
		float level = clamp(lit * reflection_strength, 0.0, 1.0);
		if (under_surface < 1.0) {
			color = mix(color, crest_color.rgb, clamp(level * 1.7, 0.0, 1.0));
		} else {
			float rows = floor(under_surface);
			float reach = 1.0 + level * 3.0;
			float fall = clamp(1.0 - (rows - 1.0) / reach, 0.0, 1.0);
			float stepped = floor(fall * 3.0 + 0.5) / 3.0;
			if (hash21(floor(world)) < stepped * level) {
				color = mix(color, crest_color.rgb, 0.7 * level);
			}
		}
		alpha = clamp(alpha + level * 0.12, 0.0, 1.0);
	}
	COLOR = vec4(color, alpha);
}
