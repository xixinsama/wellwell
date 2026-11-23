shader_type canvas_item;
render_mode blend_mix;

// A falling water body drawn as a continuous column of water between two
// surfaces, in the same palette as the pool water. This is not a particle
// system and not a separate "waterfall texture": the spill reads as the same
// water that pours over the lip, with downward streaks and foam at the foot.
//
// The quad spans the fall (UV x across the width, y down the drop). World space
// comes from the quad UVs, never from VERTEX.

uniform vec4 shallow_color : source_color = vec4(0.26, 0.66, 0.94, 0.62);
uniform vec4 deep_color : source_color = vec4(0.05, 0.18, 0.42, 0.9);
uniform vec4 crest_color : source_color = vec4(0.85, 0.97, 1.0, 0.95);
uniform vec4 foam_color : source_color = vec4(0.96, 1.0, 1.0, 0.9);
// Flow scroll speed; the field raises it for taller drops.
uniform float flow_speed = 1.0;
// How much of the foot dissolves into foam (0..1).
uniform float foot_foam = 0.6;

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

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);

	// The stream is a little narrower and softer at the edges.
	float edge = smoothstep(0.0, 0.2, uv.x) * (1.0 - smoothstep(0.8, 1.0, uv.x));

	// Two noise layers scrolling down give the falling streaks.
	float streak = value_noise(vec2(uv.x * 9.0, uv.y * 4.0 - TIME * flow_speed * 3.2));
	float fine = value_noise(vec2(uv.x * 23.0 + 7.0, uv.y * 12.0 - TIME * flow_speed * 6.4));

	// Aerated water: lighter than the deep pool, brighter as it falls.
	float aerated = mix(0.35, 0.9, uv.y);
	vec3 color = mix(deep_color.rgb, shallow_color.rgb, aerated);
	color = mix(color, crest_color.rgb, streak * 0.34 + fine * 0.18);

	// Foam at the foot where the fall meets the basin.
	float foot = smoothstep(0.72, 1.0, uv.y);
	color = mix(color, foam_color.rgb, foot * foot_foam);

	float alpha = mix(shallow_color.a, deep_color.a, 1.0 - aerated * 0.55);
	alpha *= edge;
	alpha *= mix(1.0, 0.55, foot);
	// Soften the very top so it joins the lip without a hard seam.
	alpha *= smoothstep(0.0, 0.06, uv.y);
	COLOR = vec4(color, clamp(alpha, 0.0, 1.0));
}
