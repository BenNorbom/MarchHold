shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D blade_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint_a : source_color = vec3(0.5, 0.6, 0.27);
uniform vec3 tint_b : source_color = vec3(0.7, 0.68, 0.38);
uniform vec3 player_pos = vec3(0.0);
uniform float fade_start = 26.0;
uniform float fade_end = 38.0;

varying float tipness;
varying vec3 tint;
varying float fade;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tipness = UV.y < 0.5 ? 1.0 - UV.y * 2.0 : 0.0;
	tipness = 1.0 - UV.y;
	float t = TIME * 1.7 + wp.x * 0.13 + wp.z * 0.11;
	vec3 sway = vec3(sin(t) + sin(t * 2.3) * 0.3, 0.0, cos(t * 0.9) * 0.6) * 0.12 * tipness;
	// Bend away from the commander's feet.
	vec3 away = wp - player_pos;
	float d = length(away.xz);
	if (d < 1.2) {
		sway.xz += normalize(away.xz + vec2(0.001)) * (1.2 - d) * 0.5 * tipness;
	}
	VERTEX += (inverse(MODEL_MATRIX) * vec4(sway, 0.0)).xyz;
	tint = mix(tint_a, tint_b, INSTANCE_CUSTOM.x);
	fade = 1.0 - smoothstep(fade_start, fade_end, length(wp.xz - player_pos.xz));
}

void fragment() {
	vec4 c = texture(blade_tex, UV);
	ALPHA = c.a * fade;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = c.rgb * tint * mix(0.7, 1.15, tipness);
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.5) * tint;
	AO = 1.0;
	AO_LIGHT_AFFECT = 0.0;
}
