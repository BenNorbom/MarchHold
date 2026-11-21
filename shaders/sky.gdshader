shader_type sky;
render_mode use_quarter_res_pass;

uniform vec3 zenith_color : source_color = vec3(0.22, 0.4, 0.72);
uniform vec3 horizon_color : source_color = vec3(0.68, 0.78, 0.88);
uniform vec3 ground_color : source_color = vec3(0.34, 0.33, 0.3);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.78);
uniform float cloud_cover = 0.45;
uniform float cloud_speed = 0.004;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;

float fbm(vec2 p) {
	float a = 0.0;
	float w = 0.5;
	for (int i = 0; i < 4; i++) {
		a += texture(cloud_noise, p).r * w;
		p = p * 2.03 + vec2(0.17, 0.41);
		w *= 0.5;
	}
	return a;
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);
	vec3 sky = mix(horizon_color, zenith_color, pow(clamp(up, 0.0, 1.0), 0.55));
	vec3 L = LIGHT0_DIRECTION;
	float sd = max(dot(d, L), 0.0);
	// Warm glow around the sun and a brighter horizon toward it.
	sky += sun_color * pow(sd, 8.0) * 0.35 + sun_color * pow(sd, 64.0) * 0.6;
	float low_sun = 1.0 - clamp(L.y * 2.5, 0.0, 1.0);
	sky = mix(sky, sky * vec3(1.15, 0.92, 0.75), low_sun * (1.0 - clamp(up * 3.0, 0.0, 1.0)) * 0.6);
	if (up > 0.0) {
		vec2 uv = d.xz / (d.y + 0.12) * 0.08 + TIME * cloud_speed;
		float c = fbm(uv);
		float cov = smoothstep(1.0 - cloud_cover - 0.1, 1.0 - cloud_cover + 0.25, c);
		float lit = clamp(fbm(uv + L.xz * 0.02) - c + 0.55, 0.0, 1.0);
		vec3 cloud = mix(vec3(0.55, 0.58, 0.64), vec3(1.0, 0.98, 0.94), lit) * (LIGHT0_ENERGY * 0.25 + 0.75);
		cloud = mix(cloud, cloud * sun_color * 1.15, pow(sd, 6.0) * 0.6);
		float fade = smoothstep(0.0, 0.18, up);
		sky = mix(sky, cloud, cov * fade * 0.92);
	}
	if (up < 0.0) {
		sky = mix(horizon_color * 0.9, ground_color, clamp(-up * 4.0, 0.0, 1.0));
	}
	// Sun disk (only in the main pass, not in reflections).
	if (!AT_CUBEMAP_PASS && sd > 0.99965) {
		sky += sun_color * 18.0 * smoothstep(0.99965, 0.9999, sd);
	}
	COLOR = sky;
}
