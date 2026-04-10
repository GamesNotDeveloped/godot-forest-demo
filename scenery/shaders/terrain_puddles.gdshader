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
uniform vec2 puddle_mask_uv_scale = vec2(1.0);
uniform float puddle_mask_threshold : hint_range(0.0, 1.0) = 0.08;
uniform float puddle_mask_softness : hint_range(0.0, 1.0) = 0.08;
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
    vec2 puddle_uv = (UV2 - vec2(0.5)) * puddle_mask_uv_scale + vec2(0.5);

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

    bool puddle_uv_in_bounds = puddle_uv.x >= 0.0 && puddle_uv.x <= 1.0 && puddle_uv.y >= 0.0 && puddle_uv.y <= 1.0;
    float raw_puddle_mask = 0.0;
    if (puddle_enabled && puddle_uv_in_bounds) {
        raw_puddle_mask = sample_mask_channel(textureLod(puddle_mask_texture, puddle_uv, 0.0), puddle_mask_channel);
    }
    float threshold_end = min(puddle_mask_threshold + max(puddle_mask_softness, 0.0001), 1.0);
    float puddle_mask = smoothstep(puddle_mask_threshold, threshold_end, clamp(raw_puddle_mask, 0.0, 1.0));

    float t = TIME;
    float eps = 0.004;
    float h_l = ripple_height(base_uv + vec2(-eps, 0.0), t);
    float h_r = ripple_height(base_uv + vec2(eps, 0.0), t);
    float h_d = ripple_height(base_uv + vec2(0.0, -eps), t);
    float h_u = ripple_height(base_uv + vec2(0.0, eps), t);

    float slope_strength = max(puddle_normal_strength, 0.0) * 3.2;
    vec3 puddle_tangent_normal = normalize(vec3((h_l - h_r) * slope_strength, (h_d - h_u) * slope_strength, 0.55));
    vec3 final_tangent_normal = normalize(mix(base_tangent_normal, puddle_tangent_normal, puddle_mask));
    NORMAL_MAP = final_tangent_normal * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = 1.0;

    float puddle_edge = 1.0 - smoothstep(0.0, 0.12, puddle_mask);
    float ndotv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
    float specular_view_factor = clamp(pow(1.0 - ndotv, 2.5) * 1.35 + 0.04, 0.04, 1.0);

    ALBEDO = base_albedo;
    AO = base_ao;
    AO_LIGHT_AFFECT = base_ao_light_affect;
    METALLIC = 0.0;
    SPECULAR = mix(0.0, puddle_specular * specular_view_factor * (1.0 - puddle_edge * 0.9), puddle_mask);

    float ripple_energy = clamp(abs(h_l - h_r) + abs(h_d - h_u), 0.0, 1.0);
    float puddle_rough = puddle_surface_roughness - ripple_energy * 0.025;
    puddle_rough += ndotv * 0.08;
    puddle_rough += puddle_edge * 0.12;
    ROUGHNESS = clamp(mix(base_rough, puddle_rough, puddle_mask), 0.03, 1.0);
}
