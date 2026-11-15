shader_type canvas_item;

// Density step of the gas solver: advects the three gas channels with the
// divergence-free velocity derived from psi, then applies diffusion, the ambient
// sources, the vent injection and the hero's push.
//
//   R = heavy gas (sinks), G = neutral (drifts), B = light gas (rises)
//
// The velocity is v = curl(psi) + wind + vent jets + the hero's push. The curl
// part is incompressible; the vent and hero terms are local forces that only
// exist inside their radii.

uniform sampler2D density_previous : filter_linear, repeat_disable;
uniform sampler2D psi_current : filter_linear, repeat_disable;
uniform sampler2D mask_texture : filter_nearest, repeat_disable;
uniform vec2 field_size = vec2(320.0, 180.0);
uniform vec2 mask_cell_count = vec2(40.0, 23.0);
uniform float cell_size = 4.0;
uniform float delta = 0.0333333;
uniform float diffusion = 0.12;
uniform float refill = 0.25;
uniform vec3 ambient = vec3(0.5, 0.42, 0.5);
uniform vec2 wind = vec2(7.0, -1.5);
uniform vec2 player_position = vec2(-9999.0);
uniform float push_radius = 34.0;
uniform float push_strength = 1.4;
uniform bool initialize = false;

// Vent slots: xy = outlet position (room local), z = radius, w = rate (density/s).
uniform vec4 vent0 = vec4(-9999.0, -9999.0, 1.0, 0.0);
uniform vec4 vent1 = vec4(-9999.0, -9999.0, 1.0, 0.0);
uniform vec4 vent2 = vec4(-9999.0, -9999.0, 1.0, 0.0);
uniform vec4 vent3 = vec4(-9999.0, -9999.0, 1.0, 0.0);
// xy = direction, z = channel (0 heavy, 1 neutral, 2 light), w = jet speed (px/s).
uniform vec4 vent_dir0 = vec4(1.0, 0.0, 1.0, 0.0);
uniform vec4 vent_dir1 = vec4(1.0, 0.0, 1.0, 0.0);
uniform vec4 vent_dir2 = vec4(1.0, 0.0, 1.0, 0.0);
uniform vec4 vent_dir3 = vec4(1.0, 0.0, 1.0, 0.0);

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

void add_vent(vec4 vent, vec4 info, vec2 world, float dt, inout vec2 velocity, inout vec3 injection) {
	if (vent.w <= 0.0) {
		return;
	}
	float distance_to_vent = distance(world, vent.xy);
	float falloff = 1.0 - clamp(distance_to_vent / max(vent.z, 1.0), 0.0, 1.0);
	if (falloff <= 0.0) {
		return;
	}
	falloff *= falloff;
	velocity += normalize(info.xy + vec2(0.0001)) * info.w * falloff * dt;
	injection += channel_mask(info.z) * vent.w * falloff * dt * 4.0;
}

void fragment() {
	vec2 fuv = UV;
	vec3 result = vec3(0.0);
	if (solid_at(fuv) < 0.5) {
		if (initialize) {
			result = ambient;
		} else {
			vec2 texel = vec2(cell_size / field_size.x, cell_size / field_size.y);
			vec2 world = fuv * field_size;

			float left = texture(psi_current, fuv - vec2(texel.x, 0.0)).r;
			float right = texture(psi_current, fuv + vec2(texel.x, 0.0)).r;
			float up = texture(psi_current, fuv - vec2(0.0, texel.y)).r;
			float down = texture(psi_current, fuv + vec2(0.0, texel.y)).r;
			vec2 velocity = vec2(down - up, left - right) / (2.0 * cell_size) + wind;

			vec3 injection = vec3(0.0);
			add_vent(vent0, vent_dir0, world, delta, velocity, injection);
			add_vent(vent1, vent_dir1, world, delta, velocity, injection);
			add_vent(vent2, vent_dir2, world, delta, velocity, injection);
			add_vent(vent3, vent_dir3, world, delta, velocity, injection);

			// The hero drags the gas and thins it where the body passes.
			vec2 to_hero = world - player_position;
			float distance_to_hero = length(to_hero);
			float push = 1.0 - clamp(distance_to_hero / max(push_radius, 1.0), 0.0, 1.0);
			push *= push;
			vec2 hero_velocity = vec2(0.0);
			if (push > 0.0) {
				hero_velocity = normalize(to_hero + vec2(0.0001)) * push_strength * 240.0 * push;
			}

			vec2 total_velocity = velocity + hero_velocity;
			vec2 back = clamp(fuv - total_velocity * delta / field_size, vec2(0.0), vec2(1.0));
			vec3 density = texture(density_previous, back).rgb;

			vec3 average = (
				texture(density_previous, fuv - vec2(texel.x, 0.0)).rgb
				+ texture(density_previous, fuv + vec2(texel.x, 0.0)).rgb
				+ texture(density_previous, fuv - vec2(0.0, texel.y)).rgb
				+ texture(density_previous, fuv + vec2(0.0, texel.y)).rgb
			) * 0.25;
			density = mix(density, average, clamp(diffusion * delta, 0.0, 0.5));
			density = mix(density, ambient, clamp(refill * delta, 0.0, 0.5));
			density += injection;
			density *= 1.0 - clamp(push * push_strength * delta * 6.0, 0.0, 0.8);
			result = clamp(density, vec3(0.0), vec3(1.0));
		}
	}
	COLOR = vec4(result, 1.0);
}
