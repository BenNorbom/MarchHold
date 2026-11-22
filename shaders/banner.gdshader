shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

// A side's banner. The cloth swings around its pole to lie across the line of
// sight, so it never disappears edge-on. UV.x runs from the pole to the tail.

uniform vec3 dye : source_color = vec3(0.5);

void vertex() {
	vec3 pole = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec2 to_cam = CAMERA_POSITION_WORLD.xz - pole.xz;
	vec2 away = to_cam / max(length(to_cam), 0.001);
	vec3 across = vec3(away.y, 0.0, -away.x);
	vec3 toward = vec3(away.x, 0.0, away.y);
	float along = length(VERTEX.xz - pole.xz);
	float ph = UV.x * 6.0 - TIME * 4.0 + pole.x + pole.z;
	float wave = sin(ph) * UV.x;
	VERTEX = vec3(pole.x, VERTEX.y, pole.z) + across * along + toward * wave * 0.14 * size;
	VERTEX.y += (sin(ph * 0.7) * 0.05 - 0.07) * UV.x * size;
	NORMAL = normalize(toward - across * cos(ph) * UV.x * 0.5);
}

void fragment() {
	vec3 col = mix(dye, vec3(0.85, 0.72, 0.42), 1.0 - step(0.09, UV.x));
	ALBEDO = col;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	ROUGHNESS = 0.9;
	// A little glow keeps the colour readable against the sun.
	EMISSION = col * 0.1;
}
