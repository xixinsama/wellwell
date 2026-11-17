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
// How far each ripple carries, in px: the 1/e distance of its swell. WaterField
// measures the water body the impact landed in and hands its half-width over, so
// one landing moves the *whole* body instead of a patch around the impact point.
uniform float ripple_reach_0 = 24.0;
uniform float ripple_reach_1 = 24.0;
uniform float ripple_reach_2 = 24.0;
uniform float ripple_amplitude = 3.6;
uniform float ripple_speed = 64.0;
uniform float ripple_damping = 1.1;
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

// Height of the surface from one impact.
//
// The landing sends a ring train outwards: the pattern is a cosine of how far the
// crest has travelled (`speed` px/s), so the rings visibly leave the impact point,
// and the train fades out at `ripple_damping` per second. The ripple also fades
// with the vertical distance to the surface it was created on, so a splash in one
// pool cannot wobble the surface of another. Purely visual - the height field never
// moves.
//
// The amplitude must not die next to the impact. This ripple is the only thing that
// moves the surface of a settled basin, so an envelope that is gone after a cell or
// two does not read as a quiet ripple: it reads as a hard vertical edge through the
// middle of one basin, with one end wobbling and the rest of the same body frozen
// flat (the old `exp(-distance / (18 + 22 * w))` envelope plus a +-25 px Gaussian on
// the ring front dropped below one rendered pixel about 40 px from the landing).
// `reach` is therefore the measured half-width of the water body the impact landed
// in (WaterField measures it from the simulation), which keeps the swell inside its
// own body and above the one pixel that makes it visible everywhere in that body.
float ripple_offset(vec4 ripple, float reach, float world_x, float world_y) {
	if (ripple.w <= 0.001) {
		return 0.0;
	}
	float vertical = exp(-abs(world_y - ripple.y) / 5.0);
	if (vertical < 0.01) {
		return 0.0;
	}
	float age = ripple.z;
	float distance = abs(world_x - ripple.x);
	float envelope = exp(-distance / max(reach, 1.0));
	float front = ripple_speed * age;
	float wave = cos((distance - front) * 0.8);
	float decay = exp(-age * ripple_damping);
	return wave * envelope * decay * vertical * ripple.w * ripple_amplitude;
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
	float surface_y = field_top + data.r * field_height;
	float ripple = ripple_offset(ripple_0, ripple_reach_0, world.x, surface_y)
		+ ripple_offset(ripple_1, ripple_reach_1, world.x, surface_y)
		+ ripple_offset(ripple_2, ripple_reach_2, world.x, surface_y);
	surface_y += clamp(ripple, -6.0, 6.0);
	float floor_y = field_top + data.g * field_height;
	if (world.y < surface_y || world.y >= floor_y) {
		discard;
	}

	float depth = max(floor_y - surface_y, 1.0);
	float t = clamp((world.y - surface_y) / depth, 0.0, 1.0);
	vec3 color = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 0.8, t));
	float alpha = mix(shallow_color.a, deep_color.a, t);
	float under_surface = world.y - surface_y;

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
