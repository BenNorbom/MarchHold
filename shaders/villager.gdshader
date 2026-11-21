shader_type spatial;
render_mode cull_back;
uniform sampler2D fabric : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap;
uniform vec4 dye : source_color;
uniform bool plain_linen = false;
uniform vec4 complexion : source_color;
void fragment() {
	vec3 texel = texture(fabric, UV).rgb;
	// Baked masks follow the fabric and the diagonal faction trim through skinning.
	vec3 cloth = mix(texel, texel * (0.65 + 1.4 * dye.rgb), COLOR.r * 0.62);
	float linen_mask = 0.0;
	if (plain_linen) {
		float folds = 0.74 + 0.36 * sqrt(dot(texel, vec3(0.30,0.59,0.11)));
		float checked_wool = smoothstep(1.6, 2.6, texel.r / max(0.012, texel.g)) * (1.0 - smoothstep(0.035, 0.11, texel.g));
		float blue_cloth = smoothstep(1.1, 1.9, texel.b / max(0.012, texel.r));
		float garment_area = 1.0 - smoothstep(0.26, 0.65, COLOR.b);
		linen_mask = max(COLOR.r, garment_area * max(blue_cloth, checked_wool));
		vec3 linen = mix(vec3(0.43,0.32,0.20), dye.rgb * 0.48 + vec3(0.11), 0.29);
		cloth = mix(cloth, linen * folds, linen_mask);
	}
	ALBEDO = mix(cloth, (0.18 + dot(texel, vec3(0.30, 0.59, 0.11))) * dye.rgb, COLOR.g * 0.80)
		* mix(vec3(1.0), complexion.rgb, COLOR.b);
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = mix(0.52, 0.15, linen_mask);
	ROUGHNESS = 0.86;
}
