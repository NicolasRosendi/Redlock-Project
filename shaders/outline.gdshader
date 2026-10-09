shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
// Contorno estilo cel-shading (casco invertido).

uniform vec4 color : source_color = vec4(0.04, 0.04, 0.07, 1.0);
uniform float thickness = 0.012;

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = color.rgb;
}
