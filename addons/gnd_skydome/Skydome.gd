@tool
class_name Skydome
extends Node

signal time_changed(day: int, time: float)
signal day_changed(day: int)

const SUN_SHAFTS_EFFECT_SCRIPT := preload("res://addons/gnd_skydome/SunShaftsCompositorEffect.gd")
const FILMIC_SKY_SHADER := preload("res://addons/gnd_skydome/filmic_procedural_sky.gdshader")

var _environment: Environment
var _rendered_day: int = 180
var _rendered_time: float = 12.0
var _time_transition_active: bool = false
var _time_transition_wrapped: bool = false
var _time_transition_target_total_hours: float = 0.0
var _time_transition_target_unwrapped_time: float = 0.0
var _time_transition_speed_hours_per_second: float = 0.0
var _cloud_motion_time: float = 0.0
var _cloud_evolution_time: float = 0.0
var _sky_material: ShaderMaterial
var _compositor_effect: CompositorEffect
var _light: DirectionalLight3D
var _is_ready: bool = false
var _is_daytime: bool = true
var _weather_precipitation: float = 0.0
var _weather_storm_factor: float = 0.0
var _weather_lightning_flash: float = 0.0
var _weather_local_emission_scale: float = 1.0
var _cloud_texture_a: Texture2D
var _cloud_texture_b: Texture2D
var current_vol_fog_min_density: float = 0.0
var current_vol_fog_max_density: float = 0.0

func _error(x):
    push_error("[Skydome] "+x)

func _success(x):
    print_rich("[color=green][Skydome][/color] "+x)

@export var directional_light_path: NodePath:
    set(v):
        directional_light_path = v
        _refresh()
@export var world_environment_path: NodePath:
    set(v):
        world_environment_path = v
        _refresh()
@export var manage_vol_fog_density: bool = true:
    set(v): manage_vol_fog_density = v; _update_sun_transform()

@export_group("Time & Date")
@export_range(1, 365) var day_of_year: int = 180:
    set(v):
        day_of_year = v
        _request_time_update()
@export_range(0.0, 24.0) var time_of_day: float = 12.0:
    set(v):
        time_of_day = v
        _request_time_update()
@export_range(-90.0, 90.0) var latitude: float = 21.0:
    set(v):
        latitude = v
        _update_sun_transform()
@export var time_transition_duration: float = 1.0

@export_group("Sunset", "sunset")
@export_subgroup("Light", "sunset_light")
@export var sunset_light_color: Color = Color(1.0, 0.45, 0.15):
    set(v):
        sunset_light_color = v
        _update_sun_transform()
@export_subgroup("Sky", "shader")
@export var shader_sunset_bottom_color: Color = Color(1.0, 0.5, 0.2, 1):
    set(v): shader_sunset_bottom_color = v; _set_shader_param("sunset_bottom_color", v)
@export var shader_sunset_horizon_color: Color = Color(0.8, 0.2, 0.05, 1):
    set(v): shader_sunset_horizon_color = v; _set_shader_param("sunset_horizon_color", v)
@export var shader_sunset_zenith_color: Color = Color(0.4, 0.3, 0.5, 1):
    set(v): shader_sunset_zenith_color = v; _set_shader_param("sunset_zenith_color", v)
@export var shader_sunset_cloud_color: Color = Color(1.0, 0.4, 0.15, 1):
    set(v): shader_sunset_cloud_color = v; _set_shader_param("sunset_cloud_color", v)

@export_group("Day", "day")
@export_subgroup("Light", "day_light")
@export var day_light_energy: float = 1.28:
    set(v):
        day_light_energy = v
        _update_sun_transform()
@export var day_light_color: Color = Color(1.0, 0.93, 0.85):
    set(v):
        day_light_color = v
        _update_sun_transform()
@export_subgroup("Sky", "shader")
@export var shader_lower_sky_color: Color = Color(0.655, 0.706, 0.79, 1):
    set(v):
        shader_lower_sky_color = v
        _set_shader_param("lower_sky_color", v)
@export var shader_horizon_color: Color = Color(0.832, 0.86, 0.886, 1):
    set(v):
        shader_horizon_color = v
        _set_shader_param("horizon_color", v)
@export var shader_zenith_color: Color = Color(0.2373352, 0.4190016, 0.7890625, 1):
    set(v):
        shader_zenith_color = v
        _set_shader_param("zenith_color", v)
@export var shader_sky_energy: float = 1.0:
    set(v):
        shader_sky_energy = v
        _set_shader_param("sky_energy", v)
@export var shader_horizon_height: float = 0.05:
    set(v):
        shader_horizon_height = v
        _set_shader_param("horizon_height", v)
@export var shader_horizon_softness: float = 0.24:
    set(v):
        shader_horizon_softness = v
        _set_shader_param("horizon_softness", v)
@export var shader_zenith_curve: float = 0.405:
    set(v):
        shader_zenith_curve = v
        _set_shader_param("zenith_curve", v)
@export var shader_horizon_glow_strength: float = 1.004:
    set(v):
        shader_horizon_glow_strength = v
        _set_shader_param("horizon_glow_strength", v)
@export_subgroup("Ambient", "day_ambient")
@export var day_ambient_color: Color = Color(0.91, 0.85, 0.69):
    set(v):  day_ambient_color = v; _update_sun_transform()
@export var day_ambient_energy: float = 1.5:
    set(v):  day_ambient_energy = v; _update_sun_transform()
@export var day_ambient_sky_contribution: float = 0.25:
    set(v):  day_ambient_sky_contribution = v; _update_sun_transform()
@export_subgroup("Fog", "day_fog")
@export var day_fog_color: Color = Color(1.0, 0.95, 0.91):
    set(v):  day_fog_color = v; _update_sun_transform()
@export var day_fog_density: float = 0.005:
    set(v):  day_fog_density = v; _update_sun_transform()
@export var day_fog_sky_affect: float = 0.15:
    set(v):  day_fog_sky_affect = v; _update_sun_transform()
@export var day_fog_distance_begin: float = 2.6:
    set(v):  day_fog_distance_begin = v; _update_sun_transform()
@export var day_fog_distance: float = 470.0:
    set(v):  day_fog_distance = v; _update_sun_transform()
@export_subgroup("Volumetric fog", "day_vol_fog")
@export var day_vol_fog_albedo: Color = Color(0.77, 0.74, 0.7):
    set(v):  day_vol_fog_albedo = v; _update_sun_transform()
@export var day_vol_fog_density: float = 0.015:
    set(v):  day_vol_fog_density = v; _update_sun_transform()
@export var day_vol_fog_sky_affect: float = 0.3:
    set(v):  day_vol_fog_sky_affect = v; _update_sun_transform()
@export var day_vol_fog_length: float = 8.0:
    set(v):  day_vol_fog_length = v; _update_sun_transform()
@export var day_vol_fog_min_density: float = 0.005:
    set(v):  day_vol_fog_min_density = v; _update_sun_transform()
@export var day_vol_fog_ambient_inject: float = 0.04:
    set(v):  day_vol_fog_ambient_inject = v; _update_sun_transform()

@export_group("Night", "night")
@export_subgroup("Light", "night_light")
@export var night_light_color: Color = Color(0.6, 0.8, 1.0):
    set(v):
        night_light_color = v
        _update_sun_transform()
@export var night_light_energy: float = 0.2:
    set(v):
        night_light_energy = v
        _update_sun_transform()
@export_subgroup("Sky", "shader")
@export var shader_night_lower_sky_color: Color = Color(0.03, 0.05, 0.09, 1):
    set(v):
        shader_night_lower_sky_color = v
        _set_shader_param("night_lower_sky_color", v)
@export var shader_night_horizon_color: Color = Color(0.03, 0.05, 0.09, 1):
    set(v):
        shader_night_horizon_color = v
        _set_shader_param("night_horizon_color", v)
@export var shader_night_zenith_color: Color = Color(0.069, 0.08, 0.109, 1.0):
    set(v):
        shader_night_zenith_color = v
        _set_shader_param("night_zenith_color", v)
@export var shader_night_sky_energy: float = 0.3:
    set(v):
        shader_night_sky_energy = v
        _set_shader_param("night_sky_energy", v)
@export var shader_stars_color: Color = Color(1.0, 1.0, 1.0, 1):
    set(v):
        shader_stars_color = v
        _set_shader_param("stars_color", v)
@export var shader_stars_energy: float = 2.0:
    set(v):
        shader_stars_energy = v
        _set_shader_param("stars_energy", v)
@export var shader_stars_size_min: float = 0.01:
    set(v):
        shader_stars_size_min = v
        _set_shader_param("stars_size_min", v)
@export var shader_stars_size_max: float = 0.03:
    set(v):
        shader_stars_size_max = v
        _set_shader_param("stars_size_max", v)
@export var shader_stars_edge_softness: float = 0.25:
    set(v):
        shader_stars_edge_softness = v
        _set_shader_param("stars_edge_softness", v)
@export_subgroup("Ambient", "night_ambient")
@export var night_ambient_color: Color = Color(0.02, 0.03, 0.06):
    set(v):  night_ambient_color = v; _update_sun_transform()
@export var night_ambient_energy: float = 0.1:
    set(v):  night_ambient_energy = v; _update_sun_transform()
@export var night_ambient_sky_contribution: float = 0.8:
    set(v):  night_ambient_sky_contribution = v; _update_sun_transform()
@export_subgroup("Fog", "night_fog")
@export var night_fog_color: Color = Color(0.04, 0.06, 0.12):
    set(v):  night_fog_color = v; _update_sun_transform()
@export var night_fog_density: float = 0.02:
    set(v):  night_fog_density = v; _update_sun_transform()
@export var night_fog_sky_affect: float = 0.15:
    set(v):  night_fog_sky_affect = v; _update_sun_transform()
@export var night_fog_distance_begin: float = 2.6:
    set(v):  night_fog_distance_begin = v; _update_sun_transform()
@export var night_fog_distance: float = 200.0:
    set(v): night_fog_distance = v; _update_sun_transform()
@export_subgroup("Volumetric fog", "night_vol_fog")
@export var night_vol_fog_albedo: Color = Color(0.15, 0.18, 0.25):
    set(v):  night_vol_fog_albedo = v; _update_sun_transform()
@export var night_vol_fog_density: float = 0.05:
    set(v):  night_vol_fog_density = v; _update_sun_transform()
@export var night_vol_fog_ambient_inject: float = 0.1:
    set(v):  night_vol_fog_ambient_inject = v; _update_sun_transform()
@export var night_vol_fog_sky_affect: float = 0.25:
    set(v):  night_vol_fog_sky_affect = v; _update_sun_transform()
@export var night_vol_fog_length: float = 3.0:
    set(v):  night_vol_fog_length = v; _update_sun_transform()
@export var night_vol_fog_min_density: float = 0.01:
    set(v):  night_vol_fog_min_density = v; _update_sun_transform()

@export_group("Clouds", "clouds")
@export var clouds_coverage: float = 0.25:
    set(v):
        clouds_coverage = v
        _set_shader_param("cloud_coverage", v)
@export var clouds_opacity: float = 0.85:
    set(v):
        clouds_opacity = v
        _set_shader_param("cloud_opacity", v)
@export var clouds_softness: float = 0.2:
    set(v):
        clouds_softness = v
        _set_shader_param("cloud_softness", v)
@export_subgroup("Generator", "clouds_generator")
@export var clouds_generator_seed_a: int = 10:
    set(v):
        clouds_generator_seed_a = v
        _init_sky()
@export var clouds_generator_seed_b: int = 100:
    set(v):
        clouds_generator_seed_b = v
        _init_sky()
@export var clouds_generator_frequency_a: float = 1.0:
    set(v):
        clouds_generator_frequency_a = v
        _init_sky()
@export var clouds_generator_frequency_b: float = 0.8:
    set(v):
        clouds_generator_frequency_b = v
        _init_sky()

@export_subgroup("Colors", "clouds_color")
@export var clouds_color_light: Color = Color(1, 0.98, 0.95, 1):
    set(v):
        clouds_color_light = v
        _set_shader_param("cloud_light_color", v)
@export var clouds_color_shadow: Color = Color(0.898, 0.898, 0.898, 1):
    set(v):
        clouds_color_shadow = v
        _set_shader_param("cloud_shadow_color", v)
@export_subgroup("Motion", "clouds")
@export var clouds_time_scale: float = 6.0:
    set(v):
        clouds_time_scale = v
        _update_cloud_time()
@export var clouds_wind_speed_multiplier: float = 1.0:
    set(v):
        clouds_wind_speed_multiplier = v
        _update_cloud_wind()
@export var clouds_motion_scale: float = 0.12:
    set(v):
        clouds_motion_scale = v
        _set_shader_param("cloud_motion_scale", v)
@export var clouds_evolution_speed: float = 0.04
@export var clouds_evolution_strength: float = 0.18:
    set(v):
        clouds_evolution_strength = v
        _set_shader_param("cloud_evolution_strength", v)
@export var clouds_evolution_scale: float = 0.018:
    set(v):
        clouds_evolution_scale = v
        _set_shader_param("cloud_evolution_scale", v)
@export var clouds_scroll_a: Vector2 = Vector2(0.0012, 0.00015):
    set(v):
        clouds_scroll_a = v
        _set_shader_param("cloud_scroll_a", v)
@export var clouds_scroll_b: Vector2 = Vector2(-0.0018, 0.0004):
    set(v):
        clouds_scroll_b = v
        _set_shader_param("cloud_scroll_b", v)
@export_subgroup("Size and shape", "clouds")
@export var clouds_scale_a: Vector2 = Vector2(0.045, 0.055):
    set(v):
        clouds_scale_a = v
        _set_shader_param("cloud_scale_a", v)
@export var clouds_scale_b: Vector2 = Vector2(0.082, 0.125):
    set(v):
        clouds_scale_b = v
        _set_shader_param("cloud_scale_b", v)
@export_subgroup("Advanced", "clouds")
@export var clouds_plane_height: float = 0.187:
    set(v):
        clouds_plane_height = v
        _set_shader_param("cloud_plane_height", v)
@export var clouds_plane_curve: float = 0.595:
    set(v):
        clouds_plane_curve = v
        _set_shader_param("cloud_plane_curve", v)
@export var clouds_warp_strength: float = 0.053:
    set(v):
        clouds_warp_strength = v
        _set_shader_param("cloud_warp_strength", v)
@export var clouds_horizon_fade: float = 0.481:
    set(v):
        clouds_horizon_fade = v
        _set_shader_param("cloud_horizon_fade", v)
@export var clouds_top_fade: float = 0.118:
    set(v):
        clouds_top_fade = v
        _set_shader_param("cloud_top_fade", v)
@export var clouds_forward_scatter: float = 1.5:
    set(v):
        clouds_forward_scatter = v
        _set_shader_param("cloud_forward_scatter", v)
@export var clouds_backscatter: float = 0.390:
    set(v):
        clouds_backscatter = v
        _set_shader_param("cloud_backscatter", v)
@export var clouds_sun_occlusion: float = 0.406:
    set(v):
        clouds_sun_occlusion = v
        _set_shader_param("sun_cloud_occlusion", v)

@export_group("Sun", "sun")
@export var sun_day_color: Color = Color(1, 0.98, 0.9, 1):
    set(v):
        sun_day_color = v
        _set_shader_param("sun_color", v)
@export var sun_sunset_color: Color = Color(1.0, 0.4, 0.1, 1):
    set(v): sun_sunset_color = v; _set_shader_param("sunset_sun_color", v)
@export var sun_disk_size: float = 0.07:
    set(v):
        sun_disk_size = v
        _set_shader_param("sun_disk_size", v)
@export var sun_disk_softness: float = 0.6:
    set(v):
        sun_disk_softness = v
        _set_shader_param("sun_disk_softness", v)
@export var sun_disk_strength: float = 0.6:
    set(v):
        sun_disk_strength = v
        _set_shader_param("sun_disk_strength", v)
@export var sun_halo_size: float = 0.6:
    set(v):
        sun_halo_size = v
        _set_shader_param("sun_halo_size", v)
@export var sun_halo_strength: float = 0.6:
    set(v):
        sun_halo_strength = v
        _set_shader_param("sun_halo_strength", v)
@export var sun_atmosphere_size: float = 0.5:
    set(v):
        sun_atmosphere_size = v
        _set_shader_param("sun_atmosphere_size", v)
@export var sun_atmosphere_strength: float = 0.8:
    set(v):
        sun_atmosphere_strength = v
        _set_shader_param("sun_atmosphere_strength", v)
@export var sun_energy_scale: float = 0.8:
    set(v):
        sun_energy_scale = v
        _set_shader_param("sun_energy_scale", v)

@export_group("Moon", "moon")
@export var moon_texture: Texture2D:
    set(v): moon_texture = v; _set_shader_param("moon_texture", v)
@export var moon_color: Color = Color(0.9, 0.95, 1.0, 1):
    set(v):
        moon_color = v
        _set_shader_param("moon_color", v)
@export var moon_size: float = 1.0:
    set(v):
        moon_size = v
        _set_shader_param("moon_size", v)
@export var moon_glow_strength: float = 1.0:
    set(v):
        moon_glow_strength = v
        _set_shader_param("moon_glow_strength", v)
@export var moon_eclipse_size: float = 2.5:
    set(v):
        moon_eclipse_size = v
        _set_shader_param("moon_eclipse_size", v)

@export_group("Sunshafts", "sunshafts")
@export var sunshafts_enabled: bool = true:
    set(v):
        sunshafts_enabled = v
        _update_effect()
@export var sunshafts_distance: float = 3000.0
@export var sunshafts_shaft_color: Color = Color(0.718, 0.637, 0.379, 1):
    set(v):
        sunshafts_shaft_color = v
        _update_effect()
@export var sunshafts_density: float = 0.485:
    set(v):
        sunshafts_density = v
        _update_effect()
@export var sunshafts_bright_threshold: float = 0.182:
    set(v):
        sunshafts_bright_threshold = v
        _update_effect()
@export var sunshafts_weight: float = 0.0355:
    set(v):
        sunshafts_weight = v
        _update_effect()
@export var sunshafts_decay: float = 0.93:
    set(v):
        sunshafts_decay = v
        _update_effect()
@export var sunshafts_exposure: float = 1.59:
    set(v):
        sunshafts_exposure = v
        _update_effect()
@export var sunshafts_max_radius: float = 1.377:
    set(v):
        sunshafts_max_radius = v
        _update_effect()

@export_group("Weather Overrides")
@export_range(0.0, 2.0, 0.01) var weather_overcast_intensity: float = 1.0:
    set(v):
        weather_overcast_intensity = v
        _update_sun_transform()
@export_range(0.0, 8.0, 0.01) var weather_fog_density_boost: float = 0.22:
    set(v):
        weather_fog_density_boost = v
        _update_sun_transform()
@export_range(0.0, 8.0, 0.01) var weather_storm_fog_density_boost: float = 0.28:
    set(v):
        weather_storm_fog_density_boost = v
        _update_sun_transform()
@export_range(0.0, 1.5, 0.001) var weather_fog_density_target: float = 0.012:
    set(v):
        weather_fog_density_target = v
        _update_sun_transform()
@export var weather_fog_curve: Curve = Curve.new():
    set(v):
        weather_fog_curve = v
        _ensure_weather_fog_curve()
        _update_sun_transform()
@export_range(0.0, 1.0, 0.001) var weather_fog_sky_affect_target: float = 0.12:
    set(v):
        weather_fog_sky_affect_target = v
        _update_sun_transform()
@export_range(0.0, 100.0, 0.1) var weather_fog_begin_distance: float = 2.4:
    set(v):
        weather_fog_begin_distance = v
        _update_sun_transform()
@export_range(1.0, 2000.0, 1.0) var weather_fog_end_distance: float = 180.0:
    set(v):
        weather_fog_end_distance = v
        _update_sun_transform()
@export_range(0.0, 8.0, 0.01) var weather_volumetric_fog_boost: float = 0.58:
    set(v):
        weather_volumetric_fog_boost = v
        _update_sun_transform()
@export_range(0.0, 8.0, 0.01) var weather_storm_volumetric_fog_boost: float = 0.72:
    set(v):
        weather_storm_volumetric_fog_boost = v
        _update_sun_transform()
@export_range(0.0, 2.0, 0.001) var weather_volumetric_fog_density_target: float = 0.14:
    set(v):
        weather_volumetric_fog_density_target = v
        _update_sun_transform()
@export_range(0.0, 1.0, 0.001) var weather_volumetric_fog_sky_affect_target: float = 0.32:
    set(v):
        weather_volumetric_fog_sky_affect_target = v
        _update_sun_transform()
@export var weather_volumetric_fog_emission_color: Color = Color(0.0, 0.0, 0.0, 1.0):
    set(v):
        weather_volumetric_fog_emission_color = v
        _update_sun_transform()
@export_range(0.0, 8.0, 0.01) var weather_volumetric_fog_emission_energy: float = 0.0:
    set(v):
        weather_volumetric_fog_emission_energy = v
        _update_sun_transform()

@export_group("Debug")
@export_range(0.0, 1.0) var moon_phase_debug: float

@export_group("Sky Shader: Atmosphere")
@export var shader_atmosphere_horizon_level: float = -0.035:
    set(v):
        shader_atmosphere_horizon_level = clampf(v, -0.2, 0.2)
        _set_shader_param("atmosphere_horizon_level", shader_atmosphere_horizon_level)
@export var shader_atmosphere_height: float = 0.24:
    set(v):
        shader_atmosphere_height = clampf(v, 0.02, 0.6)
        _set_shader_param("atmosphere_height", shader_atmosphere_height)
@export var shader_atmosphere_density: float = 0.46:
    set(v):
        shader_atmosphere_density = clampf(v, 0.0, 2.0)
        _set_shader_param("atmosphere_density", shader_atmosphere_density)
@export var shader_atmosphere_sun_scatter: float = 0.34:
    set(v):
        shader_atmosphere_sun_scatter = clampf(v, 0.0, 2.0)
        _set_shader_param("atmosphere_sun_scatter", shader_atmosphere_sun_scatter)
@export var shader_atmosphere_sunset_boost: float = 1.35:
    set(v):
        shader_atmosphere_sunset_boost = clampf(v, 0.0, 3.0)
        _set_shader_param("atmosphere_sunset_boost", shader_atmosphere_sunset_boost)

@export_group("Sky Shader: GI (SDFGI Fill)")
@export var gi_day_tint: Color = Color(0.8, 0.75, 0.7, 1.0):
    set(v):
        gi_day_tint = v
        _update_sun_transform()
@export var gi_day_energy: float = 0.6:
    set(v):
        gi_day_energy = v
        _update_sun_transform()
@export var gi_night_tint: Color = Color(0.2, 0.4, 0.8, 1.0):
    set(v):
        gi_night_tint = v
        _update_sun_transform()
@export var gi_night_energy: float = 2.0:
    set(v):
        gi_night_energy = v
        _update_sun_transform()



@export_group("SDFGI Workarounds")
@export var vol_fog_ambient_inject_sunset_boost: float = 0.4:
    set(v): vol_fog_ambient_inject_sunset_boost = v; _update_sun_transform()
@export var vol_fog_emission_dip_color: Color = Color(0.0, 0.0, 0.0):
    set(v): vol_fog_emission_dip_color = v; _update_sun_transform()
@export var vol_fog_emission_dip_energy: float = 0.0:
    set(v): vol_fog_emission_dip_energy = v; _update_sun_transform()



func _ready() -> void:
    _rendered_day = day_of_year
    _rendered_time = time_of_day
    _is_ready = true

    _refresh()
    set_process(true)



func _process(_delta: float) -> void:
    _advance_cloud_motion(_delta)
    _advance_cloud_evolution(_delta)
    _advance_time_transition(_delta)
    _update_effect()

func apply_now() -> void:
    _init_sky()
    _request_time_update(true)
    _update_effect()

func set_weather_overrides(precipitation: float, storm_factor: float, lightning_flash: float, local_emission_scale: float = 1.0) -> void:
    var next_precipitation := clampf(precipitation, 0.0, 1.0)
    var next_storm_factor := clampf(storm_factor, 0.0, 1.0)
    var next_lightning_flash := clampf(lightning_flash, 0.0, 1.0)
    var next_local_emission_scale := clampf(local_emission_scale, 0.0, 1.0)
    var changed := (
        absf(_weather_precipitation - next_precipitation) > 0.0001
        or absf(_weather_storm_factor - next_storm_factor) > 0.0001
        or absf(_weather_lightning_flash - next_lightning_flash) > 0.0001
        or absf(_weather_local_emission_scale - next_local_emission_scale) > 0.0001
    )

    _weather_precipitation = next_precipitation
    _weather_storm_factor = next_storm_factor
    _weather_lightning_flash = next_lightning_flash
    _weather_local_emission_scale = next_local_emission_scale

    if changed and is_inside_tree() and _is_ready:
        _update_sun_transform()
        _update_effect()


func clear_weather_overrides() -> void:
    set_weather_overrides(0.0, 0.0, 0.0, 1.0)


func _refresh() -> void:
    if not is_inside_tree():
        return

    _environment = _get_environment()
    _light = _get_directional_light()

    _remove_sunshafts_compositor_effect()
    _install_sunshafts_compositor_effect()
    _init_sky()
    _ensure_weather_fog_curve()
    _update_sun_transform()
    _update_cloud_time()
    _update_cloud_wind()

    _success("(Re)Initialized")



func _get_directional_light() -> DirectionalLight3D:
    if not is_inside_tree(): return null
    if not directional_light_path.is_empty():
        return get_node_or_null(directional_light_path) as DirectionalLight3D
    else:
        return null

func _get_world_environment() -> WorldEnvironment:
    if not world_environment_path.is_empty():
        return get_node_or_null(world_environment_path)
    return null

func _get_environment() -> Environment:
    var world_environment := _get_world_environment()
    if world_environment:
        return world_environment.environment
    return null

func _get_compositor() -> Compositor:
    if Engine.is_editor_hint():
        return EditorInterface.get_editor_viewport_3d(0).get_camera_3d().compositor
    else:
        return get_viewport().get_camera_3d().compositor

func _set_compositor(compositor: Compositor):
    if Engine.is_editor_hint():
        EditorInterface.get_editor_viewport_3d(0).get_camera_3d().compositor = compositor
    else:
        get_viewport().get_camera_3d().compositor = compositor

func _init_sky() -> void:
    if not _environment:
        return

    _environment.sky = Sky.new()

    if not _sky_material:
        _sky_material = ShaderMaterial.new()
        _sky_material.shader = FILMIC_SKY_SHADER

    if not _cloud_texture_a:
        _cloud_texture_a = NoiseTexture2D.new()
        _cloud_texture_a.seamless = true
        var noise := FastNoiseLite.new()
        _cloud_texture_a.noise = noise

    if not _cloud_texture_b:
        _cloud_texture_b = NoiseTexture2D.new()
        _cloud_texture_b.seamless = true
        var noise := FastNoiseLite.new()
        _cloud_texture_b.noise = noise

    _cloud_texture_a.noise.seed = clouds_generator_seed_a
    _cloud_texture_a.noise.frequency = clouds_generator_frequency_a * 0.01
    _cloud_texture_b.noise.seed = clouds_generator_seed_b
    _cloud_texture_b.noise.frequency = clouds_generator_frequency_b * 0.01

    _environment.sky.sky_material = _sky_material

    if not _compositor_effect:
        _install_sunshafts_compositor_effect()

    _sync_sky_shader_params()


func _set_shader_param(param_name: String, value: Variant) -> void:
    if _sky_material:
        _sky_material.set_shader_parameter(param_name, value)

func _sync_sky_shader_params() -> void:
    if not _sky_material:
        return

    _sky_material.set_shader_parameter("lower_sky_color", shader_lower_sky_color)
    _sky_material.set_shader_parameter("horizon_color", shader_horizon_color)
    _sky_material.set_shader_parameter("zenith_color", shader_zenith_color)
    _sky_material.set_shader_parameter("sky_energy", shader_sky_energy)
    _sky_material.set_shader_parameter("horizon_height", shader_horizon_height)
    _sky_material.set_shader_parameter("horizon_softness", shader_horizon_softness)
    _sky_material.set_shader_parameter("zenith_curve", shader_zenith_curve)
    _sky_material.set_shader_parameter("horizon_glow_strength", shader_horizon_glow_strength)
    _sky_material.set_shader_parameter("atmosphere_horizon_level", shader_atmosphere_horizon_level)
    _sky_material.set_shader_parameter("atmosphere_height", shader_atmosphere_height)
    _sky_material.set_shader_parameter("atmosphere_density", shader_atmosphere_density)
    _sky_material.set_shader_parameter("atmosphere_sun_scatter", shader_atmosphere_sun_scatter)
    _sky_material.set_shader_parameter("atmosphere_sunset_boost", shader_atmosphere_sunset_boost)

    _sky_material.set_shader_parameter("sunset_bottom_color", shader_sunset_bottom_color)
    _sky_material.set_shader_parameter("sunset_horizon_color", shader_sunset_horizon_color)
    _sky_material.set_shader_parameter("sunset_zenith_color", shader_sunset_zenith_color)
    _sky_material.set_shader_parameter("sunset_cloud_color", shader_sunset_cloud_color)
    _sky_material.set_shader_parameter("sunset_sun_color", sun_sunset_color)

    _sky_material.set_shader_parameter("night_lower_sky_color", shader_night_lower_sky_color)
    _sky_material.set_shader_parameter("night_horizon_color", shader_night_horizon_color)
    _sky_material.set_shader_parameter("night_zenith_color", shader_night_zenith_color)
    _sky_material.set_shader_parameter("night_sky_energy", shader_night_sky_energy)
    _sky_material.set_shader_parameter("stars_color", shader_stars_color)
    _sky_material.set_shader_parameter("stars_energy", shader_stars_energy)
    _sky_material.set_shader_parameter("stars_size_min", shader_stars_size_min)
    _sky_material.set_shader_parameter("stars_size_max", shader_stars_size_max)
    _sky_material.set_shader_parameter("stars_edge_softness", shader_stars_edge_softness)

    _sky_material.set_shader_parameter("sun_color", sun_day_color)
    _sky_material.set_shader_parameter("sun_disk_size", sun_disk_size)
    _sky_material.set_shader_parameter("sun_disk_softness", sun_disk_softness)
    _sky_material.set_shader_parameter("sun_disk_strength", sun_disk_strength)
    _sky_material.set_shader_parameter("sun_halo_size", sun_halo_size)
    _sky_material.set_shader_parameter("sun_halo_strength", sun_halo_strength)
    _sky_material.set_shader_parameter("sun_atmosphere_size", sun_atmosphere_size)
    _sky_material.set_shader_parameter("sun_atmosphere_strength", sun_atmosphere_strength)
    _sky_material.set_shader_parameter("sun_energy_scale", sun_energy_scale)

    _sky_material.set_shader_parameter("moon_color", moon_color)
    _sky_material.set_shader_parameter("moon_size", moon_size)
    _sky_material.set_shader_parameter("moon_glow_strength", moon_glow_strength)
    _sky_material.set_shader_parameter("moon_eclipse_size", moon_eclipse_size)
    _sky_material.set_shader_parameter("moon_texture", moon_texture)

    _sky_material.set_shader_parameter("cloud_tex_a", _cloud_texture_a)
    _sky_material.set_shader_parameter("cloud_tex_b", _cloud_texture_b)
    _sky_material.set_shader_parameter("cloud_scroll_a", clouds_scroll_a)
    _sky_material.set_shader_parameter("cloud_scroll_b", clouds_scroll_b)
    _sky_material.set_shader_parameter("cloud_scale_a", clouds_scale_a)
    _sky_material.set_shader_parameter("cloud_scale_b", clouds_scale_b)
    _sky_material.set_shader_parameter("cloud_plane_height", clouds_plane_height)
    _sky_material.set_shader_parameter("cloud_plane_curve", clouds_plane_curve)
    _sky_material.set_shader_parameter("cloud_warp_strength", clouds_warp_strength)
    _sky_material.set_shader_parameter("cloud_coverage", clouds_coverage)
    _sky_material.set_shader_parameter("cloud_softness", clouds_softness)
    _sky_material.set_shader_parameter("cloud_opacity", clouds_opacity)
    _sky_material.set_shader_parameter("cloud_horizon_fade", clouds_horizon_fade)
    _sky_material.set_shader_parameter("cloud_top_fade", clouds_top_fade)
    _sky_material.set_shader_parameter("cloud_light_color", clouds_color_light)
    _sky_material.set_shader_parameter("cloud_shadow_color", clouds_color_shadow)
    _sky_material.set_shader_parameter("cloud_forward_scatter", clouds_forward_scatter)
    _sky_material.set_shader_parameter("cloud_backscatter", clouds_backscatter)
    _sky_material.set_shader_parameter("sun_cloud_occlusion", clouds_sun_occlusion)

    _sky_material.set_shader_parameter("cloud_time", _get_cloud_time_value())
    _sky_material.set_shader_parameter("cloud_motion_time", _cloud_motion_time)
    _sky_material.set_shader_parameter("cloud_evolution_time", _cloud_evolution_time)
    _sky_material.set_shader_parameter("cloud_motion_scale", clouds_motion_scale)
    _sky_material.set_shader_parameter("cloud_evolution_strength", clouds_evolution_strength)
    _sky_material.set_shader_parameter("cloud_evolution_scale", clouds_evolution_scale)
    _apply_cloud_wind_params()

func _get_cloud_time_value() -> float:
    return ((float(_rendered_day - 1) * 24.0) + _rendered_time) * clouds_time_scale


func _update_cloud_time() -> void:
    _set_shader_param("cloud_time", _get_cloud_time_value())


func _advance_cloud_motion(delta: float) -> void:
    _cloud_motion_time += delta * _get_global_wind_speed() * clouds_motion_scale
    _set_shader_param("cloud_motion_time", _cloud_motion_time)


func _advance_cloud_evolution(delta: float) -> void:
    _cloud_evolution_time += delta * clouds_evolution_speed
    _set_shader_param("cloud_evolution_time", _cloud_evolution_time)


func _get_global_wind_speed() -> float:
    var viewport := get_viewport()
    var world_3d := viewport.get_world_3d() if viewport != null else null
    var speed := WeatherServer.get_weather_controlled_wind_speed(world_3d)
    return speed * clouds_wind_speed_multiplier


func _apply_cloud_wind_params() -> void:
    _sky_material.set_shader_parameter("cloud_wind_direction", WeatherServer.get_global_wind_direction())
    _sky_material.set_shader_parameter("cloud_wind_speed", _get_global_wind_speed())


func _update_cloud_wind() -> void:
    if _sky_material:
        _apply_cloud_wind_params()


func _request_time_update(snap: bool = false) -> void:
    if not is_inside_tree():
        return
    var target_hours := float(day_of_year) * 24.0 + time_of_day
    var current_hours := float(_rendered_day) * 24.0 + _rendered_time
    var same_day_wrap := day_of_year == _rendered_day and absf(time_of_day - _rendered_time) > 12.0

    if Engine.is_editor_hint() or time_transition_duration <= 0.0 or snap:
        _stop_time_transition()
        _apply_total_hours(target_hours)
        return

    if same_day_wrap:
        var wrapped_target_time := _rendered_time + _get_wrapped_time_delta(_rendered_time, time_of_day)
        var wrapped_delta := wrapped_target_time - _rendered_time
        if absf(wrapped_delta) <= 0.0001:
            _stop_time_transition()
            _apply_wrapped_time_of_day(wrapped_target_time)
            return
        _time_transition_wrapped = true
        _time_transition_target_unwrapped_time = wrapped_target_time
        _time_transition_speed_hours_per_second = wrapped_delta / time_transition_duration
        _time_transition_active = true
        return

    var total_delta := target_hours - current_hours
    if absf(total_delta) <= 0.0001:
        _stop_time_transition()
        _apply_total_hours(target_hours)
        return
    _time_transition_wrapped = false
    _time_transition_target_total_hours = target_hours
    _time_transition_speed_hours_per_second = total_delta / time_transition_duration
    _time_transition_active = true


func _get_wrapped_time_delta(from_time: float, to_time: float) -> float:
    return wrapf((to_time - from_time) + 12.0, 0.0, 24.0) - 12.0


func _advance_time_transition(delta: float) -> void:
    if not _time_transition_active or delta <= 0.0:
        return

    var step := absf(_time_transition_speed_hours_per_second) * delta
    if _time_transition_wrapped:
        var next_unwrapped_time := move_toward(_rendered_time, _time_transition_target_unwrapped_time, step)
        _apply_wrapped_time_of_day(next_unwrapped_time)
        if absf(next_unwrapped_time - _time_transition_target_unwrapped_time) <= 0.0001:
            _stop_time_transition()
        return

    var current_hours := float(_rendered_day) * 24.0 + _rendered_time
    var next_total_hours := move_toward(current_hours, _time_transition_target_total_hours, step)
    _apply_total_hours(next_total_hours)
    if absf(next_total_hours - _time_transition_target_total_hours) <= 0.0001:
        _stop_time_transition()


func _stop_time_transition() -> void:
    _time_transition_active = false
    _time_transition_wrapped = false
    _time_transition_speed_hours_per_second = 0.0


func _apply_wrapped_time_of_day(unwrapped_time: float) -> void:
    _rendered_day = day_of_year
    _rendered_time = wrapf(unwrapped_time, 0.0, 24.0)
    _update_sun_transform()
    _update_cloud_time()
    time_changed.emit(_rendered_day, _rendered_time)

func _apply_total_hours(total_hours: float) -> void:
    var day_new = int(floor(total_hours / 24.0))
    var new_time = fmod(total_hours, 24.0)
    if day_new != _rendered_day:
        day_changed.emit(day_new)
    _rendered_day = day_new
    _rendered_time = new_time

    _update_sun_transform()
    _update_cloud_time()
    time_changed.emit(_rendered_day, _rendered_time)

func _update_sun_transform() -> void:
    if not is_inside_tree():
        return

    var light = _get_directional_light()
    var day_current = float(_rendered_day) + _rendered_time / 24.0
    var moon_phase = fmod( day_current / 29.53, 1.0)
    moon_phase_debug = moon_phase

    var theta_sun = deg_to_rad(360.0 / 365.0 * ( day_current + 10.0))
    var declination_sun = deg_to_rad(-23.45) * cos(theta_sun)

    var theta_moon = theta_sun - moon_phase * TAU
    var declination_moon = deg_to_rad(-23.45) * cos(theta_moon) + deg_to_rad(5.14) * sin(theta_moon)

    var hour_angle = deg_to_rad(15.0 * (_rendered_time - 12.0))
    var lat_rad = deg_to_rad(latitude)

    var get_dir = func(ha: float, dec: float) -> Vector3:
        var y = sin(lat_rad) * sin(dec) + cos(lat_rad) * cos(dec) * cos(ha)
        var x = -cos(dec) * sin(ha)
        var z = sin(lat_rad) * cos(dec) * cos(ha) - cos(lat_rad) * sin(dec)
        return Vector3(x, y, z).normalized()

    var sun_dir = get_dir.call(hour_angle, declination_sun)
    var moon_hour_angle = hour_angle - moon_phase * TAU
    var moon_dir = get_dir.call(moon_hour_angle, declination_moon)

    var sidereal_time = deg_to_rad( day_current * 360.0 + _rendered_time * 15.0)
    var celestial_basis = Basis()
    celestial_basis = celestial_basis.rotated(Vector3.RIGHT, lat_rad - PI / 2.0)
    celestial_basis = celestial_basis.rotated(Vector3.UP, -sidereal_time)

    _set_shader_param("custom_sun_dir", sun_dir)
    _set_shader_param("custom_moon_dir", moon_dir)
    _set_shader_param("celestial_matrix", celestial_basis)

    var dir_to_basis = func(dir: Vector3) -> Basis:
        var up = Vector3.UP
        if abs(dir.y) > 0.999:
            up = Vector3.RIGHT
        var right = up.cross(dir).normalized()
        var new_up = dir.cross(right).normalized()
        return Basis(right, new_up, dir)

    var s_alt = sun_dir.y
    var m_alt = moon_dir.y

    var day_blend = smoothstep(-0.05, 0.15, s_alt)
    var sunset_blend = smoothstep(-0.1, 0.02, s_alt) * (1.0 - smoothstep(0.02, 0.25, s_alt))

    var sun_energy = day_light_energy * smoothstep(-0.05, 0.05, s_alt)
    var moon_energy = night_light_energy * smoothstep(0.0, 0.05, m_alt) * (1.0 - smoothstep(-0.1, 0.0, s_alt))

    if sun_energy >= moon_energy:
        if light:
            light.global_transform.basis = dir_to_basis.call(sun_dir)
            light.light_color = day_light_color.lerp(sunset_light_color, sunset_blend)
            light.light_energy = sun_energy
        _is_daytime = true
    else:
        if light:
            light.global_transform.basis = dir_to_basis.call(moon_dir)
            light.light_color = night_light_color
            light.light_energy = moon_energy
        _is_daytime = false

    _set_shader_param("gi_tint", gi_night_tint.lerp(gi_day_tint, day_blend))
    _set_shader_param("gi_energy_multiplier", lerp(gi_night_energy, gi_day_energy, day_blend) + sunset_blend * 0.5)

    if _environment:
        var env = _environment
        env.ambient_light_color =  night_ambient_color.lerp( day_ambient_color, day_blend)
        env.ambient_light_energy = lerp( night_ambient_energy,  day_ambient_energy, pow(day_blend, 0.5)) + sunset_blend * 0.8

        var fog_day_mix =  night_fog_color.lerp( day_fog_color, day_blend)
        env.fog_light_color = fog_day_mix.lerp(sunset_light_color, sunset_blend * 0.5)
        env.fog_density = lerp( night_fog_density,  day_fog_density, day_blend)
        env.fog_sky_affect = lerp( night_fog_sky_affect,  day_fog_sky_affect, day_blend)
        env.fog_depth_begin = lerp( night_fog_distance_begin,  day_fog_distance_begin, day_blend)
        env.fog_depth_end = lerp(night_fog_distance,  day_fog_distance, day_blend)

        var vol_day_mix =  night_vol_fog_albedo.lerp( day_vol_fog_albedo, day_blend)
        env.volumetric_fog_albedo = vol_day_mix.lerp(sunset_light_color, sunset_blend * 0.3)

        current_vol_fog_min_density = lerp( night_vol_fog_min_density,  day_vol_fog_min_density, day_blend)
        current_vol_fog_max_density = lerp( night_vol_fog_density,  day_vol_fog_density, day_blend)

        if manage_vol_fog_density:
            env.volumetric_fog_density = current_vol_fog_max_density

        env.volumetric_fog_sky_affect = lerp( night_vol_fog_sky_affect,  day_vol_fog_sky_affect, day_blend)
        env.volumetric_fog_length = lerp( night_vol_fog_length,  day_vol_fog_length, day_blend)

        # SDFGI Workarounds application
        var base_inject = lerp( night_vol_fog_ambient_inject,  day_vol_fog_ambient_inject, day_blend)

        var dip_center = 0.05
        var dip_width = 0.15
        var dip_factor = 1.0 - smoothstep(0.0, dip_width, abs(s_alt - dip_center))
        var dip_blend = smoothstep(0.0, 1.0, dip_factor)
        _apply_weather_overrides(env, light)
    else:
        _apply_weather_overrides(null, light)


func _apply_weather_overrides(env: Environment, light: DirectionalLight3D) -> void:
    var precipitation := clampf(_weather_precipitation, 0.0, 1.0)
    var storm_factor := clampf(_weather_storm_factor, 0.0, 1.0)
    var lightning_flash := clampf(_weather_lightning_flash, 0.0, 1.0)
    var local_emission_scale := clampf(_weather_local_emission_scale, 0.0, 1.0)
    var cloud_mix := clampf(precipitation * 0.8 + storm_factor * 0.55, 0.0, 1.0)
    var cloud_darkening := clampf(precipitation * 0.45 + storm_factor * 0.35, 0.0, 1.0)
    var weather_override_strength := maxf(weather_overcast_intensity, 0.0)
    var overcast_cooling := clampf((precipitation * 0.78 + storm_factor * 0.4) * weather_override_strength, 0.0, 1.0)

    _set_shader_param("cloud_coverage", lerpf(clouds_coverage, maxf(clouds_coverage, 0.88), cloud_mix))
    _set_shader_param("cloud_opacity", lerpf(clouds_opacity, maxf(clouds_opacity, 0.95), clampf(precipitation * 0.85 + storm_factor * 0.35, 0.0, 1.0)))
    _set_shader_param("cloud_shadow_color", clouds_color_shadow.lerp(Color(0.22, 0.24, 0.29, 1.0), cloud_darkening))
    _set_shader_param("cloud_light_color", clouds_color_light.lerp(Color(0.66, 0.7, 0.78, 1.0), clampf(precipitation * 0.35 + storm_factor * 0.2, 0.0, 1.0)))
    _set_shader_param("sun_cloud_occlusion", clampf(clouds_sun_occlusion + precipitation * 0.42 + storm_factor * 0.2, 0.0, 0.98))
    _set_shader_param("sky_energy", maxf(0.02, shader_sky_energy * (1.0 - precipitation * 0.46 - storm_factor * 0.18) + lightning_flash * 0.18))
    _set_shader_param("night_sky_energy", maxf(0.02, shader_night_sky_energy * (1.0 - precipitation * 0.34 - storm_factor * 0.16) + lightning_flash * 0.08))
    _set_shader_param("stars_energy", maxf(0.0, shader_stars_energy * (1.0 - cloud_mix * 0.98)))
    _set_shader_param("moon_color", moon_color.lerp(Color(0.045, 0.05, 0.06, 1.0), cloud_mix * 0.96))
    _set_shader_param("moon_size", lerpf(moon_size, moon_size * 0.72, cloud_mix * 0.85))
    _set_shader_param("moon_glow_strength", maxf(0.0, moon_glow_strength * (1.0 - cloud_mix * 0.96)))

    if light != null:
        light.light_energy = light.light_energy * maxf(0.14, 1.0 - (precipitation * 0.42 + storm_factor * 0.14) * weather_override_strength) + lightning_flash * lerpf(0.9, 5.6, storm_factor)
        light.light_color = light.light_color.lerp(Color(0.58, 0.62, 0.68, 1.0), overcast_cooling * 0.94)
        light.light_color = light.light_color.lerp(Color(0.83, 0.89, 1.0, 1.0), lightning_flash * 0.8)

    if env == null:
        return

    env.ambient_light_color = env.ambient_light_color.lerp(Color(0.38, 0.41, 0.46, 1.0), overcast_cooling * 0.82)
    env.ambient_light_energy *= maxf(0.18, 1.0 - (precipitation * 0.24 + storm_factor * 0.08) * weather_override_strength)

    var fog_weather_blend := _sample_weather_fog_curve(clampf((precipitation - 0.72) / 0.28, 0.0, 1.0))
    fog_weather_blend = clampf(fog_weather_blend + storm_factor * 0.18, 0.0, 1.0)

    env.fog_light_color = env.fog_light_color.lerp(Color(0.25, 0.28, 0.34, 1.0), overcast_cooling * 0.86)
    var weather_fog_density_add := (precipitation * weather_fog_density_boost * 0.0015 + storm_factor * weather_storm_fog_density_boost * 0.0025) * fog_weather_blend
    var weather_fog_distance_blend := fog_weather_blend
    var weather_fog_density_target_value := lerpf(env.fog_density, weather_fog_density_target, weather_fog_distance_blend)
    env.fog_density = clampf(maxf(
        env.fog_density * (1.0 + (precipitation * weather_fog_density_boost * 0.12 + storm_factor * weather_storm_fog_density_boost * 0.16) * fog_weather_blend) + weather_fog_density_add,
        weather_fog_density_target_value
    ), 0.0, 1.5)
    env.fog_sky_affect = lerpf(env.fog_sky_affect, weather_fog_sky_affect_target, weather_fog_distance_blend)
    env.fog_depth_begin = maxf(0.0, lerpf(env.fog_depth_begin, weather_fog_begin_distance, weather_fog_distance_blend))
    env.fog_depth_end = maxf(weather_fog_begin_distance + 1.0, lerpf(env.fog_depth_end, weather_fog_end_distance, weather_fog_distance_blend))

    current_vol_fog_min_density *= 1.0 + precipitation * 0.18
    var weather_volumetric_density_add := (precipitation * weather_volumetric_fog_boost * 0.003 + storm_factor * weather_storm_volumetric_fog_boost * 0.005) * fog_weather_blend
    current_vol_fog_max_density = current_vol_fog_max_density * (1.0 + (precipitation * weather_volumetric_fog_boost * 0.18 + storm_factor * weather_storm_volumetric_fog_boost * 0.22) * fog_weather_blend) + weather_volumetric_density_add

    env.volumetric_fog_albedo = env.volumetric_fog_albedo.lerp(Color(0.17, 0.19, 0.24, 1.0), overcast_cooling * 0.78)
    var weather_volumetric_density_target_value := lerpf(env.volumetric_fog_density, weather_volumetric_fog_density_target, weather_fog_distance_blend)
    env.volumetric_fog_density = clampf(maxf(
        maxf(env.volumetric_fog_density, current_vol_fog_max_density) + weather_volumetric_density_add,
        weather_volumetric_density_target_value
    ), 0.0, 2.0)
    env.volumetric_fog_sky_affect = lerpf(env.volumetric_fog_sky_affect, weather_volumetric_fog_sky_affect_target, weather_fog_distance_blend)
    env.volumetric_fog_length = maxf(2.0, env.volumetric_fog_length * (1.0 - precipitation * 0.08))
    var weather_volumetric_emission_blend := clampf(fog_weather_blend + storm_factor * 0.2, 0.0, 1.0)
    var weather_volumetric_emission := weather_volumetric_fog_emission_color * (weather_volumetric_fog_emission_energy * weather_volumetric_emission_blend * local_emission_scale)
    if lightning_flash > 0.0:
        weather_volumetric_emission = weather_volumetric_emission.lerp(Color(0.58, 0.66, 0.82, 1.0) * (lightning_flash * 0.55), lightning_flash * 0.35)
    env.volumetric_fog_emission = weather_volumetric_emission

    if lightning_flash > 0.0:
        env.ambient_light_color = env.ambient_light_color.lerp(Color(0.76, 0.82, 0.96, 1.0), lightning_flash * 0.4)
        env.ambient_light_energy += lightning_flash * (0.28 + storm_factor * 0.35)
        env.fog_light_color = env.fog_light_color.lerp(Color(0.74, 0.82, 0.96, 1.0), lightning_flash * 0.7)
        env.volumetric_fog_albedo = env.volumetric_fog_albedo.lerp(Color(0.58, 0.66, 0.82, 1.0), lightning_flash * 0.35)


func _ensure_weather_fog_curve() -> void:
    if weather_fog_curve == null:
        weather_fog_curve = Curve.new()
    if weather_fog_curve.get_point_count() > 0:
        return

    weather_fog_curve.add_point(Vector2(0.0, 0.0))
    weather_fog_curve.add_point(Vector2(1.0, 1.0))


func _sample_weather_fog_curve(value: float) -> float:
    var t := clampf(value, 0.0, 1.0)
    _ensure_weather_fog_curve()
    if weather_fog_curve == null:
        return t
    return clampf(weather_fog_curve.sample_baked(t), 0.0, 1.0)


func _install_sunshafts_compositor_effect() -> void:
    var compositor = _get_compositor()
    if not compositor:
        compositor = Compositor.new()
    else:
        compositor = compositor.duplicate(true) as Compositor
    _set_compositor(compositor)

    var effect_position: int = compositor.compositor_effects.find_custom(
        func(x): x.get_script() == SUN_SHAFTS_EFFECT_SCRIPT
    )

    if effect_position > -1:
        _compositor_effect = compositor.compositor_effects.get(effect_position)
    else:
        _compositor_effect = SUN_SHAFTS_EFFECT_SCRIPT.new()
        compositor.compositor_effects.insert(0, _compositor_effect)
        _success("Installed sunshafts compositor effect")


func _remove_sunshafts_compositor_effect() -> void:
    var compositor := _get_compositor()
    if not compositor:
        _compositor_effect = null
        return

    var effect_position: int = compositor.compositor_effects.find_custom(
        func(x): x.get_script() == SUN_SHAFTS_EFFECT_SCRIPT
    )
    if effect_position > -1:
        compositor.compositor_effects.remove_at(effect_position)
        _compositor_effect = null

func _update_effect() -> void:
    if not _compositor_effect: return

    if not sunshafts_enabled or not _is_daytime:
        _compositor_effect.set("sun_visible", false)
        return

    var light = _get_directional_light()
    if not light:
        _compositor_effect.set("sun_visible", false)
        return

    var camera = _get_active_camera()
    if not camera:
        _compositor_effect.set("sun_visible", false)
        return

    var viewport_size = _get_active_viewport_size()
    if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
        _compositor_effect.set("sun_visible", false)
        return

    var sun_dir = light.global_transform.basis.z.normalized()
    var sun_world_pos = camera.global_position + (sun_dir * sunshafts_distance)

    if camera.is_position_behind(sun_world_pos):
        _compositor_effect.set("sun_visible", false)
        return

    var screen_pos = camera.unproject_position(sun_world_pos)
    _compositor_effect.set("sun_screen_uv", Vector2(screen_pos.x / viewport_size.x, screen_pos.y / viewport_size.y))
    _compositor_effect.set("sun_visible", true)

    var weather_occlusion := clampf(_weather_precipitation * 0.85 + _weather_storm_factor * 0.25, 0.0, 0.96)
    var shafts_visibility := 1.0 - weather_occlusion
    if shafts_visibility <= 0.02:
        _compositor_effect.set("sun_visible", false)
        return

    _compositor_effect.set("shaft_color", sunshafts_shaft_color.lerp(Color(0.72, 0.74, 0.78, 1.0), weather_occlusion * 0.5))
    _compositor_effect.set("density", sunshafts_density * shafts_visibility)
    _compositor_effect.set("bright_threshold", sunshafts_bright_threshold)
    _compositor_effect.set("weight", sunshafts_weight * shafts_visibility)
    _compositor_effect.set("decay", sunshafts_decay)
    _compositor_effect.set("exposure", sunshafts_exposure * shafts_visibility)
    _compositor_effect.set("max_radius", sunshafts_max_radius)

func _get_active_camera() -> Camera3D:
    if not is_inside_tree(): return null
    if Engine.is_editor_hint():
        var editor_iface = Engine.get_singleton(&"EditorInterface")
        if editor_iface:
            var vp = editor_iface.get_editor_viewport_3d(0)
            if vp: return vp.get_camera_3d()
    var vp = get_viewport()
    return vp.get_camera_3d() if vp else null

func _get_active_viewport_size() -> Vector2:
    if not is_inside_tree(): return Vector2.ZERO
    if Engine.is_editor_hint():
        var editor_iface = Engine.get_singleton(&"EditorInterface")
        if editor_iface:
            var vp = editor_iface.get_editor_viewport_3d(0)
            if vp: return vp.get_visible_rect().size
    var vp = get_viewport()
    return vp.get_visible_rect().size if vp else Vector2.ZERO


func get_current_vol_fog_min_density() -> float:
    return current_vol_fog_min_density

func get_current_vol_fog_max_density() -> float:
    return current_vol_fog_max_density

func get_current_vol_fog_density() -> float:
    return current_vol_fog_max_density
