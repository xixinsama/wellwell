shader_type canvas_item;
render_mode blend_mix, unshaded;

// Full-room darkness pass driven by the light map.
//
// The light map is the room-sized viewport LightField renders: additive 2D
// lights over a black canvas, so it already carries the falloff and the shadows
// cast by the terrain occluders. Ambient is added here instead of being baked
// into the map, so every consumer agrees on the same ambient value.
//
// The dither only bites where the shade is mid-way, so fully lit and fully dark
// pixels stay clean and the falloff reads as pixel art instead of a gradient.
//
// Relief (optional) makes the surface orientation matter:
//
// - the light *direction* is the local gradient of the light map: it points from
//   the shadow towards the source, normalised over `relief_radius_px` pixels;
// - the surface normal comes either from the authored normal buffer (NormalField,
//   r = x / g = y / b = z, flat = (128,128,255)) or from the screen luminance
//   (a band-passed sobel, see derived_normal());
// - `ndl` lifts pixels whose normal faces the source and sinks pixels whose
//   normal faces away, scaled by `relief_strength` and masked by how much light
//   the map already delivers at that pixel.
//
// Only the map's own light is reshaped: the ambient floor and the shadow bounce
// are added afterwards, so a dark side never gains light and the lit core cannot
// stack past white.

uniform sampler2D light_tex : filter_linear, repeat_disable;
// Size of the light map in pixels; the quad covers exactly the same rectangle.
uniform vec2 light_pixels = vec2(320.0, 180.0);
uniform float ambient = 0.55;
uniform vec4 shade_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float dither_strength = 0.4;
// Bounce: light bleeding a few pixels into the shadow, so a cast shadow is dark
// deep inside and lighter towards its silhouette (the light reflecting off the
// lit surfaces next to it).
uniform float bounce = 0.45;
uniform float bounce_radius = 10.0;
// Fuzzy rim: the lit side is pushed outwards by up to this many pixels, using a
// dense noise offset and a maximum (never a subtraction), so light grows hair
// instead of the darkness eating inwards. The inside of a light is untouched.
uniform float rim_fuzz = 2.0;
uniform float rim_fuzz_scale = 2.2;

// Relief. `normal_mode` is 0 flat, 1 derived from the screen, 2 authored.
uniform sampler2D normal_tex : filter_nearest, repeat_disable;
uniform vec2 normal_pixels = vec2(320.0, 180.0);
uniform float normal_mode = 1.0;
uniform float relief_strength = 0.35;
uniform float relief_radius_px = 2.0;
uniform float relief_softness = 0.0;
// Radius of the normal high-pass, in pixels. A baked normal atlas describes a
// *tilted* surface (a bevel around every tile), not only its edges. Shading that
// tilt directly makes a flat wall look like a dome, and because the light direction
// inside a lamp's circle is radial, the dome reads as a glass ball hanging in the
// light. Subtracting the local average normal leaves only the variation (edges,
// bevels, chips), so a wall stays flat.
uniform float relief_average_px = 4.0;
// Opt-in lens: one authored light can bend the light like a convex glass ball.
// Kept as a feature because that accidental look was worth having on one lamp.
uniform vec2 lens_center_px = vec2(-99999.0, -99999.0);
uniform float lens_radius_px = 0.0;
uniform float lens_strength = 0.0;
// Reference direction the ball is lit from, in screen pixels (up and to the right,
// matching the art's light). The ball's own normals are dotted with this, which is
// what makes a bright crescent and a dark crescent instead of a flat bright disc.
uniform vec2 lens_light_dir = vec2(1.6, -1.0);
// The world viewport as it is just before the shade is drawn (terrain, backdrop,
// outline). Only read in derived normal mode. canvas_item shaders have no
// SCREEN_PIXEL_SIZE, so the viewport size is handed over by LightField.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec2 screen_pixels = vec2(320.0, 180.0);

// How much the luminance slope of one screen pixel tilts the derived normal. The
// gradient below is a *difference of differences*, so its magnitude is a fraction
// of a luminance step; this brings the usual 1 px art edge to a useful tilt.
const float DERIVED_NORMAL_SCALE = 8.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise_at(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float light_lum(vec2 px) {
	vec3 light = texture(light_tex, (px + 0.5) / light_pixels).rgb;
	return clamp(dot(light, vec3(0.3, 0.59, 0.11)), 0.0, 1.0);
}

// Light at this pixel, grown outwards by the fuzz: four offset samples taken at
// a noise-driven direction, and only the brightest of them is kept.
float fuzzed_light_lum(vec2 px) {
	float own = light_lum(px);
	if (rim_fuzz <= 0.0) {
		return own;
	}
	vec2 base = px / rim_fuzz_scale;
	for (int index = 0; index < 3; index++) {
		float angle = noise_at(base + float(index) * 37.0) * 6.2831853;
		float reach = (0.55 + 0.45 * noise_at(base * 1.7 + float(index) * 11.0)) * rim_fuzz;
		own = max(own, light_lum(px + vec2(cos(angle), sin(angle)) * reach));
	}
	return own;
}

float bayer4(vec2 p) {
	vec2 q = floor(mod(p, 4.0));
	float inner = mod(3.0 * mod(q.y, 2.0) + 2.0 * mod(q.x, 2.0), 4.0);
	float outer = mod(
		3.0 * floor(mod(q.y, 4.0) * 0.5) + 2.0 * floor(mod(q.x, 4.0) * 0.5),
		4.0
	);
	return (4.0 * inner + outer + 0.5) / 16.0;
}

float screen_lum(vec2 uv) {
	return clamp(dot(texture(screen_tex, uv).rgb, vec3(0.3, 0.59, 0.11)), 0.0, 1.0);
}

vec2 screen_gradient(vec2 uv, vec2 step_uv) {
	return vec2(
		screen_lum(uv + vec2(step_uv.x, 0.0)) - screen_lum(uv - vec2(step_uv.x, 0.0)),
		screen_lum(uv + vec2(0.0, step_uv.y)) - screen_lum(uv - vec2(0.0, step_uv.y))
	);
}

// Screen-space normal from the luminance of the world below the shade.
//
// A plain sobel of the raw screen is dominated by the light falloff itself, which
// is the same field the light direction is measured from: the dot product would
// come out near +1 over the whole lit room and the relief would read as a uniform
// brightness lift. Subtracting the gradient measured `relief_radius_px` away (a
// band-pass, still a couple of taps at design resolution) keeps only the slopes
// the art itself has, so flat falloff stays flat and brick edges, rims and
// texture get a direction. Brightness is treated as height, so the normal is the
// negative slope of the detail: the flank of a raised pixel that faces the lamp
// catches the light, which is what reads as relief instead of as a dent.
vec3 derived_normal(vec2 screen_uv) {
	vec2 pixel = 1.0 / max(screen_pixels, vec2(1.0));
	vec2 fine_step = pixel;
	vec2 coarse_step = pixel * max(relief_radius_px, 2.0);
	vec2 detail = screen_gradient(screen_uv, fine_step) - screen_gradient(screen_uv, coarse_step);
	return normalize(vec3(-detail * DERIVED_NORMAL_SCALE, 1.0));
}

// Local average of the authored normal. Sampled with four cardinal taps at
// `relief_average_px`, which is wide enough to include a whole tile bevel, so a
// tiled wall's own tilt cancels out and only deviations survive.
vec3 averaged_authored_normal(vec2 px) {
	vec2 step_px = vec2(max(relief_average_px, 1.0));
	vec3 total = texture(normal_tex, (px + 0.5) / normal_pixels).rgb * 2.0 - 1.0;
	vec3 sum = total;
	for (int index = 0; index < 4; index++) {
		float angle = float(index) * 1.5707963;
		vec2 offset = vec2(cos(angle), sin(angle)) * step_px;
		vec2 uv = clamp(px + offset + 0.5, vec2(0.0), normal_pixels - vec2(1.0)) / normal_pixels;
		sum += texture(normal_tex, uv).rgb * 2.0 - 1.0;
	}
	return sum * 0.2;
}

// Relief factor in -relief_strength .. +relief_strength for this pixel. `own` is
// the (fuzzed) light the map delivers here; it masks the effect, so a pixel with
// no light cannot gain any and the fog edge keeps its darkness.
float relief_factor(vec2 px, vec2 screen_uv, float own) {
	if (normal_mode < 0.5 || relief_strength <= 0.0) {
		return 0.0;
	}
	vec2 normal_xy = vec2(0.0);
	if (normal_mode > 1.5) {
		vec3 authored = texture(normal_tex, (px + 0.5) / normal_pixels).rgb * 2.0 - 1.0;
		vec3 coarse = averaged_authored_normal(px);
		// High-pass, then rescale: the deviation is a fraction of the full tilt,
		// so without the scale the relief would collapse to nothing.
		normal_xy = (authored - coarse).xy * DERIVED_NORMAL_SCALE;
	} else {
		normal_xy = derived_normal(screen_uv).xy;
	}
	float step_px = max(relief_radius_px, 1.0);
	vec2 gradient = vec2(
		light_lum(px + vec2(step_px, 0.0)) - light_lum(px - vec2(step_px, 0.0)),
		light_lum(px + vec2(0.0, step_px)) - light_lum(px - vec2(0.0, step_px))
	);
	float magnitude = length(gradient);
	if (magnitude < 0.002) {
		// A flat part of the light map has no direction to offer; leave it alone
		// instead of amplifying sampling noise.
		return 0.0;
	}
	// The map's gradient points from the shadow towards the source. Light travels
	// the other way, and a surface whose normal faces the source catches more of
	// it, hence the two negations.
	vec2 light_dir = -gradient / magnitude;
	float ndl = dot(normal_xy, -light_dir);
	// Softness narrows the effect towards the steep faces instead of letting
	// every gentle slope shift the whole room's brightness.
	ndl = sign(ndl) * pow(abs(ndl), 1.0 + clamp(relief_softness, 0.0, 1.0) * 2.0);
	float mask = smoothstep(0.02, 0.35, own);
	return clamp(ndl * relief_strength * mask, -1.0, 1.0);
}

// The opt-in glass ball: inside `lens_radius_px` of the chosen lamp, treat the
// surface as a sphere and shade it with the same light direction the relief uses,
// so one lamp bends the light into a convex, refracting bubble instead of lighting
// a flat wall. Only that light's own circle is affected.
float lens_factor(vec2 px, float own) {
	if (lens_strength <= 0.0 || lens_radius_px <= 0.0) {
		return 0.0;
	}
	vec2 delta = (px - lens_center_px) / lens_radius_px;
	float radius_squared = dot(delta, delta);
	if (radius_squared >= 1.0) {
		return 0.0;
	}
	// Sphere normal: xy bends outward towards the rim, z falls to 0 there.
	vec3 sphere = vec3(delta, sqrt(max(0.0, 1.0 - radius_squared)));
	// Lit from a fixed reference direction, not from the light map's gradient: the
	// gradient inside a lamp points straight at its centre, so dotting with it would
	// only brighten the whole disc equally (a flat white blob, not a ball).
	vec2 reference = normalize(lens_light_dir + vec2(0.0001));
	float ndl = dot(sphere.xy, reference);
	// A hard, darker glass edge: the rim of a sphere turns away from the light.
	float rim = smoothstep(0.78, 1.0, radius_squared);
	return (ndl * 0.8 - rim * 0.45) * lens_strength * smoothstep(0.02, 0.35, own);
}


void fragment() {
	vec2 px = floor(UV * light_pixels);
	float own = fuzzed_light_lum(px);
	// Only the map's contribution is reshaped: ambient and bounce are added below
	// and keep their old behaviour, which is also what keeps the mean in place.
	float relief = relief_factor(px, SCREEN_UV, own);
	float lit = clamp(own * (1.0 + relief), 0.0, 1.0);
	if (bounce > 0.0) {
		// Brightest light within the bounce radius, decaying with distance.
		float bleed = 0.0;
		for (int index = 0; index < 8; index++) {
			float angle = float(index) * 0.7853982;
			vec2 direction = vec2(cos(angle), sin(angle));
			bleed = max(bleed, light_lum(px + direction * bounce_radius) * 0.55);
			bleed = max(bleed, light_lum(px + direction * bounce_radius * 0.5) * 0.8);
		}
		lit = max(lit, bleed * bounce);
	}
	lit = clamp(lit + ambient, 0.0, 1.0);
	// The lens has to bite into the *final* lit value: inside a lamp the light plus
	// the ambient floor already clamps to 1, so any modulation before the add would
	// be swallowed and the ball would be invisible in its own light.
	lit = clamp(lit * (1.0 + lens_factor(px, own)), 0.0, 1.0);

	float dark = 1.0 - lit;
	float band = 1.0 - abs(dark * 2.0 - 1.0);
	dark = mix(dark, step(bayer4(px), dark), dither_strength * band);
	COLOR = vec4(shade_color.rgb, shade_color.a * dark);
}
