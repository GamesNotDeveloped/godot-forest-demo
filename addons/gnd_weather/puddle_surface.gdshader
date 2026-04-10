shader_type spatial;

render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D mask_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap, repeat_disable;
uniform vec4 shallow_color : source_color = vec4(0.11, 0.15, 0.13, 1.0);
uniform vec4 deep_color : source_color = vec4(0.03, 0.06, 0.07, 1.0);
uniform float rain_strength : hint_range(0.0, 1.0) = 0.0;
uniform float rain_ripple_threshold : hint_range(0.0, 1.0) = 0.12;
uniform float rain_wave_threshold : hint_range(0.0, 1.0) = 0.45;
uniform float puddle_alpha_cutoff : hint_range(0.0, 1.0) = 0.07;
uniform float visibility_range_begin : hint_range(0.0, 500.0) = 18.0;
uniform float visibility_range_end : hint_range(0.0, 500.0) = 28.0;
uniform float depth_absorption : hint_range(0.0, 8.0) = 1.35;
uniform float refraction_strength : hint_range(0.0, 0.1) = 0.014;
uniform float refraction_mix : hint_range(0.0, 1.0) = 1.0;
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


float linear_depth(float nonlinear_depth, mat4 inv_projection_matrix) {
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
        nonlinear_depth = nonlinear_depth * 2.0 - 1.0;
    #endif
    return 1.0 / (nonlinear_depth * inv_projection_matrix[2].w + inv_projection_matrix[3].w);
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
    float height = 0.0;
    height += sin(dot(uv, normalize(vec2(0.18, 1.0))) * secondary_wave_scale * 13.0 + time_value * secondary_wave_speed);
    height += cos(dot(uv, normalize(vec2(-1.0, 0.16))) * secondary_wave_scale * 9.0 - time_value * secondary_wave_speed * 1.17) * 0.6;
    return height * secondary_wave_intensity * 0.012;
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

    float fragment_depth = linear_depth(FRAGCOORD.z, INV_PROJECTION_MATRIX);
    float visibility = 1.0 - smoothstep(visibility_range_begin, visibility_range_end, fragment_depth);
    float fade_noise = hash12(floor(UV * 192.0));
    if (visibility <= 0.0 || fade_noise > visibility) {
        discard;
    }

    float t = TIME;
    float eps = 0.004;
    float h_l = water_height(UV + vec2(-eps, 0.0), t);
    float h_r = water_height(UV + vec2(eps, 0.0), t);
    float h_d = water_height(UV + vec2(0.0, -eps), t);
    float h_u = water_height(UV + vec2(0.0, eps), t);

    vec3 base_normal = normalize(NORMAL);
    float slope_strength = max(normal_strength, 0.0) * 3.2;
    vec3 tangent_normal = normalize(vec3((h_l - h_r) * slope_strength, (h_d - h_u) * slope_strength, 0.55));
    mat3 tbn = mat3(normalize(TANGENT), normalize(BINORMAL), base_normal);
    vec3 view_normal = normalize(tbn * tangent_normal);
    NORMAL = view_normal;

    float scene_depth = linear_depth(texture(depth_texture, SCREEN_UV).x, INV_PROJECTION_MATRIX);
    float surface_depth = -VERTEX.z;
    float water_depth = max(scene_depth - surface_depth, 0.0);
    float depth_mix = 1.0 - exp(-water_depth * depth_absorption);

    float x_mult = VIEWPORT_SIZE.y / max(VIEWPORT_SIZE.x, 0.0001);
    vec3 tanx = BINORMAL * tangent_normal.x * x_mult;
    vec3 tany = TANGENT * tangent_normal.y;
    vec2 distortion = (tanx + tany).xy * refraction_strength * water_depth / max(scene_depth, 0.001);
    vec2 refracted_uv = clamp(SCREEN_UV + distortion, vec2(0.001), vec2(0.999));
    float refracted_depth = linear_depth(texture(depth_texture, refracted_uv).x, INV_PROJECTION_MATRIX);
    if (refracted_depth < surface_depth) {
        refracted_uv = SCREEN_UV;
    }
    vec3 scene_color = textureLod(screen_texture, refracted_uv, 0.0).rgb;
    vec3 absorption_tint = mix(shallow_color.rgb, deep_color.rgb, depth_mix);
    float alpha_tint = mix(shallow_color.a, deep_color.a, depth_mix);
    vec3 volume_absorption = mix(vec3(1.0), max(absorption_tint, vec3(0.001)), alpha_tint);
    vec3 absorbed_refraction = scene_color * pow(volume_absorption, vec3(water_depth * depth_absorption));
    vec3 transmission = mix(absorption_tint, absorbed_refraction, refraction_mix);

    float edge_mask = 1.0 - smoothstep(puddle_alpha_cutoff, min(puddle_alpha_cutoff + 0.18, 1.0), mask);
    float shore_fade = edge_mask * (1.0 - smoothstep(0.0, 0.22, water_depth));
    float ripple_energy = clamp(abs(h_l - h_r) + abs(h_d - h_u), 0.0, 1.0);
    float ndotv = clamp(abs(dot(view_normal, normalize(VIEW))), 0.0, 1.0);
    float fresnel = pow(1.0 - ndotv, fresnel_power) * fresnel_strength;
    float edge_blend = shore_fade * (0.75 + edge_foam_strength * 0.25);
    transmission = mix(transmission, scene_color, edge_blend * 0.2);

    ALBEDO = vec3(0.0);
    EMISSION = transmission * (1.0 - fresnel);
    METALLIC = 0.0;
    SPECULAR = specular_strength * (1.0 - edge_blend * 0.9);

    float roughness = surface_roughness;
    roughness += edge_blend * 0.16;
    ROUGHNESS = clamp(roughness, 0.03, 0.32);
}
