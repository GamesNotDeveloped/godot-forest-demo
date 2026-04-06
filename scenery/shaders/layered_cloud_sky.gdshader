shader_type sky;

uniform sampler2D panorama_tex : source_color, filter_linear, repeat_enable;
uniform sampler2D cloud_tex_a : source_color, filter_linear, repeat_enable;
uniform sampler2D cloud_tex_b : source_color, filter_linear, repeat_enable;

uniform vec2 panorama_uv_offset = vec2(0.0, 0.0);
uniform float panorama_energy : hint_range(0.0, 4.0) = 1.0;
uniform float panorama_zenith_fade_start : hint_range(0.0, 0.999) = 0.92;
uniform float panorama_zenith_fade_end : hint_range(0.0, 1.0) = 0.985;
uniform vec3 zenith_tint : source_color = vec3(0.63, 0.7, 0.84);
uniform vec2 cloud_scroll_a = vec2(0.003, 0.0);
uniform vec2 cloud_scroll_b = vec2(-0.006, 0.0015);
uniform vec2 cloud_scale_a = vec2(0.12, 0.12);
uniform vec2 cloud_scale_b = vec2(0.2, 0.2);

uniform float cloud_density_a : hint_range(0.0, 2.0) = 0.62;
uniform float cloud_density_b : hint_range(0.0, 2.0) = 0.58;
uniform float cloud_softness : hint_range(0.01, 1.0) = 0.14;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.52;
uniform float cloud_horizon_fade : hint_range(0.0, 1.0) = 0.24;
uniform float cloud_top_fade : hint_range(0.0, 1.0) = 0.18;
uniform float cloud_brightness : hint_range(0.5, 2.0) = 1.08;
uniform vec3 cloud_tint : source_color = vec3(0.98, 0.96, 0.93);
uniform float cloud_plane_height : hint_range(0.05, 4.0) = 0.55;
uniform float cloud_plane_curve : hint_range(0.0, 1.0) = 0.12;
uniform float sun_disk_size : hint_range(0.0, 1.0) = 0.22;
uniform float sun_disk_softness : hint_range(0.0, 1.0) = 0.18;
uniform float sun_halo_size : hint_range(0.0005, 0.2) = 0.045;
uniform float sun_halo_strength : hint_range(0.0, 4.0) = 0.9;
uniform float sun_cloud_occlusion : hint_range(0.0, 1.0) = 0.55;
uniform float sun_energy_scale : hint_range(0.0, 1.0) = 0.18;


vec2 dir_to_equirect_uv(vec3 dir) {
    vec3 n = normalize(dir);
    float longitude = atan(n.x, -n.z);
    float latitude = asin(clamp(n.y, -1.0, 1.0));
    return vec2(longitude / TAU + 0.5, 1.0 - (latitude / PI + 0.5));
}


vec2 dir_to_cloud_plane_uv(vec3 dir, float plane_height, float curve) {
    float denom = max(dir.y + plane_height, 0.05);
    vec2 uv = dir.xz / denom;
    float dist = length(uv);
    uv *= 1.0 + dist * curve;
    return uv;
}


float sample_cloud_layer(sampler2D tex, vec2 uv, vec2 scale_uv, vec2 scroll_uv, float density) {
    vec2 layer_uv = uv * scale_uv + scroll_uv * TIME;
    float raw = texture(tex, layer_uv).r;
    return smoothstep(density - cloud_softness, density + cloud_softness, raw);
}


void sky() {
    vec3 dir = normalize(EYEDIR);
    vec2 pano_uv = dir_to_equirect_uv(dir) + panorama_uv_offset;
    vec2 pano_texel = 1.0 / vec2(textureSize(panorama_tex, 0));
    pano_uv.x = fract(pano_uv.x);
    pano_uv.y = clamp(pano_uv.y, pano_texel.y * 0.5, 1.0 - pano_texel.y * 0.5);
    vec3 panorama_base = texture(panorama_tex, pano_uv).rgb * panorama_energy;
    float zenith_blend = smoothstep(
        min(panorama_zenith_fade_start, panorama_zenith_fade_end - 0.0001),
        max(panorama_zenith_fade_end, panorama_zenith_fade_start + 0.0001),
        max(dir.y, 0.0)
    );
    vec3 zenith_base = mix(panorama_base, zenith_tint, 0.65);
    vec3 base = mix(panorama_base, zenith_base, zenith_blend);

    vec2 cloud_uv = dir_to_cloud_plane_uv(dir, cloud_plane_height, cloud_plane_curve);
    float cloud_a = sample_cloud_layer(cloud_tex_a, cloud_uv, cloud_scale_a, cloud_scroll_a, cloud_density_a);
    float cloud_b = sample_cloud_layer(cloud_tex_b, cloud_uv + vec2(1.7, -0.9), cloud_scale_b, cloud_scroll_b, cloud_density_b);
    float breakup = texture(cloud_tex_b, cloud_uv * 0.08 + vec2(-0.02, 0.015) * TIME).r;
    float combined = clamp((cloud_a * 0.75 + cloud_b * 0.55) * mix(0.82, 1.18, breakup) * cloud_opacity, 0.0, 1.0);

    float horizon = smoothstep(-0.12, cloud_horizon_fade, dir.y);
    float zenith = 1.0 - smoothstep(1.0 - cloud_top_fade, 1.0, max(dir.y, 0.0));
    float vertical_mask = horizon * zenith;

    float lighting = mix(0.8, cloud_brightness, clamp(dir.y * 0.5 + 0.5, 0.0, 1.0));
    vec3 clouds = cloud_tint * lighting;
    vec3 final_color = mix(base, clouds, combined * vertical_mask);

    if (LIGHT0_ENABLED) {
        vec3 sun_dir = normalize(LIGHT0_DIRECTION);
        float sun_dot = clamp(dot(dir, sun_dir), 0.0, 1.0);
        float disk_radius = mix(0.00005, 0.012, pow(clamp(sun_disk_size, 0.0, 1.0), 2.4));
        float disk_softness = mix(0.00002, 0.006, pow(clamp(sun_disk_softness, 0.0, 1.0), 2.2));
        float disk = smoothstep(1.0 - disk_radius - disk_softness, 1.0 - disk_radius, sun_dot);
        float halo = smoothstep(1.0 - sun_halo_size, 1.0, sun_dot);
        float cloud_block = 1.0 - (combined * vertical_mask * sun_cloud_occlusion);
        vec3 sun_color = LIGHT0_COLOR.rgb * max(LIGHT0_ENERGY * sun_energy_scale, 0.0);
        final_color += sun_color * disk * cloud_block;
        final_color += sun_color * halo * sun_halo_strength * cloud_block * 0.25;
    }

    COLOR = final_color;
}
