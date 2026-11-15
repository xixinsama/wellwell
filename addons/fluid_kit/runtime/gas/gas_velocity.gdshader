shader_type canvas_item;

// Navier-Stokes pass 1: semi-Lagrangian self-advection of the velocity field,
// then the external forces (buoyancy from the three gas densities, vent jets and
// the hero's push). The result is the intermediate velocity u* that the pressure
// projection makes divergence free.
//
// Velocity is stored in CELLS PER SECOND, so the divergence and pressure passes
// can work with a grid spacing of exactly 1 cell.

uniform sampler2D velocity_texture : filter_linear, repeat_disable;
uniform sampler2D density_texture : filter_linear, repeat_disable;
uniform sampler2D mask_texture : filter_nearest, repeat_disable;
uniform vec2 grid_size = vec2(80.0, 45.0);
uniform vec2 mask_cell_count = vec2(40.0, 23.0);
uniform vec2 field_size = vec2(320.0, 180.0);
uniform float cell_size = 4.0;
uniform float delta = 0.0166667;
// Fraction of the velocity lost per second while advecting.
uniform float dissipation = 0.4;
// Downward / upward acceleration per unit density, in cells per second squared.
uniform float buoyancy_heavy = 60.0;
uniform float buoyancy_light = 75.0;
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
// One-shot radial blast: xy = centre (room local), z = radius (px), w = kick
// (cells per second) already faded by the caller.
uniform vec4 impulse = vec4(-9999.0, -9999.0, 0.0, 0.0);
// Moving obstacle: xy = centre, zw = half extents (px). It drags the gas along.
uniform vec4 mover = vec4(-9999.0, -9999.0, 0.0, 0.0);
uniform vec2 mover_velocity = vec2(0.0);
uniform float mover_active = 0.0;
// Moving trail emitter: xy = centre (room local), z = radius (px), w = rate.
uniform vec4 emitter = vec4(-9999.0, -9999.0, 0.0, 0.0);
uniform vec2 emitter_velocity = vec2(0.0);
// Kinematic viscosity in 1/s: blends each velocity cell towards its four
// neighbours. 0 = inviscid, higher = thicker, calmer gas.
uniform float viscosity = 0.0;
uniform bool initialize = false;

float solid_at(vec2 fuv) {
	vec2 mask_uv = fuv * (field_size / (8.0 * max(mask_cell_count, vec2(1.0))));
	return texture(mask_texture, clamp(mask_uv, vec2(0.0), vec2(1.0))).r;
}

void add_vent(vec4 vent, vec4 info, vec2 world, inout vec2 velocity) {
	if (vent.w <= 0.0) {
		return;
	}
	float falloff = 1.0 - clamp(distance(world, vent.xy) / max(vent.z, 1.0), 0.0, 1.0);
	if (falloff <= 0.0) {
		return;
	}
	falloff *= falloff;
	velocity += normalize(info.xy + vec2(0.0001)) * (info.w / cell_size) * falloff * delta * 3.0;
}

void fragment() {
	vec2 fuv = UV;
	vec2 velocity = vec2(0.0);
	if (!initialize && solid_at(fuv) < 0.5) {
		vec2 texel = vec2(1.0 / grid_size.x, 1.0 / grid_size.y);
		vec2 current = texture(velocity_texture, fuv).rg;
		// Semi-Lagrangian: follow the flow backwards and take the value there.
		vec2 back = fuv - current * delta / grid_size;
		velocity = texture(velocity_texture, clamp(back, vec2(0.0), vec2(1.0))).rg;
		velocity *= max(0.0, 1.0 - dissipation * delta);

		vec3 density = texture(density_texture, fuv).rgb;
		velocity.y += buoyancy_heavy * density.r * delta;
		velocity.y -= buoyancy_light * density.b * delta;

		vec2 world = fuv * field_size;
		add_vent(vent0, vent_dir0, world, velocity);
		add_vent(vent1, vent_dir1, world, velocity);
		add_vent(vent2, vent_dir2, world, velocity);
		add_vent(vent3, vent_dir3, world, velocity);

		vec2 to_hero = world - player_position;
		float push = 1.0 - clamp(length(to_hero) / max(push_radius, 1.0), 0.0, 1.0);
		push *= push;
		velocity += normalize(to_hero + vec2(0.0001)) * push_strength * 55.0 * push * delta;

		if (impulse.w > 0.0) {
			vec2 blast = world - impulse.xy;
			float ring = 1.0 - clamp(length(blast) / max(impulse.z, 1.0), 0.0, 1.0);
			ring *= ring;
			velocity += normalize(blast + vec2(0.0001)) * impulse.w * ring;
		}

		if (mover_active > 0.5) {
			vec2 offset = world - mover.xy;
			vec2 q = abs(offset) - mover.zw;
			float outside = length(max(q, vec2(0.0)));
			float inside = min(max(q.x, q.y), 0.0);
			float distance_to_box = outside + inside;
			float influence = 1.0 - clamp((distance_to_box + 6.0) / 24.0, 0.0, 1.0);
			influence *= influence;
			velocity += mover_velocity / cell_size * influence * 2.4;
			velocity += normalize(offset + vec2(0.0001)) * 10.0 * influence;
		}

		if (viscosity > 0.0) {
			vec2 neighbors = (
				texture(velocity_texture, clamp(fuv - vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).rg
				+ texture(velocity_texture, clamp(fuv + vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).rg
				+ texture(velocity_texture, clamp(fuv - vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).rg
				+ texture(velocity_texture, clamp(fuv + vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).rg
			) * 0.25;
			velocity = mix(velocity, neighbors, clamp(viscosity * delta, 0.0, 0.2));
		}

		if (emitter.w > 0.0) {
			float falloff = 1.0 - clamp(distance(world, emitter.xy) / max(emitter.z, 1.0), 0.0, 1.0);
			falloff *= falloff;
			// The emitted gas inherits the emitter's backward velocity, so the
			// trail lags behind the traveller instead of following it.
			velocity = mix(velocity, emitter_velocity / cell_size, falloff * 0.85);
		}
	}
	COLOR = vec4(velocity, 0.0, 1.0);
}
