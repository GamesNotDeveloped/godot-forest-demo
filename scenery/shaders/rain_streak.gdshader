shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled;

uniform vec4 tint : source_color = vec4(0.84, 0.9, 1.0, 0.12);
uniform float width_softness : hint_range(0.01, 0.8) = 0.22;
uniform float tail_softness : hint_range(0.01, 1.0) = 0.55;
uniform float center_bias : hint_range(0.0, 1.0) = 0.62;

void fragment() {
	float centered_x = abs(UV.x - 0.5) * 2.0;
	float width_mask = 1.0 - smoothstep(0.0, width_softness, centered_x);

	float top_fade = smoothstep(0.0, 0.16, UV.y);
	float bottom_fade = 1.0 - smoothstep(center_bias, center_bias + tail_softness * 0.35, UV.y);
	float body_mask = top_fade * bottom_fade;

	float spark = smoothstep(0.18, 0.9, UV.y);
	float alpha = width_mask * body_mask * mix(0.75, 1.0, spark) * tint.a;

	ALBEDO = tint.rgb * alpha;
	ALPHA = alpha;
}
