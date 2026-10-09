shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
// Red de portería en cuadrícula, ignorando el eje normal del panel.

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = abs((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 f = abs(fract(wp * 4.0) - 0.5);
	vec3 lines = step(vec3(0.42), f) * (1.0 - step(vec3(0.5), n));
	float l = max(lines.x, max(lines.y, lines.z));
	ALBEDO = vec3(0.95);
	ALPHA = l * 0.8 + 0.03;
}
