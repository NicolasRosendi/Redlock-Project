shader_type spatial;
// Grada con público: puntos de colores que "saltan" levemente.

uniform float density = 3.0;
uniform float excitement = 0.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.31, 289.13))) * 13758.5453);
}

void fragment() {
	vec2 cell = floor(vec2(wp.x + wp.z, wp.y) * density);
	float h = hash(cell);
	vec3 shirt = vec3(hash(cell + 1.3), hash(cell + 7.1), hash(cell + 3.7));
	shirt = mix(shirt, vec3(0.15, 0.3, 0.85), step(0.55, h));
	shirt = mix(shirt, vec3(0.85, 0.15, 0.2), step(0.85, h));
	vec2 f = fract(vec2(wp.x + wp.z, wp.y) * density + vec2(0.0, sin(TIME * (6.0 + h * 6.0)) * 0.08 * (0.3 + excitement)));
	float person = step(length(f - vec2(0.5, 0.45)), 0.33);
	ALBEDO = mix(vec3(0.12, 0.12, 0.15), shirt * 0.8, person);
	ROUGHNESS = 1.0;
}
