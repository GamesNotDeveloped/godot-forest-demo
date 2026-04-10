shader_type spatial;

render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D base_albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_ao_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool base_has_normal = false;
uniform bool base_has_ao = false;
uniform vec4 base_albedo_color : source_color = vec4(1.0);
uniform float base_albedo_boost : hint_range(0.0, 4.0) = 1.0;
uniform vec2 base_uv_scale = vec2(1.0);
uniform float base_normal_scale : hint_range(0.0, 4.0) = 1.0;
uniform float base_roughness : hint_range(0.0, 1.0) = 1.0;
uniform float base_ao_light_affect : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D puddle_mask_texture : source_color, filter_nearest, repeat_disable;
uniform bool puddle_enabled = false;
uniform int puddle_mask_channel = 2;
uniform float puddle_mask_threshold : hint_range(0.0, 1.0) = 0.08;
uniform float puddle_mask_softness : hint_range(0.0, 1.0) = 0.08;
uniform float puddle_wet_edge_width : hint_range(0.0, 0.5) = 0.06;
uniform float puddle_wet_edge_feather_world : hint_range(0.0, 4.0) = 0.75;
uniform float puddle_wet_darkening : hint_range(0.0, 1.0) = 0.08;
uniform vec2 puddle_mask_world_size = vec2(1.0);
uniform float puddle_surface_roughness : hint_range(0.0, 1.0) = 0.08;
uniform float puddle_specular : hint_range(0.0, 1.0) = 0.18;
uniform float puddle_rain_strength : hint_range(0.0, 1.0) = 0.0;
uniform float puddle_ripple_threshold : hint_range(0.0, 1.0) = 0.08;
uniform float puddle_ripple_intensity : hint_range(0.0, 2.0) = 0.9;
uniform float puddle_ripple_scale : hint_range(0.1, 10.0) = 0.1;
uniform float puddle_ripple_speed : hint_range(0.1, 4.0) = 0.67;
uniform float puddle_ripple_max_radius : hint_range(0.0, 5.0) = 1.0;
uniform float puddle_normal_strength : hint_range(0.0, 8.0) = 1.0;

const float HASHSCALE1 = 0.1031;
const vec3 HASHSCALE3 = vec3(0.1031, 0.1030, 0.0973);


float sample_mask_channel(vec4 value, int channel_index) {
    if (channel_index == 0) {
        return value.r;
    }
    if (channel_index == 1) {
        return value.g;
    }
    if (channel_index == 2) {
        return value.b;
    }
    if (channel_index == 3) {
        return value.a;
    }
    return dot(value.rgb, vec3(0.2126, 0.7152, 0.0722));
}


bool puddle_uv_in_bounds(vec2 uv) {
    return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}


float sample_puddle_mask_raw(vec2 uv) {
    if (!puddle_enabled || !puddle_uv_in_bounds(uv)) {
        return 0.0;
    }
    return sample_mask_channel(textureLod(puddle_mask_texture, uv, 0.0), puddle_mask_channel);
}


float sample_puddle_mask_weight(vec2 uv) {
    if (!puddle_enabled || !puddle_uv_in_bounds(uv)) {
        return 0.0;
    }
    return 1.0;
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
    float rain_mask = smoothstep(puddle_ripple_threshold, 1.0, puddle_rain_strength);
    if (rain_mask <= 0.0001) {
        return 0.0;
    }

    vec2 field_uv = uv / max(puddle_ripple_scale, 0.001) * 0.85;
    vec2 cell_origin = floor(field_uv);
    float height = 0.0;

    for (float j = -1.0; j <= 1.0; j += 1.0) {
        for (float i = -1.0; i <= 1.0; i += 1.0) {
            vec2 cell = cell_origin + vec2(i, j);
            vec2 rnd = hash22(cell);
            vec2 center = cell + rnd;
            float age = fract(time_value * puddle_ripple_speed * mix(0.85, 1.15, rnd.x) + hash12(cell));
            float radius = mix(0.02, 0.18 + max(puddle_ripple_max_radius, 0.0) * 0.54, age);
            vec2 delta = field_uv - center;
            float dist = length(delta);
            float band = dist - radius;
            float envelope = exp(-11.0 * abs(band)) * (1.0 - age) * mix(0.8, 1.15, rnd.y);
            float ring = sin(band * 34.0 - age * 4.5) * envelope;
            height += ring;
        }
    }

    return height * puddle_ripple_intensity * rain_mask * 0.12;
}
void fragment() {
    vec2 base_uv = UV * base_uv_scale;
    vec2 puddle_uv = UV2;

    vec4 base_albedo_sample = texture(base_albedo_texture, base_uv) * base_albedo_color;
    vec3 base_albedo = base_albedo_sample.rgb * base_albedo_boost;
    float base_ao = base_has_ao ? texture(base_ao_texture, base_uv).r : 1.0;
    float base_rough = base_roughness;

    vec3 base_tangent_normal = vec3(0.0, 0.0, 1.0);
    if (base_has_normal) {
        base_tangent_normal = texture(base_normal_texture, base_uv).rgb * 2.0 - 1.0;
        base_tangent_normal.xy *= base_normal_scale;
        base_tangent_normal = normalize(base_tangent_normal);
    }

    float raw_puddle_mask = sample_puddle_mask_raw(puddle_uv);
    float threshold_end = min(puddle_mask_threshold + max(puddle_mask_softness, 0.0001), 1.0);
    float puddle_mask = smoothstep(puddle_mask_threshold, threshold_end, clamp(raw_puddle_mask, 0.0, 1.0));
    vec2 puddle_texel = 1.0 / vec2(textureSize(puddle_mask_texture, 0));
    vec2 feather_uv = vec2(
        puddle_wet_edge_feather_world / max(puddle_mask_world_size.x, 0.0001),
        puddle_wet_edge_feather_world / max(puddle_mask_world_size.y, 0.0001)
    );
    vec2 blur_step = max(feather_uv, puddle_texel);
    vec2 blur_half_step = max(blur_step * 0.5, puddle_texel);
    float blurred_raw_puddle_mask = raw_puddle_mask * 0.14;
    float blurred_raw_puddle_weight = sample_puddle_mask_weight(puddle_uv) * 0.14;
    vec2 sample_uv = puddle_uv + vec2(blur_half_step.x, 0.0);
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.10;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.10;
    sample_uv = puddle_uv - vec2(blur_half_step.x, 0.0);
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.10;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.10;
    sample_uv = puddle_uv + vec2(0.0, blur_half_step.y);
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.10;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.10;
    sample_uv = puddle_uv - vec2(0.0, blur_half_step.y);
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.10;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.10;
    sample_uv = puddle_uv + vec2(blur_step.x, 0.0);
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.09;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.09;
    sample_uv = puddle_uv - vec2(blur_step.x, 0.0);
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.09;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.09;
    sample_uv = puddle_uv + vec2(0.0, blur_step.y);
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.09;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.09;
    sample_uv = puddle_uv - vec2(0.0, blur_step.y);
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.09;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.09;
    sample_uv = puddle_uv + blur_half_step;
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.05;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.05;
    sample_uv = puddle_uv - blur_half_step;
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.05;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.05;
    sample_uv = puddle_uv + vec2(blur_half_step.x, -blur_half_step.y);
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.05;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.05;
    sample_uv = puddle_uv + vec2(-blur_half_step.x, blur_half_step.y);
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.05;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.05;
    sample_uv = puddle_uv + blur_step;
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.03;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.03;
    sample_uv = puddle_uv - blur_step;
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.03;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.03;
    sample_uv = puddle_uv + vec2(blur_step.x, -blur_step.y);
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.03;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.03;
    sample_uv = puddle_uv + vec2(-blur_step.x, blur_step.y);
    blurred_raw_puddle_mask += sample_puddle_mask_raw(sample_uv) * 0.03;
    blurred_raw_puddle_weight += sample_puddle_mask_weight(sample_uv) * 0.03;
    blurred_raw_puddle_mask = clamp(blurred_raw_puddle_mask / max(blurred_raw_puddle_weight, 0.0001), 0.0, 1.0);
    float clamped_blurred_raw_puddle_mask = clamp(blurred_raw_puddle_mask, 0.0, 1.0);
    float rough_edge_width = max(puddle_wet_edge_width, 0.0001);
    float blurred_puddle_mask = smoothstep(
        puddle_mask_threshold,
        threshold_end,
        clamped_blurred_raw_puddle_mask
    );
    float wet_edge_start = max(puddle_mask_threshold - rough_edge_width, 0.0);
    float wet_edge_end = min(threshold_end + rough_edge_width, 1.0);
    float wet_mask = smoothstep(wet_edge_start, wet_edge_end, clamped_blurred_raw_puddle_mask);
    wet_mask = pow(clamp(wet_mask, 0.0, 1.0), 0.75);
    wet_mask = max(wet_mask, puddle_mask);
    float surface_wet_mask = smoothstep(
        max(wet_edge_start - rough_edge_width, 0.0),
        min(wet_edge_end + rough_edge_width, 1.0),
        clamped_blurred_raw_puddle_mask
    );
    surface_wet_mask = pow(clamp(surface_wet_mask, 0.0, 1.0), 0.6);
    surface_wet_mask = max(surface_wet_mask, wet_mask);

    vec2 ripple_uv = puddle_uv * base_uv_scale;
    float t = TIME;
    float eps = 0.004;
    float h_l = ripple_height(ripple_uv + vec2(-eps, 0.0), t);
    float h_r = ripple_height(ripple_uv + vec2(eps, 0.0), t);
    float h_d = ripple_height(ripple_uv + vec2(0.0, -eps), t);
    float h_u = ripple_height(ripple_uv + vec2(0.0, eps), t);

    float slope_strength = max(puddle_normal_strength, 0.0) * 3.2;
    vec3 puddle_tangent_normal = normalize(vec3((h_l - h_r) * slope_strength, (h_d - h_u) * slope_strength, 0.55));
    float ripple_mask = wet_mask;
    vec3 final_tangent_normal = normalize(mix(base_tangent_normal, puddle_tangent_normal, ripple_mask));
    NORMAL_MAP = final_tangent_normal * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = 1.0;

    float puddle_edge = 1.0 - smoothstep(0.0, 0.12, puddle_mask);
    float wet_edge = 1.0 - smoothstep(0.0, 0.22, surface_wet_mask);
    float ndotv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
    float specular_view_factor = clamp(pow(1.0 - ndotv, 2.5) * 1.35 + 0.04, 0.04, 1.0);

    ALBEDO = mix(base_albedo, base_albedo * (1.0 - puddle_wet_darkening), surface_wet_mask);
    AO = base_ao;
    AO_LIGHT_AFFECT = base_ao_light_affect;
    METALLIC = 0.0;
    SPECULAR = mix(0.0, puddle_specular * specular_view_factor * (1.0 - wet_edge * 0.9), surface_wet_mask);

    float ripple_energy = clamp(abs(h_l - h_r) + abs(h_d - h_u), 0.0, 1.0) * ripple_mask;
    float puddle_rough = puddle_surface_roughness - ripple_energy * 0.025;
    puddle_rough += ndotv * 0.08;
    puddle_rough += wet_edge * 0.12;

    // Feather roughness from both sides of the seam so wet and dry regions meet gradually.
    float dry_edge_roughness_blend = smoothstep(
        wet_edge_start,
        puddle_mask_threshold,
        clamped_blurred_raw_puddle_mask
    ) * (1.0 - blurred_puddle_mask);
    float wet_edge_roughness_blend = (
        1.0 - smoothstep(
            threshold_end,
            wet_edge_end,
            clamped_blurred_raw_puddle_mask
        )
    ) * blurred_puddle_mask;

    float dry_side_roughness = mix(base_rough, puddle_rough, dry_edge_roughness_blend);
    float wet_side_roughness = mix(puddle_rough, base_rough, wet_edge_roughness_blend);
    float blended_roughness = mix(dry_side_roughness, wet_side_roughness, blurred_puddle_mask);
    ROUGHNESS = clamp(blended_roughness, 0.03, 1.0);
}
