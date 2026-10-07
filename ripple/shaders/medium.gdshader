shader_type canvas_item;
// 活膜渲染：从每格的"点亮时刻"重建平滑、圆润的波前，并画出光晕。
// data: RGBA 浮点纹理，R = 年龄（秒，负数 = 即将点亮，99 = 静），G = 是否介质。

uniform sampler2D data : filter_nearest;
uniform vec2 grid = vec2(64.0, 36.0);
uniform float exc = 0.26;
uniform float refr = 1.1;
uniform float speed = 9.0;
uniform float time_s = 0.0;
uniform float pulse = 0.0;      // 全局心跳亮度（结局 / 标题用）
uniform bool smooth_edges = false;   // 结局的心：用解析的心形边缘代替方格边缘
uniform vec2 heart_c = vec2(32.0, 18.0);
uniform vec2 heart_s = vec2(12.5, 11.0);
uniform float dim = 1.0;
uniform vec3 rest_col = vec3(0.075, 0.085, 0.20);
uniform vec3 deep_col = vec3(0.035, 0.04, 0.11);
uniform vec3 hot_col = vec3(1.0, 0.98, 0.92);
uniform vec3 front_col = vec3(0.45, 0.92, 1.0);
uniform vec3 tail_col = vec3(1.0, 0.36, 0.62);
uniform vec3 fade_col = vec3(0.42, 0.24, 0.78);

vec4 cell(ivec2 c) {
	if (c.x < 0 || c.y < 0 || c.x >= int(grid.x) || c.y >= int(grid.y)) {
		return vec4(99.0, 0.0, 0.0, 0.0);
	}
	return texelFetch(data, c, 0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * grid;               // 以格为单位的坐标
	ivec2 base = ivec2(floor(p));

	// ---- 介质遮罩（平滑边缘） ----
	vec2 q = p - 0.5;
	ivec2 i0 = ivec2(floor(q));
	vec2 f = fract(q);
	float m00 = cell(i0).g;
	float m10 = cell(i0 + ivec2(1, 0)).g;
	float m01 = cell(i0 + ivec2(0, 1)).g;
	float m11 = cell(i0 + ivec2(1, 1)).g;
	float mask_lin = mix(mix(m00, m10, f.x), mix(m01, m11, f.x), f.y);
	float own = cell(base).g;
	float mask = own;
	float edge_a = 1.0;
	if (smooth_edges) {
		float u = (p.x - heart_c.x) / heart_s.x;
		float v = -(p.y - heart_c.y) / heart_s.y;
		float a = u * u + v * v - 1.0;
		float hf = a * a * a - u * u * v * v * v;
		mask = step(hf, 0.0);
		edge_a = smoothstep(0.012, -0.012, hf);
		mask = max(mask, step(0.001, edge_a));
	}

	// ---- 用邻域重建平滑年龄：age(p) = max(age_s - |p - s| / v) ----
	// 只混合"同一道波"的样本：先取本格年龄作参照（本格是静就取邻近最年轻的），
	// 年龄相差太大的样本属于更早的一道波，不参与，否则紧跟着的两道波会互相污染。
	float ref = cell(base).r;
	if (cell(base).g < 0.5 || ref > exc + refr) {
		ref = 99.0;
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				vec4 s = cell(base + ivec2(dx, dy));
				if (s.g > 0.5 && s.r < 50.0) ref = min(ref, s.r);
			}
		}
	}
	float age = -1000.0;
	float halo = 0.0;
	float tail_halo = 0.0;
	for (int dy = -2; dy <= 2; dy++) {
		for (int dx = -2; dx <= 2; dx++) {
			ivec2 c = base + ivec2(dx, dy);
			vec4 s = cell(c);
			if (s.g < 0.5 || s.r > 50.0) continue;
			vec2 sc = vec2(c) + 0.5;
			float d = length(p - sc);
			float a = s.r - d / speed;
			if (abs(s.r - ref) < 0.45) age = max(age, a);
			// 光晕：亮着的格向四周发光
			float e = clamp(1.0 - s.r / exc, 0.0, 1.0) * step(0.0, s.r);
			halo += e * exp(-d * d * 0.55);
			float tr = clamp(1.0 - (s.r - exc) / refr, 0.0, 1.0) * step(exc, s.r);
			tail_halo += tr * tr * exp(-d * d * 0.9);
		}
	}
	if (age < -100.0) age = 99.0;

	vec3 col = vec3(0.0);
	float alpha = 0.0;

	if (mask > 0.5) {
		// 静：深靛蓝 + 细格纹 + 缓慢的焦散
		vec2 fc = fract(p);
		float grid_line = smoothstep(0.06, 0.0, min(min(fc.x, 1.0 - fc.x), min(fc.y, 1.0 - fc.y)));
		float n = noise(p * 0.35 + vec2(time_s * 0.15, -time_s * 0.1));
		float n2 = noise(p * 0.9 - vec2(time_s * 0.22, time_s * 0.05));
		vec3 base_col = mix(deep_col, rest_col, 0.55 + 0.45 * n);
		base_col += vec3(0.05, 0.07, 0.16) * pow(n2, 3.0) * 0.8;
		base_col += vec3(0.08, 0.1, 0.22) * grid_line * 0.35;
		base_col *= 1.0 + pulse * 0.6;
		col = base_col;
		alpha = 0.94;

		if (age < 50.0) {
			if (age < 0.0) {
				// 前沿预亮
				float pre = smoothstep(-0.16, 0.0, age);
				col = mix(col, front_col * 0.9, pre * 0.6);
			} else if (age < exc) {
				float e = 1.0 - age / exc;
				vec3 c = mix(front_col, hot_col, smoothstep(0.35, 1.0, e));
				col = mix(col, c * 1.25, smoothstep(0.0, 0.25, e) * 0.95 + 0.05);
			} else if (age < exc + refr) {
				float r = (age - exc) / refr;
				vec3 c = mix(tail_col, fade_col, smoothstep(0.0, 0.4, r));
				c = mix(c, base_col, smoothstep(0.3, 0.95, r));
				float k = pow(1.0 - r, 1.8);
				col = mix(col, c, 0.15 + 0.85 * k);
			}
		}
		// 介质上表面的水面高光
		float above = cell(base + ivec2(0, -1)).g;
		if (above < 0.5) {
			float fy = fract(p.y);
			col += vec3(0.35, 0.5, 1.0) * smoothstep(0.18, 0.0, fy) * 0.35;
		}
	}

	// 光晕叠加（介质内外都有，外面形成辉光）
	vec3 glow = front_col * halo * 0.28 + tail_col * tail_halo * 0.05;
	if (mask > 0.5) {
		col += glow * 0.6;
	} else {
		float g = clamp(halo * 0.22 + tail_halo * 0.04, 0.0, 0.85);
		col = (front_col * halo * 0.22 + tail_col * tail_halo * 0.04) / max(g, 0.001);
		alpha = g;
		// 介质边缘柔化
		alpha = max(alpha, mask_lin * 0.0);
	}

	if (mask > 0.5) alpha *= edge_a;
	COLOR = vec4(col * dim, alpha * mix(1.0, dim, 0.5));
}
