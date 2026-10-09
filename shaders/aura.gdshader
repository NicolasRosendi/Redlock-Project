shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;
// Aura de llamas que suben (estado de Despertar).

uniform vec4 color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float strength = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	float n = noise(vec2(uv.x * 10.0, uv.y * 4.0 + TIME * 3.5)) * 0.6 + noise(vec2(uv.x * 22.0, uv.y * 9.0 + TIME * 6.0)) * 0.4;
	// Las llamas se afinan hacia arriba (uv.y = 0 arriba en el cilindro)
	float h = 1.0 - uv.y;
	float flame = smoothstep(h * 1.1 - 0.1, h * 1.1 + 0.25, n);
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	ALBEDO = color.rgb * flame * (0.4 + fres) * strength * (1.0 - h * 0.3);
}
