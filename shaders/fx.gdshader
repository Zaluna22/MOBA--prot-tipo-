shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// 0 ground ring/nova (flat plane), 1 glow sprite, 2 fire sprite, 3 vertical beam
uniform int mode = 0;
uniform vec4 col : source_color = vec4(1.0);
uniform float alpha = 1.0;
uniform float ringr = 0.9;
uniform float width = 0.08;
uniform float swirl = 0.0;
uniform float fill = 0.0;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
varying float seed;

void vertex() {
	seed = fract(MODEL_MATRIX[3].x * 0.137 + MODEL_MATRIX[3].z * 0.291);
	if (mode == 1 || mode == 2) {
		float s = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(INV_VIEW_MATRIX[0].xyz) * s, 0.0),
			vec4(normalize(INV_VIEW_MATRIX[1].xyz) * s * (mode == 2 ? 1.5 : 1.0), 0.0),
			vec4(normalize(INV_VIEW_MATRIX[2].xyz) * s, 0.0), MODEL_MATRIX[3]);
	} else if (mode == 3) {
		vec3 up = MODEL_MATRIX[1].xyz;
		vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
		vec3 right = normalize(cross(normalize(up), to_cam)) * length(MODEL_MATRIX[0].xyz);
		vec3 fwd = normalize(cross(right, up));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(up, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
	}
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	vec3 c = col.rgb;
	float a = 0.0;
	if (mode == 0) {
		float ring = exp(-pow((d - ringr) / width, 2.0));
		float ang = atan(uv.y, uv.x);
		float inside = 1.0 - smoothstep(ringr - 0.02, ringr + 0.02, d);
		float sw = swirl * pow(0.5 + 0.5 * sin(ang * 6.0 + d * 12.0 - TIME * 8.0), 3.0) * inside * smoothstep(0.0, ringr, d);
		float f = fill * inside * (0.35 + 0.65 * d / max(ringr, 0.01));
		a = ring + sw * 0.7 + f * 0.5;
		c = mix(c, vec3(1.0), ring * 0.25);
	} else if (mode == 1) {
		a = exp(-d * d * 6.0) * 0.6 + exp(-d * d * 40.0) * 0.8;
		c = mix(c, vec3(1.0), exp(-d * d * 25.0));
	} else if (mode == 2) {
		float h = 1.0 - UV.y;
		float n = texture(noise_tex, vec2(UV.x * 0.6 + seed, UV.y * 0.5 + TIME * 1.3 + seed * 3.0)).a;
		float x = uv.x + (n - 0.5) * 0.7 * h;
		float w = mix(0.55, 0.02, h);
		float shape = (1.0 - smoothstep(w * 0.2, w, abs(x))) * (1.0 - smoothstep(0.35, 1.0, h + (n - 0.5) * 0.5)) * smoothstep(0.0, 0.12, h);
		c = mix(vec3(1.0, 0.22, 0.04), vec3(1.0, 0.85, 0.45), shape * shape);
		a = shape * 1.4;
	} else {
		float core = exp(-uv.x * uv.x * 6.0);
		a = core * (1.0 - smoothstep(0.55, 1.0, UV.y * -1.0 + 1.0)) ;
		a = core * smoothstep(0.0, 0.4, UV.y);
		c = mix(c, vec3(1.0), exp(-uv.x * uv.x * 30.0));
	}
	ALBEDO = c;
	ALPHA = clamp(a * alpha * col.a, 0.0, 1.0);
}
