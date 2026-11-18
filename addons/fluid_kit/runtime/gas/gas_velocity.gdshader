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
// Vorticity confinement (Fedkiw et al. 2001; GPU Gems 38). The semi-Lagrangian
// step is stable but *dissipative*: every step it averages, so the small curls
// that make smoke look like smoke are smoothed away and the mist ends up as a
// soft veil with no structure of its own. Confinement adds back a force that
// pushes the flow towards the centre of each vortex (along the gradient of the
// vorticity magnitude, crossed with the vorticity), which re-sharpens the curls
// without adding energy to the large scales.
//
//   w     = curl(u) = dv/dx - du/dy
//   N     = normalize(grad |w|)
//   force = epsilon * (N.y, -N.x) * w        (N x w in 2D)
//
// The scale is not physical: it is a modelling knob in "cells per second", tuned
// like the buoyancy. 0 restores the plain dissipative solver.
uniform float vorticity = 0.0;
// The blue channel of this field carries the gas's *detail tracer*: a passive
// scalar that is advected exactly like the velocity and refreshed where the dye is
// thick. The render shader uses it as the wisp pattern, so the mist's texture is
// the gas's own stretched structure instead of a noise texture scrolling over the
// screen. It lives here rather than in the density field because these passes write
// alpha = 1.0: a transparent SubViewport premultiplies the colour by the written
// alpha, so a fourth piece of data in the density field's alpha would silently
// halve the dye every step.
uniform float detail_retention = 1.0;
uniform float detail_refresh = 1.6;
uniform float detail_hz = 6.0;
uniform bool initialize = false;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Detail source: white noise in world cells, re-drawn `detail_hz` times a second.
// Stepping in time rather than scrolling keeps the blotches from crawling; the
// advection below is what makes them move.
float detail_source(vec2 world, float step_index) {
	return hash21(floor(world / cell_size) + vec2(step_index * 37.0, step_index * 71.0));
}

float solid_at(vec2 fuv) {
	vec2 mask_uv = fuv * (field_size / (8.0 * max(mask_cell_count, vec2(1.0))));
	return texture(mask_texture, clamp(mask_uv, vec2(0.0), vec2(1.0))).r;
}

// Scalar curl of the velocity at a cell, as a central difference in cell units.
float curl_at(vec2 fuv, vec2 texel) {
	float v_right = texture(velocity_texture, clamp(fuv + vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).g;
	float v_left = texture(velocity_texture, clamp(fuv - vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).g;
	float u_down = texture(velocity_texture, clamp(fuv + vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).r;
	float u_up = texture(velocity_texture, clamp(fuv - vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).r;
	return 0.5 * ((v_right - v_left) - (u_down - u_up));
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
	float detail = 0.5;
	if (!initialize && solid_at(fuv) < 0.5) {
		vec2 texel = vec2(1.0 / grid_size.x, 1.0 / grid_size.y);
		vec4 advected = texture(velocity_texture, fuv);
		// Semi-Lagrangian: follow the flow backwards and take the value there.
		vec2 back = fuv - advected.rg * delta / grid_size;
		vec4 traced = texture(velocity_texture, clamp(back, vec2(0.0), vec2(1.0)));
		velocity = traced.rg * max(0.0, 1.0 - dissipation * delta);
		detail = mix(0.5, traced.b, clamp(detail_retention, 0.0, 1.0));

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

		if (vorticity > 0.0) {
			// Re-inject the small scales the trace-back just averaged away. Read the
			// curvature of the *current* field (before this step's forces), so the
			// confinement follows the vortices that already exist instead of the
			// impulses injected this frame.
			float w_centre = curl_at(fuv, texel);
			float w_left = curl_at(fuv - vec2(texel.x, 0.0), texel);
			float w_right = curl_at(fuv + vec2(texel.x, 0.0), texel);
			float w_up = curl_at(fuv - vec2(0.0, texel.y), texel);
			float w_down = curl_at(fuv + vec2(0.0, texel.y), texel);
			vec2 gradient = vec2(
				0.5 * (abs(w_right) - abs(w_left)),
				0.5 * (abs(w_down) - abs(w_up))
			);
			float magnitude = length(gradient);
			if (magnitude > 1e-5 && abs(w_centre) > 1e-5) {
				vec2 direction = gradient / magnitude;
				// N x w, with w pointing out of the plane.
				vec2 confinement = vec2(direction.y, -direction.x) * w_centre;
				velocity += confinement * vorticity * delta;
			}
		}

		if (emitter.w > 0.0) {
			float falloff = 1.0 - clamp(distance(world, emitter.xy) / max(emitter.z, 1.0), 0.0, 1.0);
			falloff *= falloff;
			// The emitted gas inherits the emitter's backward velocity, so the
			// trail lags behind the traveller instead of following it.
			velocity = mix(velocity, emitter_velocity / cell_size, falloff * 0.85);
		}

		// Stir fresh detail into the cells that hold gas. The source is world noise
		// re-drawn a few times a second; from here on it is a passive scalar and only
		// the trace-back moves it, so the strokes it leaves follow the flow. The rate
		// is deliberately not gated by how thick the gas is: a thin veil needs its
		// texture as much as a dense puff, and where there is no gas the mist is
		// discarded before the pattern is ever visible.
		float stir = clamp(detail_refresh * delta, 0.0, 0.6);
		if (stir > 0.0) {
			detail = mix(detail, detail_source(world, floor(TIME * detail_hz)), stir);
		}
	}
	COLOR = vec4(velocity, clamp(detail, 0.0, 1.0), 1.0);
}
