shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 color : source_color = vec4(0.3, 0.9, 0.4, 0.35);

void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = color.rgb;
	ALPHA = color.a * (0.55 + rim * 0.6);
}
