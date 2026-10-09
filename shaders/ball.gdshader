shader_type spatial;
// Balón blanco con 14 parches oscuros (caras y vértices de un cubo).

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 n = normalize(lp);
	vec3 a = abs(n);
	float face = max(a.x, max(a.y, a.z));
	float patches = smoothstep(0.935, 0.95, face);
	patches = max(patches, smoothstep(0.935, 0.95, dot(a, vec3(0.57735))));
	ALBEDO = mix(vec3(0.96), vec3(0.07, 0.07, 0.1), patches);
	ROUGHNESS = 0.45;
}
