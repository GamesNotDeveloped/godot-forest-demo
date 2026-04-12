shader_type spatial;
render_mode specular_schlick_ggx, diffuse_lambert;

uniform vec4 water_color : source_color = vec4(0.0, 0.2, 0.4, 0.8);
uniform float wave_speed : hint_range(0.0, 5.0) = 0.5;
uniform float wave_frequency : hint_range(0.0, 10.0) = 2.0;
uniform float wave_amplitude : hint_range(0.0, 1.0) = 0.05;
uniform float refraction_strength : hint_range(0.0, 1.0) = 0.05;
uniform float roughness : hint_range(0.0, 1.0) = 0.1;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	float time = TIME * wave_speed;
	
	// Basic waving effect using UV and TIME
	vec2 wave_uv = UV * wave_frequency;
	float wave = sin(wave_uv.x + time) * cos(wave_uv.y + time * 0.8) * wave_amplitude;
	float wave2 = sin(wave_uv.y * 1.5 - time * 1.2) * cos(wave_uv.x * 1.3 + time) * wave_amplitude * 0.5;
	
	float total_wave = wave + wave2;
	
	// Distort screen UV for refraction
	vec2 distorted_uv = SCREEN_UV + vec2(total_wave) * refraction_strength;
	vec3 screen_color = texture(screen_texture, distorted_uv).rgb;
	
	// Apply color
	ALBEDO = mix(screen_color, water_color.rgb, water_color.a);
	
	// Normal mapping simulation (just slightly perturbing the normal)
	NORMAL = normalize(NORMAL + vec3(total_wave, total_wave, 0.0) * 2.0);
	
	METALLIC = 0.0;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
