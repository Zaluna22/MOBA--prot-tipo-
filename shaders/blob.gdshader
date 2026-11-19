shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
void fragment() {
	float d = length(UV * 2.0 - 1.0);
	ALBEDO = vec3(0.02, 0.04, 0.05);
	ALPHA = (1.0 - smoothstep(0.25, 1.0, d)) * 0.55;
}
