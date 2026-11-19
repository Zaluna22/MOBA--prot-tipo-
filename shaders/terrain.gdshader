shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
// One draw call for the whole ground. splat: R dirt, G paving, B water, A jungle.
// light: baked painted light (x0.5). tiles: R grass, G dirt, B stones, A soft noise.
uniform sampler2D splat : filter_linear, repeat_disable;
uniform sampler2D light : filter_linear, repeat_disable;
uniform sampler2D tiles : filter_linear_mipmap, repeat_enable;
uniform vec2 origin = vec2(-30.0);
uniform float size = 200.0;
varying vec2 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = (wp - origin) / size;
	vec4 sp = texture(splat, uv);
	vec3 li = texture(light, uv).rgb * 2.0;
	vec4 t1 = texture(tiles, wp / 7.0);
	float st = texture(tiles, wp / 6.5).b;
	float macro = texture(tiles, wp / 53.0).a;
	float jungle = (sp.a - 0.1) / 0.9;
	vec3 grass = mix(vec3(0.08, 0.2, 0.1), vec3(0.24, 0.4, 0.15), clamp(t1.r * 0.8 + macro * 0.45 - 0.1, 0.0, 1.0));
	grass = mix(grass, grass * vec3(0.72, 0.9, 0.95), jungle);
	vec3 dirt = mix(vec3(0.29, 0.21, 0.13), vec3(0.52, 0.41, 0.27), t1.g);
	vec3 stone = mix(vec3(0.2, 0.21, 0.22), mix(vec3(0.42, 0.43, 0.44), vec3(0.6, 0.59, 0.55), macro), st);
	float dirt_w = smoothstep(0.0, 1.0, sp.r + (t1.g - 0.5) * 0.5);
	vec3 c = mix(grass, dirt, clamp(dirt_w, 0.0, 1.0));
	float stone_w = clamp(sp.g * 1.3 + (st - 0.5) * 0.6 - 0.15, 0.0, 1.0);
	c = mix(c, stone, stone_w);
	float w = sp.b * (1.0 - stone_w);
	if (w > 0.02) {
		float n1 = texture(tiles, wp * 0.07 + TIME * vec2(0.025, 0.018)).a;
		float n2 = texture(tiles, wp * 0.11 - TIME * vec2(0.016, 0.03)).a;
		vec3 water = mix(vec3(0.03, 0.13, 0.17), vec3(0.07, 0.27, 0.31), clamp(n1 * 1.4 - 0.2, 0.0, 1.0));
		water += smoothstep(0.62, 0.7, (n1 + n2) * 0.5) * vec3(0.08, 0.16, 0.16);
		float shore = smoothstep(0.25, 0.5, w) * (1.0 - smoothstep(0.5, 0.75, w));
		water = mix(water, vec3(0.62, 0.8, 0.78), shore * smoothstep(0.45, 0.6, n2) * 0.7);
		c *= 1.0 - 0.45 * smoothstep(0.0, 0.4, w);
		c = mix(c, water, smoothstep(0.38, 0.6, w));
	}
	ALBEDO = c * li;
}
