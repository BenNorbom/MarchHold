shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 vein_color : source_color = vec3(1.0);
uniform float vein_amount = 0.0;
uniform float vein_metal = 0.0;
uniform float scale = 0.35;
uniform vec3 moss_color : source_color = vec3(0.32, 0.38, 0.18);

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 tw = pow(abs(wn), vec3(4.0));
	tw /= (tw.x + tw.y + tw.z);
	vec3 alb = texture(albedo_tex, wp.zy * scale).rgb * tw.x + texture(albedo_tex, wp.xz * scale).rgb * tw.y + texture(albedo_tex, wp.xy * scale).rgb * tw.z;
	vec3 arm = texture(arm_tex, wp.zy * scale).rgb * tw.x + texture(arm_tex, wp.xz * scale).rgb * tw.y + texture(arm_tex, wp.xy * scale).rgb * tw.z;
	alb *= tint;
	// Moss on top surfaces.
	float moss = smoothstep(0.6, 0.95, wn.y) * smoothstep(0.35, 0.7, texture(noise_tex, wp.xz * 0.3).r);
	alb = mix(alb, moss_color * (0.7 + 0.5 * alb), moss * 0.7);
	float metal = 0.0;
	if (vein_amount > 0.0) {
		float v = texture(noise_tex, wp.xz * 0.45 + wp.y * 0.3).r;
		float vein = smoothstep(0.5, 0.56, v) * (1.0 - smoothstep(0.6, 0.66, v));
		vein = max(vein, smoothstep(0.72, 0.8, texture(noise_tex, wp.xy * 0.8).r));
		alb = mix(alb, vein_color, vein * vein_amount);
		metal = vein * vein_metal;
	}
	ALBEDO = alb;
	AO = arm.r;
	ROUGHNESS = mix(arm.g, 0.45, metal);
	METALLIC = metal;
	NORMAL_MAP = texture(normal_tex, wp.xz * scale).rgb;
}
