shader_type spatial;
render_mode cull_back;

// UV2: x = limb (0 body, 1 head, 2 left arm, 3 right arm, 4 left leg, 5 right leg)
//      y = region (0 skin, 1 tunic, 2 trousers, 3 leather, 4 hair, 5 wood, 6 iron, 7 bronze, 8 gold, 9 tinted, 13 side colour)
// INSTANCE_CUSTOM: x = animation, y = phase, z = amount, w = per-person seed
//   A fighting pose (x >= 16, see battle_pose.gd) packs riding, lean and twist into x,
//   and has y = right arm angle, z = left arm angle.
// INSTANCE_COLOR: tunic / tint colour

uniform sampler2D cloth_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool painted_crowd = false;
uniform vec3 crowd_dye : source_color = vec3(0.5); // side colour of a painted crowd
uniform bool is_animal = false;

varying vec3 base_color;
varying float rough;
varying float metal;
varying flat int prop_region;
varying vec3 lp;

mat3 rot_x(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_y(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }
mat3 rot_z(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void vertex() {
	int limb = int(UV2.x + 0.5);
	int region = int(UV2.y + 0.5);
	prop_region = region;
	int anim = int(INSTANCE_CUSTOM.x + 0.5);
	float ph = INSTANCE_CUSTOM.y;
	float amt = INSTANCE_CUSTOM.z;
	float seed = INSTANCE_CUSTOM.w;
	vec3 v = VERTEX;
	float rest_y = v.y;
	vec3 n = NORMAL;
	if (!is_animal && anim != 13) {
		vec3 hip = vec3(0.0, 0.95, 0.0);
		vec3 sh_l = vec3(0.21, 1.42, 0.0);
		vec3 sh_r = vec3(-0.21, 1.42, 0.0);
		vec3 neck = vec3(0.0, 1.5, 0.0);
		float s = sin(ph);
		float arm_l = 0.0; float arm_r = 0.0; float leg_l = 0.0; float leg_r = 0.0;
		float lean = 0.0; float twist = 0.0; float spread = 0.0; float arm_out = 0.0; float head = 0.0;
		if (anim >= 16) { // fighting
			int bits = anim - 16;
			lean = float((bits >> 1) & 15) * 0.05 - 0.2;
			twist = float((bits >> 5) & 31) * 0.05 - 0.8;
			arm_r = ph; arm_l = amt;
			if ((bits & 1) == 1) { leg_l = -1.2; leg_r = -1.2; spread = 0.45; }
		} else if (anim == 1 || anim == 14 || anim == 15 || anim == 9) { // walk, carry
			leg_l = s * 0.45 * amt; leg_r = -leg_l;
			arm_l = -s * 0.35 * amt; arm_r = -arm_l;
			if (anim == 9) { arm_l = -0.46; arm_r = -0.46; }
			if (anim == 14) { arm_r = -0.42; }
			if (anim == 15) { arm_r = -0.12; }
		} else if (anim == 2) { // run
			leg_l = s * 0.8; leg_r = -leg_l; arm_l = -s * 0.7; arm_r = -arm_l; lean = 0.18;
		} else if (anim == 3) { // chop
			float k = 0.5 + 0.5 * sin(ph);
			arm_r = -2.4 + 1.9 * k; arm_l = arm_r + 0.2; twist = 0.25 * (k - 0.5); lean = 0.12 * k;
		} else if (anim == 4) { // hammer
			arm_r = -1.5 + 0.75 * sin(ph); arm_l = -0.5; lean = 0.15;
		} else if (anim == 5) { // dig
			float k = 0.5 + 0.5 * sin(ph);
			arm_r = -1.4 + 0.9 * k; arm_l = arm_r; lean = 0.2 + 0.25 * k;
		} else if (anim == 6) { // pick / graze
			lean = 0.55; arm_r = -0.7 + 0.25 * sin(ph); arm_l = -0.6 - 0.25 * sin(ph); head = 0.3;
		} else if (anim == 7) { // melee
			float k = fract(ph / 6.2831);
			float sw = k < 0.35 ? k / 0.35 : 1.0 - (k - 0.35) / 0.65;
			arm_r = -2.2 + 2.1 * (1.0 - sw); arm_l = -0.6; twist = -0.35 + 0.6 * (1.0 - sw); lean = 0.1;
		} else if (anim == 8) { // shoot
			arm_l = -1.5; arm_r = -1.35; twist = 0.35; arm_out = 0.15;
		} else if (anim == 10) { // ride
			leg_l = -1.2; leg_r = -1.2; spread = 0.45; arm_l = -0.55; arm_r = -0.55;
		} else if (anim == 12) { // load a gun
			arm_r = -1.0 + 0.5 * sin(ph); arm_l = -1.0 - 0.5 * sin(ph); lean = 0.3;
		} else { // idle
			arm_l = 0.04 * sin(ph * 0.35); arm_r = -arm_l;
		}
		mat3 body = rot_y(twist) * rot_x(lean);
		if (limb == 4 || limb == 5) {
			float a = limb == 4 ? leg_l : leg_r;
			float sp = limb == 4 ? spread : -spread;
			mat3 r = rot_x(a) * rot_z(sp);
			v = r * (v - hip) + hip;
			n = r * n;
		} else {
			if (limb == 2 || limb == 3) {
				vec3 piv = limb == 2 ? sh_l : sh_r;
				float bend = anim == 9 ? -1.4 : (anim == 14 && limb == 3 ? -2.35 : (anim == 15 && limb == 3 ? -0.40 : 0.0));
				vec3 elbow = vec3(piv.x * 1.095, 1.10, 0.02);
				mat3 elbow_rotation = rot_x(bend * (1.0 - smoothstep(1.08,1.13,v.y)));
				v = elbow_rotation * (v - elbow) + elbow;
				n = elbow_rotation * n;
				float a = limb == 2 ? arm_l : arm_r;
				float o = limb == 2 ? arm_out : -arm_out;
				mat3 r = rot_x(a) * rot_z(o);
				v = r * (v - piv) + piv;
				n = r * n;
			} else if (limb == 1) {
				mat3 r = rot_x(head);
				v = r * (v - neck) + neck;
				n = r * n;
			}
			v = body * (v - hip) + hip;
			n = body * n;
		}
		if (anim == 1 || anim == 2 || anim == 9 || anim == 14 || anim == 15) {
			v.y += abs(cos(ph)) * 0.035 * (anim == 2 ? 2.0 : amt);
		}
	} else if (is_animal) {
		// Quadruped: 0 body, 1 neck+head, 2..5 legs (FL, FR, BL, BR), 6 tail.
		float s = sin(ph);
		float amp = anim == 2 ? 0.7 : (anim == 1 ? 0.38 : 0.0);
		vec3 fl = vec3(0.0, 0.95, 0.55);
		vec3 bl = vec3(0.0, 0.95, -0.5);
		if (limb >= 2 && limb <= 5) {
			float a = (limb == 2 || limb == 5) ? s * amp : -s * amp;
			vec3 piv = (limb <= 3) ? fl : bl;
			mat3 r = rot_x(a);
			v = r * (v - piv) + piv;
			n = r * n;
		} else if (limb == 1) {
			float g = anim == 6 ? 1.05 : (anim == 2 ? -0.15 : 0.08 * s);
			vec3 piv = vec3(0.0, 1.25, 0.7);
			mat3 r = rot_x(g);
			v = r * (v - piv) + piv;
			n = r * n;
		} else if (limb == 6) {
			vec3 piv = vec3(0.0, 1.2, -0.75);
			mat3 r = rot_z(0.25 * sin(ph * 0.7 + seed * 6.0));
			v = r * (v - piv) + piv;
			n = r * n;
		}
		if (anim == 2) {
			v.y += abs(cos(ph)) * 0.12;
		}
	}
	VERTEX = v;
	NORMAL = normalize(n);
	lp = v;
	if (painted_crowd) {
		// The crowd meshes have no masks, so find garments by limb and rest height.
		float garment;
		if (limb == 0) { garment = 1.0; }
		else if (limb == 1) { garment = 0.0; }
		else if (limb <= 3) { garment = smoothstep(1.0, 1.14, rest_y); }
		else { garment = smoothstep(0.42, 0.62, rest_y); }
		float folds = clamp(0.5 + 0.9 * sqrt(dot(COLOR.rgb, vec3(0.30, 0.59, 0.11))), 0.0, 1.15);
		float red_trim = smoothstep(0.35, 0.5, COLOR.r) * (1.0 - smoothstep(0.05, 0.09, COLOR.g));
		base_color = mix(COLOR.rgb, vec3(0.16, 0.08, 0.035), red_trim);
		base_color = mix(base_color, crowd_dye * mix(1.0, 0.88, seed) * folds, garment);
		rough = 0.9;
		metal = 0.0;
	} else {
		// Colours by region, varied per person.
		float h1 = hash(seed * 91.7 + 3.1);
		float h2 = hash(seed * 47.3 + 1.7);
		vec3 skin = mix(vec3(0.84, 0.66, 0.52), vec3(0.46, 0.31, 0.22), h1 * h1);
		vec3 hair = mix(vec3(0.12, 0.08, 0.05), vec3(0.55, 0.38, 0.2), h2);
		vec3 col = COLOR.rgb;
		rough = 0.85;
		metal = 0.0;
		if (region == 0) { col = skin; rough = 0.6; }
		else if (region == 1) { col = COLOR.rgb * mix(0.85, 1.1, h2); }
		else if (region == 2) { col = mix(vec3(0.26, 0.22, 0.17), vec3(0.4, 0.36, 0.28), h1); }
		else if (region == 3) { col = vec3(0.2, 0.13, 0.08); rough = 0.7; }
		else if (region == 4) { col = hair; }
		else if (region == 5) { col = vec3(0.42, 0.29, 0.17); rough = 0.75; }
		else if (region == 6) { col = vec3(0.56, 0.57, 0.6); rough = 0.35; metal = 0.9; }
		else if (region == 7) { col = vec3(0.72, 0.48, 0.24); rough = 0.35; metal = 0.9; }
		else if (region == 8) { col = vec3(0.95, 0.74, 0.28); rough = 0.25; metal = 1.0; }
		if (region == 10) { col = vec3(0.68,0.49,0.28); }
		if (region == 11) { col = vec3(0.40,0.095,0.055); }
		if (is_animal) {
			col = COLOR.rgb;
			if (region == 4) { col = COLOR.rgb * 0.35; }
			if (region == 3) { col = vec3(0.08, 0.07, 0.06); }
			if (region == 0) { col = mix(COLOR.rgb, vec3(0.9, 0.88, 0.85), 0.6); }
			rough = 0.7;
		}
		base_color = col;
	}
}

void fragment() {
	float n = painted_crowd ? 0.64 : texture(cloth_noise, lp.xy * 3.1 + lp.zy * 2.3).r;
	ALBEDO = base_color * mix(0.86, 1.08, n);
	if (prop_region == 12) {
		ALBEDO = texture(bark_tex, UV * vec2(1.8, 1.1)).rgb;
	} else if (prop_region == 10) {
		float rings = cos(UV.y * 93.0);
		ALBEDO *= 0.84 + 0.16 * rings;
	}
	ROUGHNESS = rough;
	METALLIC = metal;
}
