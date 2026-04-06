shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform vec2 gnd_wind_direction;
global uniform float gnd_wind_speed;
global uniform float gnd_wind_strength;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_albedo_texture = true;
uniform vec4 albedo_color : source_color = vec4(1.0);

uniform bool use_normal_texture = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale : hint_range(0.0, 4.0) = 1.0;

uniform bool use_roughness_texture = false;
uniform sampler2D roughness_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness = 1.0;
uniform int roughness_texture_channel = 1;

uniform float metallic_specular : hint_range(0.0, 1.0) = 0.5;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;
uniform vec3 backlight_color : source_color = vec3(0.0);
uniform float sss_strength : hint_range(0.0, 1.0) = 0.0;

uniform float wind_speed : hint_range(0.0, 4.0) = 1.0;
uniform float wind_strength : hint_range(0.0, 4.0) = 1.0;
uniform float trunk_strength : hint_range(0.0, 1.0) = 0.02;
uniform float branch_frequency : hint_range(0.01, 4.0) = 0.32;
uniform float detail_frequency : hint_range(0.01, 8.0) = 1.15;
uniform float height_start : hint_range(-10.0, 10.0) = 0.4;
uniform float height_end : hint_range(-10.0, 50.0) = 4.0;

float sample_channel(vec4 value, int channel_index) {
    if (channel_index == 0) {
        return value.r;
    }
    if (channel_index == 1) {
        return value.g;
    }
    if (channel_index == 2) {
        return value.b;
    }
    return value.a;
}

void vertex() {
    vec2 wind_dir = normalize(max(abs(gnd_wind_direction.x) + abs(gnd_wind_direction.y), 0.0001) * gnd_wind_direction);
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float height_factor = smoothstep(height_start, height_end, VERTEX.y);
    float speed = gnd_wind_speed * wind_speed;
    float strength = gnd_wind_strength * wind_strength;

    float primary = sin(dot(world_pos.xz, wind_dir * branch_frequency) + TIME * speed);
    float secondary = sin(dot(world_pos.xz, vec2(-wind_dir.y, wind_dir.x) * detail_frequency) + TIME * (speed * 1.73));
    float gust = sin(dot(world_pos.xz, vec2(0.19, 0.27)) + TIME * (speed * 0.41));
    float sway = primary + secondary * 0.35 + gust * 0.2;
    float bend = mix(trunk_strength, strength, height_factor) * sway;

    VERTEX.xz += wind_dir * bend * height_factor;
}

void fragment() {
    vec4 tex = vec4(1.0);
    if (use_albedo_texture) {
        tex = texture(albedo_texture, UV);
    }
    vec4 base = tex * albedo_color;

    ALBEDO = base.rgb;
    ALPHA = base.a;
    ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
    SPECULAR = metallic_specular;
    ROUGHNESS = roughness;
    BACKLIGHT = backlight_color * base.a;
    SSS_STRENGTH = sss_strength;

    if (use_normal_texture) {
        NORMAL_MAP = texture(normal_texture, UV).rgb;
        NORMAL_MAP_DEPTH = normal_scale;
    }

    if (use_roughness_texture) {
        vec4 roughness_sample = texture(roughness_texture, UV);
        ROUGHNESS = sample_channel(roughness_sample, roughness_texture_channel);
    }
}
