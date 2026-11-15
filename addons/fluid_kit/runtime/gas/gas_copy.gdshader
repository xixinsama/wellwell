shader_type canvas_item;

// One channel copy, used to keep the last converged pressure as the initial guess
// for the next step's Jacobi solve (warm start). Without it every step restarts
// from p = 0 and a handful of Jacobi iterations only removes the high frequency
// part of the divergence, leaving the large scale flow compressible.

uniform sampler2D source_texture : filter_nearest, repeat_disable;

void fragment() {
	COLOR = vec4(texture(source_texture, UV).r, 0.0, 0.0, 1.0);
}
