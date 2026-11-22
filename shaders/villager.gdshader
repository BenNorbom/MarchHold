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
	// Only the fabric's shading is kept, so its own hue can't muddy the side's colour.
	float folds = clamp(0.5 + 0.9 * sqrt(dot(texel, vec3(0.30, 0.59, 0.11))), 0.0, 1.15);
	vec3 cloth = texel;
	float linen_mask = 0.0;
	if (plain_linen) {
		float checked_wool = smoothstep(1.6, 2.6, texel.r / max(0.012, texel.g)) * (1.0 - smoothstep(0.035, 0.11, texel.g));
		float blue_cloth = smoothstep(1.1, 1.9, texel.b / max(0.012, texel.r));
		float garment_area = 1.0 - smoothstep(0.26, 0.65, COLOR.b);
		linen_mask = max(COLOR.r, garment_area * max(blue_cloth, checked_wool));
		// The baked red boots and hat band would read as Rook's side: make them leather.
		float red_trim = smoothstep(0.25, 0.4, texel.r) * (1.0 - smoothstep(0.03, 0.06, texel.g));
		cloth = mix(cloth, vec3(0.16, 0.08, 0.035) * folds, red_trim);
	}
	cloth = mix(cloth, dye.rgb * folds, max(COLOR.r, linen_mask));
	ALBEDO = mix(cloth, mix(dye.rgb, vec3(1.0), 0.22) * folds, COLOR.g * 0.80)
		* mix(vec3(1.0), complexion.rgb, COLOR.b);
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = mix(0.52, 0.15, linen_mask);
	ROUGHNESS = 0.86;
}
