shader_type sky;

uniform sampler2D cloud_tex_a : source_color, filter_linear, repeat_enable;
uniform sampler2D cloud_tex_b : source_color, filter_linear, repeat_enable;

group_uniforms Sky;
	uniform vec3 lower_sky_color : source_color = vec3(0.66, 0.71, 0.8);
	uniform vec3 horizon_color : source_color = vec3(0.82, 0.86, 0.89);
	uniform vec3 zenith_color : source_color = vec3(0.12, 0.24, 0.48);
	uniform float sky_energy : hint_range(0.0, 10.0) = 1.0;
	uniform float horizon_height : hint_range(-0.4, 0.5) = -0.02;
	uniform float horizon_softness : hint_range(0.02, 1.0) = 0.24;
	uniform float zenith_curve : hint_range(0.1, 8.0) = 1.65;
	uniform float horizon_glow_strength : hint_range(0.0, 4.0) = 0.5;

group_uniforms Sun;
	uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.8);
	uniform float sun_disk_size : hint_range(0.0, 2.0) = 1.0;
	uniform float sun_disk_softness : hint_range(0.0, 1.0) = 0.5;
	uniform float sun_disk_strength : hint_range(0.0, 20.0) = 5.0;
	uniform float sun_halo_size : hint_range(0.0, 2.0) = 1.0;
	uniform float sun_halo_strength : hint_range(0.0, 10.0) = 1.5;
	uniform float sun_atmosphere_size : hint_range(0.0, 4.0) = 1.0;
	uniform float sun_atmosphere_strength : hint_range(0.0, 10.0) = 1.0;
	uniform float sun_energy_scale : hint_range(0.0, 10.0) = 1.0;

group_uniforms Clouds;
	uniform vec2 cloud_scroll_a = vec2(0.0012, 0.00015);
	uniform vec2 cloud_scroll_b = vec2(-0.0018, 0.0004);
	uniform vec2 cloud_scale_a = vec2(0.045, 0.055);
	uniform vec2 cloud_scale_b = vec2(0.082, 0.125);
	uniform float cloud_plane_height : hint_range(0.02, 4.0) = 0.25;
	uniform float cloud_plane_curve : hint_range(0.0, 1.0) = 0.15;
	uniform float cloud_warp_strength : hint_range(0.0, 1.0) = 0.14;
	uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5;
	uniform float cloud_softness : hint_range(0.01, 1.0) = 0.2;
	uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.6;
	uniform float cloud_horizon_fade : hint_range(0.0, 1.0) = 0.3;
	uniform float cloud_top_fade : hint_range(0.0, 1.0) = 0.2;
	uniform vec3 cloud_light_color : source_color = vec3(1.0, 0.98, 0.95);
	uniform vec3 cloud_shadow_color : source_color = vec3(0.4, 0.45, 0.55);
	uniform float cloud_forward_scatter : hint_range(0.0, 4.0) = 1.5;
	uniform float cloud_backscatter : hint_range(0.0, 1.0) = 0.2;
	uniform float sun_cloud_occlusion : hint_range(0.0, 1.0) = 0.8;


vec2 dir_to_cloud_plane_uv(vec3 dir, float plane_height, float curve) {
    float denom = max(dir.y + plane_height, 0.05);
    vec2 uv = dir.xz / denom;
    float dist = length(uv);
    uv *= 1.0 + dist * curve;
    return uv;
}

float saturate(float value) {
    return clamp(value, 0.0, 1.0);
}

void sky() {
    vec3 dir = normalize(EYEDIR);

    // Sky Gradient
    float horizon_t = smoothstep(
        horizon_height - horizon_softness,
        horizon_height + horizon_softness,
        dir.y
    );
    float zenith_t = pow(saturate(max(dir.y, 0.0)), zenith_curve);
    
    vec3 base = mix(lower_sky_color, horizon_color, horizon_t);
    base = mix(base, zenith_color, zenith_t);
    
    // Horizon haze / glow
    float horizon_glow = pow(1.0 - saturate(abs(dir.y - horizon_height) * 2.5), 4.0);
    base += horizon_color * horizon_glow * horizon_glow_strength;

    // Clouds
    vec2 cloud_uv = dir_to_cloud_plane_uv(dir, cloud_plane_height, cloud_plane_curve);
    vec2 warp = texture(cloud_tex_b, cloud_uv * 0.01 + vec2(0.003, -0.002) * TIME).rg * 2.0 - 1.0;
    cloud_uv += warp * cloud_warp_strength;

    float cloud_a = texture(cloud_tex_a, cloud_uv * cloud_scale_a + cloud_scroll_a * TIME).r;
    float cloud_b = texture(cloud_tex_b, cloud_uv * cloud_scale_b + cloud_scroll_b * TIME).r;
    float breakup = texture(cloud_tex_b, cloud_uv * 0.04 - vec2(0.0015, 0.0008) * TIME).r;

    float cloud_shape = mix(cloud_a, cloud_b, 0.5);
    cloud_shape = mix(cloud_shape, cloud_shape * breakup, 0.4);
    float cloud_mask = 1.0 - smoothstep(
        cloud_coverage - cloud_softness,
        cloud_coverage + cloud_softness,
        cloud_shape
    );

    float horizon_mask = smoothstep(-0.1, cloud_horizon_fade, dir.y);
    float top_mask = 1.0 - smoothstep(1.0 - cloud_top_fade, 1.0, max(dir.y, 0.0));
    cloud_mask *= horizon_mask * top_mask * cloud_opacity;

    vec3 final_color = base * sky_energy;

    if (LIGHT0_ENABLED) {
        vec3 sun_dir = normalize(LIGHT0_DIRECTION);
        float sun_dot = dot(dir, sun_dir);
        
        // Sun Disk
        // We use a larger base for radius and scale it with sun_disk_size
        float disk_radius = 0.015 * sun_disk_size;
        float disk_soft = disk_radius * sun_disk_softness;
        float disk = smoothstep(1.0 - disk_radius - disk_soft, 1.0 - disk_radius, sun_dot);
        
        // Sun Halo (Mie Scattering approximation)
        float halo_radius = 0.08 * sun_halo_size;
        float halo = pow(saturate(sun_dot), 1.0 / halo_radius) * sun_halo_strength;
        
        // Atmospheric Sun Glow (Rayleigh/Haze approximation)
        float atmos_radius = 0.35 * sun_atmosphere_size;
        float atmosphere = pow(saturate(sun_dot), 1.0 / atmos_radius) * sun_atmosphere_strength;
        
        float sun_visibility = 1.0 - (cloud_mask * sun_cloud_occlusion);
        vec3 sun_term = sun_color * LIGHT0_COLOR.rgb * LIGHT0_ENERGY * sun_energy_scale;

        // Cloud Lighting
        float silver_lining = pow(saturate(sun_dot), 12.0) * cloud_forward_scatter;
        float backscatter_val = pow(1.0 - saturate(sun_dot), 2.0) * cloud_backscatter;
        vec3 cloud_col = mix(cloud_shadow_color, cloud_light_color, saturate(0.4 + silver_lining - backscatter_val));
        
        final_color = mix(final_color, cloud_col, cloud_mask);
        
        // Add sun components
        final_color += sun_term * disk * sun_visibility * sun_disk_strength;
        final_color += sun_term * halo * sun_visibility;
        final_color += sun_term * atmosphere * sun_visibility;
    } else {
        final_color = mix(final_color, mix(cloud_shadow_color, cloud_light_color, 0.5), cloud_mask);
    }

    COLOR = final_color;
}
