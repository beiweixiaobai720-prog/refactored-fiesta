shader_type canvas_item;
// 背景：深夜蓝到梅紫的渐变、缓慢漂移的柔光团和细小的尘点。

uniform float time_s = 0.0;
uniform float pulse = 0.0;
uniform vec3 top_col = vec3(0.025, 0.03, 0.07);
uniform vec3 bottom_col = vec3(0.075, 0.04, 0.10);
uniform vec3 blob_col = vec3(0.16, 0.10, 0.32);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(top_col, bottom_col, smoothstep(0.0, 1.0, uv.y));
	vec2 p = uv * vec2(16.0, 9.0);
	float n = noise(p * 0.45 + vec2(time_s * 0.03, time_s * 0.02));
	n += 0.5 * noise(p * 0.9 - vec2(time_s * 0.05, 0.0));
	col += blob_col * pow(n / 1.5, 3.0) * 0.9;
	// 尘点
	vec2 sp = uv * vec2(320.0, 180.0);
	vec2 cellp = floor(sp);
	float h = hash(cellp);
	if (h > 0.985) {
		vec2 fp = fract(sp) - 0.5;
		float tw = 0.5 + 0.5 * sin(time_s * (1.0 + h * 3.0) + h * 40.0);
		col += vec3(0.6, 0.7, 1.0) * smoothstep(0.25, 0.0, length(fp)) * tw * 0.35;
	}
	// 暗角
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 0.9;
	col *= 1.0 + pulse * 0.5;
	COLOR = vec4(col, 1.0);
}
