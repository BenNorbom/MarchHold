shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float uv_scale = 0.5;
uniform float normal_depth = 1.0;
uniform float metal = 0.0;
uniform float rough_mul = 1.0;
uniform float emission = 0.0;
uniform vec3 emission_color : source_color = vec3(1.0, 0.5, 0.15);

// Per instance: construction height in local metres, and soot from damage.
instance uniform float build_level = 999.0;
instance uniform float damage = 0.0;

varying vec3 lpos;
varying vec3 wp;

void vertex() {
	lpos = VERTEX;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (lpos.y > build_level) {
		discard;
	}
	vec2 uv = UV * uv_scale;
	vec3 alb = texture(albedo_tex, uv).rgb * tint;
	// Weathering: darker near the ground.
	alb *= mix(0.78, 1.0, clamp(lpos.y * 0.8, 0.0, 1.0));
	alb = mix(alb, alb * vec3(0.18, 0.16, 0.15), damage);
	vec3 arm = texture(arm_tex, uv).rgb;
	ALBEDO = alb;
	AO = arm.r;
	ROUGHNESS = clamp(arm.g * rough_mul, 0.05, 1.0);
	METALLIC = max(arm.b, metal);
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	EMISSION = emission_color * emission;
	// A bright seam where construction is still going on.
	if (build_level < 900.0 && lpos.y > build_level - 0.12) {
		ALBEDO = mix(ALBEDO, vec3(0.75, 0.62, 0.42), 0.6);
	}
}
