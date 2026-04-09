shader_type spatial;

render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D mask_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap, repeat_disable;
uniform vec4 shallow_color : source_color = vec4(0.11, 0.15, 0.13, 1.0);
uniform vec4 deep_color : source_color = vec4(0.03, 0.06, 0.07, 1.0);
uniform vec4 foam_color : source_color = vec4(0.84, 0.88, 0.82, 1.0);
uniform float rain_strength : hint_range(0.0, 1.0) = 0.0;
uniform float rain_ripple_threshold : hint_range(0.0, 1.0) = 0.12;
uniform float rain_wave_threshold : hint_range(0.0, 1.0) = 0.45;
uniform float puddle_alpha_cutoff : hint_range(0.0, 1.0) = 0.07;
uniform float depth_absorption : hint_range(0.0, 8.0) = 1.35;
uniform float refraction_strength : hint_range(0.0, 0.1) = 0.014;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.72;
uniform float fresnel_power : hint_range(0.5, 8.0) = 5.0;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.04;
uniform float ripple_roughness_reduction : hint_range(0.0, 1.0) = 0.02;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.65;
uniform float wave_intensity : hint_range(0.0, 2.0) = 0.08;
uniform float wave_scale : hint_range(0.1, 20.0) = 1.6;
uniform float wave_speed : hint_range(0.1, 20.0) = 0.35;
uniform float secondary_wave_intensity : hint_range(0.0, 2.0) = 0.05;
uniform float secondary_wave_scale : hint_range(0.1, 20.0) = 2.8;
uniform float secondary_wave_speed : hint_range(0.1, 20.0) = 0.55;
uniform float ripple_intensity : hint_range(0.0, 2.0) = 0.18;
uniform float ripple_scale : hint_range(0.1, 10.0) = 1.2;
uniform float ripple_speed : hint_range(0.1, 4.0) = 0.9;
uniform float ripple_max_radius : hint_range(0.0, 5.0) = 1.0;
uniform float edge_foam_strength : hint_range(0.0, 1.0) = 0.08;
uniform float normal_strength : hint_range(0.0, 8.0) = 1.4;

const float HASHSCALE1 = 0.1031;
const vec3 HASHSCALE3 = vec3(0.1031, 0.1030, 0.0973);


float sample_mask_alpha(vec2 uv) {
    return texture(mask_texture, uv).a;
}


float linear_depth(float raw_depth, vec2 screen_uv, mat4 inv_projection_matrix) {
    vec3 ndc = vec3(screen_uv * 2.0 - 1.0, raw_depth);
    vec4 view_position = inv_projection_matrix * vec4(ndc, 1.0);
    view_position.xyz /= view_position.w;
    return -view_position.z;
}


float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * HASHSCALE1);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}


vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * HASHSCALE3);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx + p3.yz) * p3.zy);
}


float ripple_height(vec2 uv, float time_value) {
    float rain_mask = smoothstep(rain_ripple_threshold, 1.0, rain_strength);
    if (rain_mask <= 0.0001) {
        return 0.0;
    }

    vec2 field_uv = uv / max(ripple_scale, 0.001) * 0.85;
    vec2 cell_origin = floor(field_uv);
    float height = 0.0;

    for (float j = -1.0; j <= 1.0; j += 1.0) {
        for (float i = -1.0; i <= 1.0; i += 1.0) {
            vec2 cell = cell_origin + vec2(i, j);
            vec2 rnd = hash22(cell);
            vec2 center = cell + rnd;
            float age = fract(time_value * ripple_speed * mix(0.85, 1.15, rnd.x) + hash12(cell));
            float radius = mix(0.02, 0.18 + max(ripple_max_radius, 0.0) * 0.54, age);
            vec2 delta = field_uv - center;
            float dist = length(delta);
            float band = dist - radius;
            float envelope = exp(-11.0 * abs(band)) * (1.0 - age) * mix(0.8, 1.15, rnd.y);
            float ring = sin(band * 34.0 - age * 4.5) * envelope;
            height += ring;
        }
    }

    return height * ripple_intensity * rain_mask * 0.12;
}


float primary_wave_height(vec2 uv, float time_value) {
    float height = 0.0;
    height += sin(dot(uv, normalize(vec2(1.0, 0.24))) * wave_scale * 10.0 + time_value * wave_speed);
    height += sin(dot(uv, normalize(vec2(-0.45, 1.0))) * wave_scale * 7.0 - time_value * wave_speed * 0.82) * 0.65;
    return height * wave_intensity * 0.02;
}


float secondary_wave_height(vec2 uv, float time_value) {
    float rain_wave_mask = mix(0.35, 1.0, smoothstep(rain_wave_threshold, 1.0, rain_strength));
    float height = 0.0;
    height += sin(dot(uv, normalize(vec2(0.18, 1.0))) * secondary_wave_scale * 13.0 + time_value * secondary_wave_speed);
    height += cos(dot(uv, normalize(vec2(-1.0, 0.16))) * secondary_wave_scale * 9.0 - time_value * secondary_wave_speed * 1.17) * 0.6;
    return height * secondary_wave_intensity * 0.012 * rain_wave_mask;
}


float water_height(vec2 uv, float time_value) {
    float mask = sample_mask_alpha(uv);
    if (mask <= 0.001) {
        return 0.0;
    }
    float waves = primary_wave_height(uv, time_value) + secondary_wave_height(uv, time_value);
    float ripples = ripple_height(uv, time_value);
    return (waves + ripples) * mask;
}


void fragment() {
    float mask = sample_mask_alpha(UV);
    if (mask < puddle_alpha_cutoff) {
        discard;
    }

    float t = TIME;
    float eps = 0.004;
    float h_l = water_height(UV + vec2(-eps, 0.0), t);
    float h_r = water_height(UV + vec2(eps, 0.0), t);
    float h_d = water_height(UV + vec2(0.0, -eps), t);
    float h_u = water_height(UV + vec2(0.0, eps), t);

    float slope_strength = max(normal_strength, 0.0) * 3.2;
    vec3 tangent_normal = normalize(vec3((h_l - h_r) * slope_strength, (h_d - h_u) * slope_strength, 0.55));
    mat3 tbn = mat3(normalize(TANGENT), normalize(BINORMAL), normalize(NORMAL));
    vec3 view_normal = normalize(tbn * tangent_normal);
    NORMAL = view_normal;

    float scene_depth = linear_depth(texture(depth_texture, SCREEN_UV).x, SCREEN_UV, INV_PROJECTION_MATRIX);
    float surface_depth = linear_depth(FRAGCOORD.z, SCREEN_UV, INV_PROJECTION_MATRIX);
    float water_depth = max(scene_depth - surface_depth, 0.0);
    float depth_mix = 1.0 - exp(-water_depth * depth_absorption);

    vec2 distortion = view_normal.xy * refraction_strength * clamp(water_depth, 0.0, 1.0);
    vec2 refracted_uv = clamp(SCREEN_UV + distortion, vec2(0.001), vec2(0.999));
    vec3 scene_color = textureLod(screen_texture, refracted_uv, 0.0).rgb;
    vec3 absorption_tint = mix(shallow_color.rgb, deep_color.rgb, depth_mix);
    float alpha_tint = mix(shallow_color.a, deep_color.a, depth_mix);
    float tint_strength = clamp((0.55 + depth_mix * 0.25) * alpha_tint, 0.02, 0.98);
    vec3 transmission = mix(scene_color, absorption_tint, clamp(tint_strength, 0.0, 0.98));

    float edge_mask = 1.0 - smoothstep(puddle_alpha_cutoff, min(puddle_alpha_cutoff + 0.18, 1.0), mask);
    float shore_foam = edge_mask * (1.0 - smoothstep(0.0, 0.4, water_depth));
    float ripple_energy = clamp(abs(h_l - h_r) + abs(h_d - h_u), 0.0, 1.0);
    float ndotv = clamp(abs(dot(view_normal, normalize(VIEW))), 0.0, 1.0);
    float fresnel = pow(1.0 - ndotv, fresnel_power) * fresnel_strength;
    float calm_surface = 1.0 - clamp(ripple_energy * 2.5, 0.0, 1.0);
    float blob_suppression = (1.0 - fresnel) * calm_surface;

    ALBEDO = mix(transmission, foam_color.rgb, shore_foam * edge_foam_strength);
    METALLIC = 0.0;
    SPECULAR = specular_strength * mix(0.22, 1.0, fresnel);

    float roughness = surface_roughness;
    roughness -= ripple_energy * (ripple_roughness_reduction * 2.4);
    roughness -= fresnel * 0.015;
    roughness += blob_suppression * 0.075;
    ROUGHNESS = clamp(roughness, 0.03, 0.22);
}
