shader_type canvas_item;
// Líneas de velocidad estilo anime para los cortes de técnicas especiales.

uniform float intensity = 0.0;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

float hash(float x) {
	return fract(sin(x * 91.7) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float ang = atan(uv.y, uv.x);
	float r = length(uv);
	float id = floor(ang * 38.0 + floor(TIME * 18.0) * 3.0);
	float n = hash(id);
	float on = step(0.62, n) * smoothstep(0.22 + n * 0.12, 0.6, r);
	float vignette = smoothstep(0.35, 0.85, r) * 0.35;
	COLOR = vec4(line_color.rgb, clamp(on * line_color.a + vignette, 0.0, 1.0) * intensity);
}
