shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_always, shadows_disabled;
// Cuerpo de energía del dragón: escamas, flujo de energía, brillo de borde y
// desvanecimiento hacia la cola.

uniform vec4 color_a : source_color = vec4(1.0, 0.35, 0.1, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.9, 0.45, 1.0);
uniform float fade = 1.0;
uniform float body = 1.0;
uniform float intensity = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	// Escamas en hileras desplazadas
	vec2 sc = vec2(uv.x * 70.0, uv.y * 9.0);
	sc.x += step(1.0, mod(floor(sc.y), 2.0)) * 0.5;
	vec2 f = fract(sc) - 0.5;
	float scale_edge = smoothstep(0.32, 0.5, length(f * vec2(1.0, 1.5)));
	float flow = noise(vec2(uv.x * 14.0 - TIME * 4.0, uv.y * 5.0 + TIME));
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	vec3 col = mix(color_a.rgb, color_b.rgb, clamp(flow * 0.7 + fres * 0.6, 0.0, 1.0));
	col += color_b.rgb * scale_edge * 0.55 * body;
	// Vientre más claro (lado inferior del tubo)
	col += color_b.rgb * smoothstep(0.6, 1.0, sin(uv.y * 6.2831)) * 0.25 * body;
	float tail = mix(1.0, 1.0 - smoothstep(0.55, 1.0, uv.x), body);
	// Núcleo de color saturado y borde brillante (el glow del entorno lo realza)
	ALBEDO = col * (0.75 + fres * 0.9) * intensity;
	ALPHA = clamp((0.72 + fres * 0.28 + scale_edge * 0.1) * fade * tail, 0.0, 1.0);
}
