shader_type spatial;
render_mode blend_premul_alpha, depth_draw_never, cull_disabled;

uniform vec4 tint : source_color = vec4(0.84, 0.9, 1.0, 0.12);
uniform float width_softness : hint_range(0.01, 0.8) = 0.22;
uniform float tail_softness : hint_range(0.01, 1.0) = 0.55;
uniform float center_bias : hint_range(0.0, 1.0) = 0.62;
uniform float flow_speed : hint_range(0.0, 8.0) = 1.0;
uniform float travel_distance : hint_range(0.0, 32.0) = 8.0;
uniform float respawn_spread : hint_range(0.0, 4.0) = 0.35;
uniform float streak_length_scale : hint_range(0.05, 2.0) = 1.0;
uniform float intensity_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float blur_amount : hint_range(0.0, 1.0) = 0.0;
uniform float glow_amount : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.47;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform float roughness : hint_range(0.0, 1.0) = 0.1;

varying vec4 instance_custom_data;
varying float streak_flow;

float hash11(float p) {
	return fract(sin(p) * 43758.5453123);
}

void vertex() {
	instance_custom_data = INSTANCE_CUSTOM;
	float variation = instance_custom_data.b;
	float detail = instance_custom_data.a;
	float speed = TIME * flow_speed * mix(0.75, 1.35, variation);
	streak_flow = fract(instance_custom_data.r + speed);
	float cycle = floor(instance_custom_data.r + speed);
	float offset_x = (hash11(instance_custom_data.a * 97.13 + cycle * 13.71) - 0.5) * respawn_spread;
	float offset_z = (hash11(instance_custom_data.r * 83.17 + cycle * 7.91 + instance_custom_data.a * 19.37) - 0.5) * respawn_spread;
	VERTEX.y += (streak_flow - 0.5) * travel_distance;
	VERTEX.x += offset_x + sin((streak_flow + detail) * 6.28318) * mix(0.0, 0.012, detail);
	VERTEX.z += offset_z;
}

void fragment() {
	float instance_alpha = clamp(instance_custom_data.g, 0.0, 1.0);
	float variation = instance_custom_data.b;
	float detail = instance_custom_data.a;
	float primary_trail = UV.y;
	float secondary_trail = fract(UV.y * 1.35 + instance_custom_data.r * 0.7 + TIME * flow_speed * 0.18);

	float center_shift = mix(-0.18, 0.18, detail);
	float centered_x = abs((UV.x - 0.5) + center_shift * (1.0 - UV.y)) * 2.0;
	float width_mask = 1.0 - smoothstep(0.0, mix(width_softness * 0.7, width_softness * 1.35, detail), centered_x);
	width_mask *= 1.0 - smoothstep(0.78, 1.0, centered_x);

	float primary_length = mix(0.24, 0.52, variation) * streak_length_scale;
	float primary_head_size = mix(0.02, 0.05, detail);
	float primary_tail = (1.0 - smoothstep(0.0, primary_length, primary_trail)) * smoothstep(0.0, 0.012, primary_trail);
	float primary_head_glow = 1.0 - smoothstep(0.0, primary_head_size, primary_trail);
	float primary_streak = max(primary_tail * 0.9, primary_head_glow);

	float secondary_length = mix(0.1, 0.28, detail) * streak_length_scale;
	float secondary_tail = (1.0 - smoothstep(0.0, secondary_length, secondary_trail)) * smoothstep(0.0, 0.02, secondary_trail);
	float secondary_head_glow = 1.0 - smoothstep(0.0, mix(0.025, 0.055, variation), secondary_trail);
	float secondary_streak = max(secondary_tail * mix(0.35, 0.7, detail), secondary_head_glow * 0.65);

	float streak_mask = max(primary_streak, secondary_streak * mix(0.2, 0.45, variation));
	float body_end_min = mix(0.28, 0.46, detail) * streak_length_scale;
	float body_end_max = mix(0.58, 0.82, variation) * streak_length_scale;
	float body_fade = smoothstep(0.0, 0.04, UV.y) * (1.0 - smoothstep(body_end_min, body_end_max, UV.y));
	float breakup = 0.65 + 0.35 * sin(
		UV.y * mix(16.0, 28.0, detail)
		+ instance_custom_data.r * 17.0
		+ UV.x * mix(6.0, 14.0, variation)
	);
	float core_alpha = width_mask * body_fade * streak_mask * breakup;
	float blur_width = mix(width_softness * 1.35, width_softness * 3.1, blur_amount);
	float blur_width_mask = 1.0 - smoothstep(0.0, mix(blur_width * 0.95, blur_width * 1.55, detail), centered_x);
	blur_width_mask *= 1.0 - smoothstep(0.96, 1.36 + blur_amount * 0.3, centered_x);
	float blur_body_start = 0.08 + blur_amount * 0.08;
	float blur_body_end_min = body_end_min * mix(0.92, 0.74, blur_amount);
	float blur_body_end_max = body_end_max * mix(1.04, 1.2, blur_amount);
	float blur_body_fade = smoothstep(0.0, blur_body_start, UV.y) * (1.0 - smoothstep(blur_body_end_min, blur_body_end_max, UV.y));
	float blur_breakup = mix(1.0, breakup, 0.35);
	float blur_shape = blur_width_mask * blur_body_fade * pow(max(streak_mask, 0.0), 0.7) * blur_breakup;
	float blur_alpha = blur_shape * glow_amount;
	float alpha = core_alpha + blur_alpha;
	if (alpha < 0.00001) {
		discard;
	}
	float color_alpha = clamp(intensity * 0.5, 0.1, 0.3);
	float opacity_alpha = clamp(intensity * 0.5, 0.1, 0.4);
	float blur_visibility = mix(1.0, 0.42, blur_amount);
	float blur_color_visibility = mix(1.0, 0.58, blur_amount);
	ALBEDO = tint.rgb * ((core_alpha * intensity + blur_alpha * 0.18) * color_alpha * blur_color_visibility);
	ALPHA = (core_alpha * intensity + blur_alpha * 0.1) * opacity_alpha * blur_visibility;
	ROUGHNESS = roughness;
	SPECULAR = specular;
    EMISSION = vec3(1.0, 1.0, 1.0) * intensity * 0.005;

	// Curve the normal to make the streak act like a cylinder rather than a flat mirror.
	// This diffuses sharp environment reflections (like the sun/moon disk) into a vertical highlight.
	vec3 local_normal = normalize(vec3((UV.x - 0.5) * 2.5, 0.0, 1.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(local_normal, 0.0)).xyz);
}

