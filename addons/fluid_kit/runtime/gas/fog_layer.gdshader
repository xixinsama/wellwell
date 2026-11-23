shader_type canvas_item;
render_mode blend_mix;

// Draws the three-gas field.
//
// The field texture (R = heavy, G = neutral, B = light) comes from the GPU
// simulation viewport, or from a CPU fallback image. Each gas has its own color
// and opacity, so the density difference is visible: the heavy gas pools on the
// floor in warm rust, the neutral gas drifts through the room in cool cyan and
// the light gas gathers under the ceiling in pale gold.
//
// World space comes from the quad's UVs, never from VERTEX (a canvas_item
// fragment's VERTEX is not guaranteed to stay in the item's local space). The
// solid mask is one texel per terrain tile, so the gas is cut exactly at the
// collision silhouette. Keep the light falloff in sync with
// FogGrid.sample_light().

uniform sampler2D gas_texture : filter_linear, repeat_disable;
uniform sampler2D solid_texture : filter_nearest, repeat_disable;
uniform vec2 field_origin = vec2(0.0, 180.0);
uniform vec2 field_size = vec2(320.0, 180.0);
uniform vec2 mask_cell_count = vec2(40.0, 23.0);

uniform vec4 heavy_color : source_color = vec4(0.86, 0.5, 0.26, 1.0);
uniform vec4 neutral_color : source_color = vec4(0.42, 0.78, 0.92, 1.0);
uniform vec4 light_color : source_color = vec4(1.0, 0.93, 0.64, 1.0);
uniform vec3 gas_alpha = vec3(0.46, 0.26, 0.2);
uniform vec3 gas_noise_scale = vec3(0.09, 0.17, 0.3);
uniform vec4 lit_tint : source_color = vec4(1.0, 0.9, 0.72, 1.0);
uniform float base_alpha = 0.55;
uniform float light_alpha = 0.9;
uniform float noise_amount = 0.6;

uniform vec4 light0 = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec4 light0_color : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform vec4 light1 = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec4 light1_color : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform vec4 light2 = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec4 light2_color : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform vec4 light3 = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec4 light3_color : source_color = vec4(1.0, 0.8, 0.5, 1.0);

// The room light map (see LightField). It is taken as a *maximum* with the four
// authored lights above instead of replacing them: the authored lights keep the
// wide, soft falloff the mist already had, and the map adds the lantern's real
// shape and the shadows walls cast, so gas behind a wall no longer glows.
uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform vec2 light_pixels = vec2(320.0, 180.0);
uniform float map_gain = 1.0;
uniform float map_weight = 1.4;

// Stylised threshold ("thresholding" in the post-mortem): the gas opacity is
// quantised into `stipple_steps` levels and which level a pixel lands on is decided
// by a per-pixel threshold in [0, 1), so the fade is dithered by grain instead of
// by a smooth gradient that bands.
//
// `stipple_mode` picks the threshold source:
//   0 = the 4x4 ordered Bayer tile (legacy, kept for A/B captures),
//   1 = the 64x64 blue-noise tile (resources/textures/blue_noise_64.png),
//   2 = white noise (a hash of the pixel), the cheap reference.
// The blue-noise tile is the shipped default: it is aperiodic, so it has no
// lattice for the 4x upscale (or the CRT slot mask) to line up with, and its
// spatial spectrum is empty at low frequencies, so it also does not blotch.
uniform sampler2D stipple_tex : filter_nearest, repeat_enable;
uniform float stipple_mode = 1.0;
uniform float stipple_steps = 32.0;

// How much of the gas's own advected detail is used as the wisp pattern. The
// tracer lives in the blue channel of the velocity field (see
// gas_velocity.gdshader); 0 falls back to the screen-space noise below, which is
// what the CPU fog grid still needs.
uniform sampler2D detail_tex : filter_linear, repeat_disable;
uniform float detail_amount = 0.0;
// The tracer comes out of the solver with a narrow spread (the trace-back is a
// blur), so its contrast is expanded around the neutral 0.5 before it is used as a
// wisp. Without this the mist is *smoother* than the noise it replaced (measured:
// opacity gradient 0.0046 against 0.0065).
uniform float detail_contrast = 3.5;

// Volumetric self-shadowing. The density is treated as a participating medium and
// marched towards the key light: a pixel whose line of sight to the lantern crosses
// thick gas is darker than the skin of the cloud facing it. That is the 2D stand-in
// for the ray-marched volume the effect is after, and it is what stops the mist
// from looking like a flat sheet of noise painted on the room.
//
//   transmittance = exp(-sum(rho) * volume_shadow)
//   color        *= mix(1.0, transmittance, volume_weight)
//
// `volume_light` is the key light's world position (xy) and, in z, the fraction of
// the effect already faded out (0 = off).
uniform vec4 volume_light = vec4(-9999.0, -9999.0, 0.0, 0.0);
uniform float volume_shadow = 0.9;
uniform float volume_weight = 1.0;
uniform float volume_step_px = 7.0;
uniform int volume_taps = 6;

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

// 4x4 ordered dither in [0, 1), built as M4 = 4 * M2(inner) + M2(outer), the same
// construction the light shade, bloom, backdrop and fog dithers use.
//
// This exact form matters. A previous version computed the value from the low bits
// of the position directly (x&1 * 8 + y&1 * 4 + ...), which is the Bayer matrix
// with its bit order reversed: all eight low thresholds land in the even columns
// and all eight high ones in the odd columns. The dither then resolves into
// vertical stripes two world pixels wide (measured: a 15/1000 opacity difference
// between neighbouring columns, i.e. ~8% of the gas layer where the cloud is
// faint) instead of a dispersed 2D stipple, which reads as a seam running down the
// gas. The recursive form keeps every column of the tile summing to the same
// amount, so no column is systematically denser and the stripe is gone.
//
// It is kept only as `stipple_mode = 0`, for comparison: a balanced Bayer tile is
// still a *lattice*. At the opacity a fading mist passes through, the tile lit by
// the level underneath is a regular 2x2 checkerboard of design pixels, so on the
// 4x screen every column becomes a dashed line and the fade reads as a woven grid
// or a set of bars instead of a mist. The blue-noise tile above is what removes
// the lattice while keeping the same mean opacity.
float bayer4(vec2 p) {
	vec2 q = floor(mod(p, 4.0));
	float inner = mod(3.0 * mod(q.y, 2.0) + 2.0 * mod(q.x, 2.0), 4.0);
	float outer = mod(
		3.0 * floor(mod(q.y, 4.0) * 0.5) + 2.0 * floor(mod(q.x, 4.0) * 0.5),
		4.0
	);
	return (4.0 * inner + outer + 0.5) / 16.0;
}

// The threshold a world pixel gets, in [0, 1). Declared after the kernels it
// chooses between: GLSL has no forward declarations here.
float stipple_at(vec2 world_px) {
	vec2 snapped = floor(world_px);
	if (stipple_mode < 0.5) {
		return bayer4(snapped);
	}
	if (stipple_mode < 1.5) {
		return texture(stipple_tex, (snapped + 0.5) / 64.0).r;
	}
	return hash21(snapped);
}

float light_term(vec2 world, vec4 light, vec4 tint, inout vec3 sum) {
	if (light.w <= 0.001) {
		return 0.0;
	}
	float distance = length(world - light.xy);
	float falloff = pow(clamp(1.0 - distance / max(light.z, 1.0), 0.0, 1.0), 1.6) * light.w;
	sum += tint.rgb * falloff;
	return falloff;
}

void fragment() {
	// QuadMesh UVs run bottom-up, the field is authored top-down.
	vec2 quad_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 world = field_origin + quad_uv * field_size;
	vec2 mask_uv = quad_uv * (field_size / (8.0 * mask_cell_count));
	if (texture(solid_texture, mask_uv).r > 0.5) {
		discard;
	}

	vec4 field = texture(gas_texture, clamp(quad_uv, vec2(0.0), vec2(0.9999)));
	vec3 gas = field.rgb;
	// The wisp pattern rides *inside* the field: the simulation advects the blue
	// channel of the velocity field with the dye, so what the eye reads as smoke
	// detail is the gas's own stretched structure rather than a noise texture
	// scrolling over the screen. Where no GPU field is running (the CPU fallback has
	// no such channel) the old screen-space noise is kept, so previews still have
	// texture.
	vec3 wisp;
	if (detail_amount > 0.0) {
		float tracer = texture(detail_tex, clamp(quad_uv, vec2(0.0), vec2(0.9999))).b;
		float expanded = 0.5 + (tracer - 0.5) * detail_contrast;
		wisp = vec3(mix(0.5, clamp(expanded, 0.0, 1.0), clamp(detail_amount, 0.0, 1.0)));
	} else {
		wisp = vec3(
			value_noise(world * gas_noise_scale.x + vec2(TIME * 0.06, -TIME * 0.04)),
			value_noise(world * gas_noise_scale.y - vec2(TIME * 0.11, TIME * 0.03)),
			value_noise(world * gas_noise_scale.z + vec2(TIME * 0.18, -TIME * 0.08))
		);
	}
	gas *= mix(vec3(1.0 - noise_amount), vec3(1.0 + noise_amount), wisp);

	float heavy = clamp(gas.r, 0.0, 1.0);
	float neutral = clamp(gas.g, 0.0, 1.0);
	float light = clamp(gas.b, 0.0, 1.0);
	float total = heavy + neutral + light;
	if (total <= 0.01) {
		discard;
	}
	float opacity = heavy * gas_alpha.x + neutral * gas_alpha.y + light * gas_alpha.z;
	vec3 color = (heavy_color.rgb * heavy + neutral_color.rgb * neutral + light_color.rgb * light) / max(total, 0.001);

	float lit = 0.0;
	vec3 light_sum = vec3(0.0);
	lit += light_term(world, light0, light0_color, light_sum);
	lit += light_term(world, light1, light1_color, light_sum);
	lit += light_term(world, light2, light2_color, light_sum);
	lit += light_term(world, light3, light3_color, light_sum);
	// The light map is bound room-local (LightField hands it over at the room's
	// origin), so it must be sampled with the quad's own UV, not with `world`: for a
	// room at chunk (3,0) `world` starts at 960 and the whole UV range clamped to the
	// map's last column, which is why the mist ignored the walls' shadows.
	vec2 map_uv = clamp(quad_uv * (field_size / max(light_pixels, vec2(1.0))), vec2(0.0), vec2(0.9999));
	vec3 map_sample = texture(light_tex, map_uv).rgb;
	float map_lit = clamp(dot(map_sample, vec3(0.3, 0.59, 0.11)) * map_gain, 0.0, 1.0);
	if (map_lit > 0.0) {
		lit = max(lit, map_lit * map_weight);
		light_sum = max(light_sum, map_sample * map_weight);
	}

	color = mix(color, lit_tint.rgb * color * 1.6, clamp(lit * 0.55, 0.0, 0.8));
	color += light_sum * 0.22;

	float alpha = clamp(opacity * (base_alpha + light_alpha * min(lit, 1.5)), 0.0, 0.92);

	// Volume pass: how much gas sits between this pixel and the key light. The taps
	// are deliberately coarse (one per 7 world px): the density field is 4 px per
	// cell, so a finer step would only re-sample the same texel.
	//
	// The effect is gated by the layer's own opacity, because it is a self-shadowing
	// term: a nearly transparent veil is optically thin towards the lantern and must
	// not darken, while a dense puff has depth. Without the gate the faint mist lost
	// a third of its brightness (measured straight-colour luminance 0.764 -> 0.514),
	// which is the state the fade artefact lives in.
	if (volume_light.z > 0.0) {
		vec2 to_light = volume_light.xy - world;
		float reach = length(to_light);
		if (reach > volume_step_px) {
			vec2 dir = to_light / reach;
			float blocked = 0.0;
			for (int tap = 1; tap <= 6; tap++) {
				if (tap > volume_taps) {
					break;
				}
				vec2 probe = world + dir * (float(tap) * volume_step_px);
				vec2 probe_uv = clamp((probe - field_origin) / field_size, vec2(0.0), vec2(0.9999));
				vec3 probe_gas = texture(gas_texture, probe_uv).rgb;
				blocked += max(probe_gas.r, max(probe_gas.g, probe_gas.b));
			}
			float transmittance = exp(-blocked * volume_shadow);
			float depth = mix(1.0, 0.45 + 0.55 * transmittance, clamp(volume_weight, 0.0, 1.0));
			color *= mix(1.0, depth, clamp(alpha * 6.0, 0.0, 1.0));
		}
	}

	// 32 steps instead of 8: at the 4x pixel scale the 1/8 steps read as a
	// 32 steps instead of 8: at the 4x pixel scale the 1/8 steps read as a
	// screen-door pattern over the backdrop; finer steps keep the banding
	// guard without the visible stipple.
	alpha = floor(alpha * stipple_steps + stipple_at(world)) / stipple_steps;
	if (alpha <= 0.02) {
		discard;
	}
	COLOR = vec4(color, alpha);
}
