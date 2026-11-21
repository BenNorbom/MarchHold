shader_type spatial;
render_mode cull_back;

// Splat: R rock, G dirt, B forest floor, A dry grass.
uniform sampler2D splat : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float map_size = 1024.0;
uniform vec3 grass_tint : source_color = vec3(0.86, 1.0, 0.74);
uniform vec3 dry_tint : source_color = vec3(1.0, 0.93, 0.72);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hblend(float base, float h, float w) {
	// Height-based blend: crisper, more natural transitions than a linear mix.
	return smoothstep(0.0, 1.0, clamp((base * 1.6 - 0.3) + (h - 0.5) * 0.6 * w, 0.0, 1.0));
}

void fragment() {
	vec2 muv = wpos.xz / map_size;
	vec4 sp = texture(splat, muv);
	float n_macro = texture(noise_tex, wpos.xz * 0.0035).r;
	float n_mid = texture(noise_tex, wpos.xz * 0.021 + 0.31).r;
	float n_fine = texture(noise_tex, wpos.xz * 0.19).r;

	// Grass, sampled at two scales to hide tiling.
	vec2 uvg = wpos.xz * 0.22;
	vec2 uvg2 = wpos.xz * 0.061 + vec2(0.37, 0.71);
	vec3 alb = mix(texture(grass_alb, uvg).rgb, texture(grass_alb, uvg2).rgb, 0.4);
	alb *= mix(grass_tint * 0.86, grass_tint * 1.08, n_macro);
	alb = mix(alb, alb * dry_tint, clamp(sp.a + (n_mid - 0.5) * 0.6, 0.0, 1.0));
	vec3 nrm = texture(grass_nrm, uvg).rgb;
	vec3 arm = texture(grass_arm, uvg).rgb;

	float wf = hblend(sp.b, n_mid, 1.0);
	if (wf > 0.01) {
		vec2 uvf = wpos.xz * 0.2;
		alb = mix(alb, texture(forest_alb, uvf).rgb * 0.9, wf);
		nrm = mix(nrm, texture(forest_nrm, uvf).rgb, wf);
		arm = mix(arm, texture(forest_arm, uvf).rgb, wf);
	}
	float wd = hblend(sp.g, n_fine * 0.6 + n_mid * 0.4, 1.0);
	if (wd > 0.01) {
		vec2 uvd = wpos.xz * 0.24;
		alb = mix(alb, texture(dirt_alb, uvd).rgb, wd);
		nrm = mix(nrm, texture(dirt_nrm, uvd).rgb, wd);
		arm = mix(arm, texture(dirt_arm, uvd).rgb, wd);
	}
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	float wr = clamp(max(sp.r, smoothstep(0.33, 0.5, slope)) + (n_fine - 0.5) * 0.25, 0.0, 1.0);
	wr = smoothstep(0.35, 0.65, wr);
	if (wr > 0.01) {
		vec3 tw = pow(abs(wnrm), vec3(4.0));
		tw /= (tw.x + tw.y + tw.z);
		float s = 0.11;
		vec3 r = texture(rock_alb, wpos.zy * s).rgb * tw.x + texture(rock_alb, wpos.xz * s).rgb * tw.y + texture(rock_alb, wpos.xy * s).rgb * tw.z;
		alb = mix(alb, r * vec3(0.72, 0.7, 0.66), wr);
		nrm = mix(nrm, texture(rock_nrm, wpos.xz * s).rgb, wr * tw.y + wr * 0.4);
		arm = mix(arm, texture(rock_arm, wpos.xz * s).rgb, wr);
	}
	ALBEDO = alb;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	ROUGHNESS = clamp(arm.g * 1.05, 0.35, 1.0);
	METALLIC = 0.0;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 1.1;
}
