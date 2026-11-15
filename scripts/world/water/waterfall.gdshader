shader_type canvas_item;
render_mode blend_mix;

// The sheet of water pouring over a spill lip. A quad with the falling height:
// UV (0,0) is the lip, UV (1,1) the impact point. Vertical lanes scroll down
// and break into white streaks; the top and bottom edges fade out.

uniform vec4 water_color : source_color = vec4(0.3, 0.7, 0.96, 0.7);
uniform vec4 foam_color : source_color = vec4(0.9, 0.99, 1.0, 0.95);
uniform float flow_speed = 1.0;
uniform float lane_count = 6.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	// QuadMesh UVs run bottom-up: v = 0 is the impact point, v = 1 the lip.
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	float x = uv.x * lane_count;
	float lane = floor(x);
	float jitter = hash21(vec2(lane, 3.0));
	float phase = fract(uv.y * -2.0 + TIME * 2.6 * flow_speed + jitter);
	float streak = smoothstep(0.30, 0.5, phase) * smoothstep(0.95, 0.7, phase);
	float body = 0.52 + 0.3 * hash21(vec2(lane, 11.0));
	vec3 color = mix(water_color.rgb, foam_color.rgb, streak * 0.85);
	float alpha = water_color.a * (body + streak * 0.5);
	alpha *= smoothstep(0.0, 0.08, uv.y);
	alpha *= smoothstep(1.0, 0.86, uv.y);
	if (alpha < 0.02) {
		discard;
	}
	COLOR = vec4(color, alpha);
}
