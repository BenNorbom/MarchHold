shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float wind_strength = 0.35;
uniform float alpha_cut = 0.42;
uniform float translucency = 0.45;

varying float shade;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float t = TIME * 1.3 + wp.x * 0.05 + wp.z * 0.07;
	vec3 sway = vec3(sin(t), 0.0, cos(t * 0.8)) * 0.04 * h * wind_strength;
	sway += vec3(sin(TIME * 4.1 + wp.x * 0.9 + wp.y), sin(TIME * 3.3 + wp.z), cos(TIME * 3.7 + wp.y * 1.3)) * 0.06 * wind_strength * COLOR.g;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(sway, 0.0)).xyz;
	// Inner leaves are darker (self shadowing).
	shade = mix(0.55, 1.0, COLOR.r);
}

void fragment() {
	vec4 c = texture(leaf_tex, UV);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALBEDO = c.rgb * tint * shade;
	ROUGHNESS = 0.72;
	SPECULAR = 0.35;
	BACKLIGHT = vec3(translucency) * c.rgb * tint;
}
