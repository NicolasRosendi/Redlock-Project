shader_type spatial;
// Césped con franjas y líneas reglamentarias dibujadas proceduralmente.

uniform vec2 half_size = vec2(52.5, 34.0);
uniform float stripes = 14.0;
uniform vec3 grass_a : source_color = vec3(0.17, 0.52, 0.2);
uniform vec3 grass_b : source_color = vec3(0.14, 0.45, 0.17);
uniform float line_w = 0.12;
uniform float box_depth = 16.5;
uniform float box_width = 40.3;
uniform float small_depth = 5.5;
uniform float small_width = 18.3;
uniform float circle_r = 9.15;
uniform float spot_dist = 11.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line(float d) {
	float aa = fwidth(d);
	return 1.0 - smoothstep(line_w * 0.5, line_w * 0.5 + aa, abs(d));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 a = abs(p);
	float sw = 2.0 * half_size.x / stripes;
	float stripe = mod(floor((p.x + half_size.x) / sw), 2.0);
	vec3 col = mix(grass_a, grass_b, stripe);
	col *= 0.93 + 0.07 * hash(floor(p * 5.0));
	bool outside = a.x > half_size.x + line_w || a.y > half_size.y + line_w;
	if (outside) {
		col *= 0.8;
	}
	float l = 0.0;
	if (!outside) {
		l = max(l, line(a.x - half_size.x) * step(a.y, half_size.y + line_w * 0.5));
		l = max(l, line(a.y - half_size.y) * step(a.x, half_size.x + line_w * 0.5));
		l = max(l, line(p.x) * step(a.y, half_size.y));
		l = max(l, line(length(p) - circle_r));
		l = max(l, 1.0 - smoothstep(0.18, 0.24, length(p)));
		float bx = half_size.x - box_depth;
		l = max(l, line(a.x - bx) * step(a.y, box_width * 0.5));
		l = max(l, line(a.y - box_width * 0.5) * step(bx, a.x));
		float sx = half_size.x - small_depth;
		l = max(l, line(a.x - sx) * step(a.y, small_width * 0.5));
		l = max(l, line(a.y - small_width * 0.5) * step(sx, a.x));
		vec2 spot = vec2(a.x - (half_size.x - spot_dist), p.y);
		l = max(l, 1.0 - smoothstep(0.14, 0.2, length(spot)));
		l = max(l, line(length(spot) - circle_r) * (1.0 - step(bx, a.x)));
	}
	ALBEDO = mix(col, vec3(0.94), clamp(l, 0.0, 1.0));
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
