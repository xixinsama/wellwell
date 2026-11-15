shader_type canvas_item;

// Navier-Stokes passive scalar step: the three gas densities are advected by the
// projected (divergence free) velocity. Diffusion is a four neighbour blend, the
// ambient source slowly refills the room, vents inject their channel and the hero
// thins the gas where the body passes.
//
//   R = heavy gas (sinks), G = neutral (drifts), B = light gas (rises)

uniform sampler2D density_texture : filter_linear, repeat_disable;
uniform sampler2D velocity_texture : filter_linear, repeat_disable;
uniform sampler2D mask_texture : filter_nearest, repeat_disable;
uniform vec2 grid_size = vec2(80.0, 45.0);
uniform vec2 mask_cell_count = vec2(40.0, 23.0);
uniform vec2 field_size = vec2(320.0, 180.0);
uniform float cell_size = 4.0;
uniform float delta = 0.0166667;
uniform float diffusion = 0.25;
uniform float refill = 0.35;
uniform vec3 ambient = vec3(0.28, 0.22, 0.32);
// Drift added to the projected velocity, in cells per second.
uniform vec2 wind = vec2(1.5, -0.3);
uniform vec2 player_position = vec2(-9999.0);
uniform float push_radius = 34.0;
uniform float push_strength = 1.4;
uniform vec4 vent0 = vec4(-9999.0, -9999.0, 1.0, 0.0);
uniform vec4 vent1 = vec4(-9999.0, -9999.0, 1.0, 0.0);
uniform vec4 vent2 = vec4(-9999.0, -9999.0, 1.0, 0.0);
uniform vec4 vent3 = vec4(-9999.0, -9999.0, 1.0, 0.0);
uniform vec4 vent_dir0 = vec4(1.0, 0.0, 1.0, 0.0);
uniform vec4 vent_dir1 = vec4(1.0, 0.0, 1.0, 0.0);
uniform vec4 vent_dir2 = vec4(1.0, 0.0, 1.0, 0.0);
uniform vec4 vent_dir3 = vec4(1.0, 0.0, 1.0, 0.0);
// A moving trail emitter: xy = centre (room local), z = radius (px), w = rate
// (density per second). `emitter_velocity` is the initial velocity given to the
// gas, `emitter_channel` selects heavy/neutral/light.
uniform vec4 emitter = vec4(-9999.0, -9999.0, 0.0, 0.0);
uniform vec2 emitter_velocity = vec2(0.0);
uniform float emitter_channel = 1.0;
// Exponential fade of the gas per second (0 = never fades). This is what makes a
// trail dissolve instead of hanging in the room forever.
uniform float decay = 0.0;
// Explosion: xy = centre (room local), z = radius (px), w = density added.
uniform vec4 impulse = vec4(-9999.0, -9999.0, 0.0, 0.0);
// Moving obstacle: xy = centre, zw = half extents (px). It displaces the gas.
uniform vec4 mover = vec4(-9999.0, -9999.0, 0.0, 0.0);
uniform vec2 mover_velocity = vec2(0.0);
uniform float mover_active = 0.0;
uniform bool initialize = false;

float solid_at(vec2 fuv) {
	vec2 mask_uv = fuv * (field_size / (8.0 * max(mask_cell_count, vec2(1.0))));
	return texture(mask_texture, clamp(mask_uv, vec2(0.0), vec2(1.0))).r;
}

vec3 channel_mask(float channel) {
	if (channel < 0.5) {
		return vec3(1.0, 0.0, 0.0);
	}
	if (channel < 1.5) {
		return vec3(0.0, 1.0, 0.0);
	}
	return vec3(0.0, 0.0, 1.0);
}

void add_vent(vec4 vent, vec4 info, vec2 world, inout vec3 injection) {
	if (vent.w <= 0.0) {
		return;
	}
	float falloff = 1.0 - clamp(distance(world, vent.xy) / max(vent.z, 1.0), 0.0, 1.0);
	if (falloff <= 0.0) {
		return;
	}
	falloff *= falloff;
	injection += channel_mask(info.z) * vent.w * falloff * delta * 4.0;
}

void fragment() {
	vec2 fuv = UV;
	vec3 density = vec3(0.0);
	if (solid_at(fuv) < 0.5) {
		if (initialize) {
			density = ambient;
		} else {
			vec2 texel = vec2(1.0 / grid_size.x, 1.0 / grid_size.y);
			vec2 velocity = texture(velocity_texture, fuv).rg + wind;
			vec2 back = clamp(fuv - velocity * delta / grid_size, vec2(0.0), vec2(1.0));
			density = texture(density_texture, back).rgb;

			vec3 average = (
				texture(density_texture, fuv - vec2(texel.x, 0.0)).rgb
				+ texture(density_texture, fuv + vec2(texel.x, 0.0)).rgb
				+ texture(density_texture, fuv - vec2(0.0, texel.y)).rgb
				+ texture(density_texture, fuv + vec2(0.0, texel.y)).rgb
			) * 0.25;
			density = mix(density, average, clamp(diffusion * delta, 0.0, 0.5));
			density = mix(density, ambient, clamp(refill * delta, 0.0, 0.5));

			vec2 world = fuv * field_size;
			vec3 injection = vec3(0.0);
			add_vent(vent0, vent_dir0, world, injection);
			add_vent(vent1, vent_dir1, world, injection);
			add_vent(vent2, vent_dir2, world, injection);
			add_vent(vent3, vent_dir3, world, injection);
			density += injection;

			vec2 to_hero = world - player_position;
			float push = 1.0 - clamp(length(to_hero) / max(push_radius, 1.0), 0.0, 1.0);
			push *= push;
			density *= 1.0 - clamp(push * push_strength * delta * 6.0, 0.0, 0.8);

			if (impulse.w > 0.0) {
				float flash = 1.0 - clamp(distance(world, impulse.xy) / max(impulse.z, 1.0), 0.0, 1.0);
				flash *= flash;
				density += vec3(impulse.w * flash);
			}

			if (mover_active > 0.5) {
				vec2 offset = world - mover.xy;
				vec2 q = abs(offset) - mover.zw;
				float outside = length(max(q, vec2(0.0)));
				float inside = min(max(q.x, q.y), 0.0);
				float distance_to_box = outside + inside;
				float carve = 1.0 - smoothstep(-2.0, 3.0, distance_to_box);
				density *= 1.0 - carve * 0.9;
			}

			if (emitter.w > 0.0) {
				float falloff = 1.0 - clamp(distance(world, emitter.xy) / max(emitter.z, 1.0), 0.0, 1.0);
				falloff *= falloff;
				density += channel_mask(emitter_channel) * emitter.w * falloff * delta * 5.0;
			}

			density *= max(0.0, 1.0 - decay * delta);
		}
	}
	COLOR = vec4(clamp(density, vec3(0.0), vec3(1.0)), 1.0);
}
