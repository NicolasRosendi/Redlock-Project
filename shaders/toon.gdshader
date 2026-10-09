shader_type spatial;
// Sombreado anime: dos tonos (luz/sombra tintada), brillo especular duro y
// luz de borde. Se combina con outline.gdshader como siguiente pasada.

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 shade_color : source_color = vec4(0.55, 0.6, 0.85, 1.0);
uniform float shade_strength = 0.42;
uniform float rim_strength = 0.35;
uniform float spec_size = 0.035;
uniform float spec_strength = 0.35;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = albedo.rgb * rim * rim_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, 0.06, ndl) * ATTENUATION;
	vec3 band = mix(shade_color.rgb * shade_strength, vec3(1.0), lit);
	DIFFUSE_LIGHT += band * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float sp = smoothstep(1.0 - spec_size, 1.0 - spec_size + 0.012, dot(NORMAL, h)) * lit;
	SPECULAR_LIGHT += sp * LIGHT_COLOR / PI * spec_strength;
}
