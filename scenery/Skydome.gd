@tool
class_name Skydome
extends Node

signal time_changed(day: int, time: float)
signal day_changed(day: int)

@export var time_transition_duration: float = 2.0
var _rendered_day: int = 180
var _rendered_time: float = 12.0
var _time_tween: Tween

const SUN_SHAFTS_EFFECT_SCRIPT := preload("res://scenery/SunShaftsCompositorEffect.gd")
const SKY_MATERIAL_RES := preload("res://scenery/materials/M_filmic_procedural_sky.tres")
const SKY_RES := preload("res://materials/sky_filmic.tres")

@export_group("Time & Date")
@export_range(1, 365) var day_of_year: int = 180:
    set(v):
        day_of_year = v
        _request_time_update()
@export_range(0.0, 24.0) var time_of_day: float = 12.0:
    set(v):
        time_of_day = v
        _request_time_update()
@export_range(-90.0, 90.0) var latitude: float = 45.0:
    set(v):
        latitude = v
        _update_sun_transform()

@export_group("Light Settings")
@export var sun_light_color: Color = Color(1.0, 0.93, 0.85):
    set(v):
        sun_light_color = v
        _update_sun_transform()
@export var sunset_light_color: Color = Color(1.0, 0.45, 0.15):
    set(v):
        sunset_light_color = v
        _update_sun_transform()
@export var sun_light_energy: float = 1.28:
    set(v):
        sun_light_energy = v
        _update_sun_transform()
@export var moon_light_color: Color = Color(0.6, 0.8, 1.0):
    set(v):
        moon_light_color = v
        _update_sun_transform()
@export var moon_light_energy: float = 0.2:
    set(v):
        moon_light_energy = v
        _update_sun_transform()

@export_group("Environment & Fog")
@export var ambient_color_day: Color = Color(0.91, 0.85, 0.69):
    set(v): ambient_color_day = v; _update_sun_transform()
@export var ambient_color_night: Color = Color(0.02, 0.03, 0.06):
    set(v): ambient_color_night = v; _update_sun_transform()
@export var ambient_energy_day: float = 1.5:
    set(v): ambient_energy_day = v; _update_sun_transform()
@export var ambient_energy_night: float = 0.1:
    set(v): ambient_energy_night = v; _update_sun_transform()

@export var fog_color_day: Color = Color(1.0, 0.95, 0.91):
    set(v): fog_color_day = v; _update_sun_transform()
@export var fog_color_night: Color = Color(0.04, 0.06, 0.12):
    set(v): fog_color_night = v; _update_sun_transform()
@export var fog_density_day: float = 0.005:
    set(v): fog_density_day = v; _update_sun_transform()
@export var fog_density_night: float = 0.02:
    set(v): fog_density_night = v; _update_sun_transform()
@export var fog_sky_affect_day: float = 0.15:
    set(v): fog_sky_affect_day = v; _update_sun_transform()
@export var fog_sky_affect_night: float = 0.15:
    set(v): fog_sky_affect_night = v; _update_sun_transform()
@export var fog_distance_begin_day: float = 2.6:
    set(v): fog_distance_begin_day = v; _update_sun_transform()
@export var fog_distance_begin_night: float = 2.6:
    set(v): fog_distance_begin_night = v; _update_sun_transform()
@export var fog_distance_day: float = 470.0:
    set(v): fog_distance_day = v; _update_sun_transform()
@export var fog_distance_night: float = 200.0:
    set(v): fog_distance_night = v; _update_sun_transform()

@export var vol_fog_albedo_day: Color = Color(0.77, 0.74, 0.7):
    set(v): vol_fog_albedo_day = v; _update_sun_transform()
@export var vol_fog_albedo_night: Color = Color(0.15, 0.18, 0.25):
    set(v): vol_fog_albedo_night = v; _update_sun_transform()
@export var vol_fog_density_day: float = 0.015:
    set(v): vol_fog_density_day = v; _update_sun_transform()
@export var vol_fog_density_night: float = 0.05:
    set(v): vol_fog_density_night = v; _update_sun_transform()
@export var vol_fog_sky_affect_day: float = 0.3:
    set(v): vol_fog_sky_affect_day = v; _update_sun_transform()
@export var vol_fog_sky_affect_night: float = 0.25:
    set(v): vol_fog_sky_affect_night = v; _update_sun_transform()
@export var vol_fog_length_day: float = 8.0:
    set(v): vol_fog_length_day = v; _update_sun_transform()
@export var vol_fog_length_night: float = 3.0:
    set(v): vol_fog_length_night = v; _update_sun_transform()

@export var manage_vol_fog_density: bool = true:
    set(v): manage_vol_fog_density = v; _update_sun_transform()

var current_vol_fog_min_density: float = 0.0
var current_vol_fog_max_density: float = 0.0

@export var vol_fog_min_density_day: float = 0.005:
    set(v): vol_fog_min_density_day = v; _update_sun_transform()
@export var vol_fog_min_density_night: float = 0.01:
    set(v): vol_fog_min_density_night = v; _update_sun_transform()
@export_group("SDFGI & Fog Workarounds")
@export var vol_fog_ambient_inject_day: float = 0.04:
    set(v): vol_fog_ambient_inject_day = v; _update_sun_transform()
@export var vol_fog_ambient_inject_night: float = 0.1:
    set(v): vol_fog_ambient_inject_night = v; _update_sun_transform()
@export var vol_fog_ambient_inject_sunset_boost: float = 0.4:
    set(v): vol_fog_ambient_inject_sunset_boost = v; _update_sun_transform()

@export var vol_fog_emission_dip_color: Color = Color(0.0, 0.0, 0.0):
    set(v): vol_fog_emission_dip_color = v; _update_sun_transform()
@export var vol_fog_emission_dip_energy: float = 0.0:
    set(v): vol_fog_emission_dip_energy = v; _update_sun_transform()

@export var sky_contribution_day: float = 0.25:
    set(v): sky_contribution_day = v; _update_sun_transform()
@export var sky_contribution_night: float = 0.8:
    set(v): sky_contribution_night = v; _update_sun_transform()

@export_group("Nodes")
@export var directional_light_path: NodePath:
    set(v):
        directional_light_path = v
        _refresh()
@export var world_environment_path: NodePath:
    set(v):
        world_environment_path = v
        _refresh()

@export_group("Sunshafts")
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

var _sky_material: ShaderMaterial
var _compositor_effect: CompositorEffect
var _is_ready: bool = false
var _is_daytime: bool = true

@export_group("Debug")
@export_range(0.0, 1.0) var moon_phase_debug: float

@export_group("Sky Shader: DaySky")
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
@export var shader_horizon_height: float = 0.178:
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

@export_group("Sky Shader: Sunset")
@export var shader_sunset_bottom_color: Color = Color(1.0, 0.5, 0.2, 1):
    set(v): shader_sunset_bottom_color = v; _set_shader_param("sunset_bottom_color", v)
@export var shader_sunset_horizon_color: Color = Color(0.8, 0.2, 0.05, 1):
    set(v): shader_sunset_horizon_color = v; _set_shader_param("sunset_horizon_color", v)
@export var shader_sunset_zenith_color: Color = Color(0.4, 0.3, 0.5, 1):
    set(v): shader_sunset_zenith_color = v; _set_shader_param("sunset_zenith_color", v)
@export var shader_sunset_cloud_color: Color = Color(1.0, 0.4, 0.15, 1):
    set(v): shader_sunset_cloud_color = v; _set_shader_param("sunset_cloud_color", v)
@export var shader_sunset_sun_color: Color = Color(1.0, 0.4, 0.1, 1):
    set(v): shader_sunset_sun_color = v; _set_shader_param("sunset_sun_color", v)

@export_group("Sky Shader: NightSky")
@export var shader_night_lower_sky_color: Color = Color(0.03, 0.05, 0.09, 1):
    set(v):
        shader_night_lower_sky_color = v
        _set_shader_param("night_lower_sky_color", v)
@export var shader_night_horizon_color: Color = Color(0.06, 0.1, 0.18, 1):
    set(v):
        shader_night_horizon_color = v
        _set_shader_param("night_horizon_color", v)
@export var shader_night_zenith_color: Color = Color(0.01, 0.015, 0.03, 1):
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

@export_group("Sky Shader: Sun")
@export var shader_sun_color: Color = Color(1, 0.98, 0.9, 1):
    set(v):
        shader_sun_color = v
        _set_shader_param("sun_color", v)
@export var shader_sun_disk_size: float = 0.067:
    set(v):
        shader_sun_disk_size = v
        _set_shader_param("sun_disk_size", v)
@export var shader_sun_disk_softness: float = 0.573:
    set(v):
        shader_sun_disk_softness = v
        _set_shader_param("sun_disk_softness", v)
@export var shader_sun_disk_strength: float = 0.63:
    set(v):
        shader_sun_disk_strength = v
        _set_shader_param("sun_disk_strength", v)
@export var shader_sun_halo_size: float = 0.411:
    set(v):
        shader_sun_halo_size = v
        _set_shader_param("sun_halo_size", v)
@export var shader_sun_halo_strength: float = 0.725:
    set(v):
        shader_sun_halo_strength = v
        _set_shader_param("sun_halo_strength", v)
@export var shader_sun_atmosphere_size: float = 0.463:
    set(v):
        shader_sun_atmosphere_size = v
        _set_shader_param("sun_atmosphere_size", v)
@export var shader_sun_atmosphere_strength: float = 0.301:
    set(v):
        shader_sun_atmosphere_strength = v
        _set_shader_param("sun_atmosphere_strength", v)
@export var shader_sun_energy_scale: float = 0.378:
    set(v):
        shader_sun_energy_scale = v
        _set_shader_param("sun_energy_scale", v)

@export_group("Sky Shader: Moon")
@export var shader_moon_tex: Texture2D:
    set(v): shader_moon_tex = v; _set_shader_param("moon_tex", v)
@export var shader_moon_color: Color = Color(0.9, 0.95, 1.0, 1):
    set(v):
        shader_moon_color = v
        _set_shader_param("moon_color", v)
@export var shader_moon_size: float = 1.0:
    set(v):
        shader_moon_size = v
        _set_shader_param("moon_size", v)
@export var shader_moon_glow_strength: float = 1.0:
    set(v):
        shader_moon_glow_strength = v
        _set_shader_param("moon_glow_strength", v)
@export var shader_moon_eclipse_size: float = 2.5:
    set(v):
        shader_moon_eclipse_size = v
        _set_shader_param("moon_eclipse_size", v)

@export_group("Sky Shader: Clouds")
@export var shader_cloud_time_scale: float = 6.0:
    set(v):
        shader_cloud_time_scale = v
        _update_cloud_time()
@export var shader_cloud_use_global_wind: bool = true:
    set(v):
        shader_cloud_use_global_wind = v
        _update_cloud_wind()
@export var shader_cloud_wind_direction: Vector2 = Vector2(0.8, 0.3):
    set(v):
        shader_cloud_wind_direction = v
        _update_cloud_wind()
@export var shader_cloud_wind_speed_multiplier: float = 1.0:
    set(v):
        shader_cloud_wind_speed_multiplier = v
        _update_cloud_wind()
@export var shader_cloud_motion_scale: float = 0.12:
    set(v):
        shader_cloud_motion_scale = v
        _set_shader_param("cloud_motion_scale", v)
@export var shader_cloud_tex_a: Texture2D = preload("res://scenery/materials/cloud_noise_a.tres"):
    set(v):
        shader_cloud_tex_a = v
        _set_shader_param("cloud_tex_a", v)
@export var shader_cloud_tex_b: Texture2D = preload("res://scenery/materials/cloud_noise_b.tres"):
    set(v):
        shader_cloud_tex_b = v
        _set_shader_param("cloud_tex_b", v)
@export var shader_cloud_scroll_a: Vector2 = Vector2(0.0012, 0.00015):
    set(v):
        shader_cloud_scroll_a = v
        _set_shader_param("cloud_scroll_a", v)
@export var shader_cloud_scroll_b: Vector2 = Vector2(-0.0018, 0.0004):
    set(v):
        shader_cloud_scroll_b = v
        _set_shader_param("cloud_scroll_b", v)
@export var shader_cloud_scale_a: Vector2 = Vector2(0.045, 0.055):
    set(v):
        shader_cloud_scale_a = v
        _set_shader_param("cloud_scale_a", v)
@export var shader_cloud_scale_b: Vector2 = Vector2(0.082, 0.125):
    set(v):
        shader_cloud_scale_b = v
        _set_shader_param("cloud_scale_b", v)
@export var shader_cloud_plane_height: float = 0.187:
    set(v):
        shader_cloud_plane_height = v
        _set_shader_param("cloud_plane_height", v)
@export var shader_cloud_plane_curve: float = 0.595:
    set(v):
        shader_cloud_plane_curve = v
        _set_shader_param("cloud_plane_curve", v)
@export var shader_cloud_warp_strength: float = 0.053:
    set(v):
        shader_cloud_warp_strength = v
        _set_shader_param("cloud_warp_strength", v)
@export var shader_cloud_coverage: float = 0.200:
    set(v):
        shader_cloud_coverage = v
        _set_shader_param("cloud_coverage", v)
@export var shader_cloud_softness: float = 0.046:
    set(v):
        shader_cloud_softness = v
        _set_shader_param("cloud_softness", v)
@export var shader_cloud_opacity: float = 0.441:
    set(v):
        shader_cloud_opacity = v
        _set_shader_param("cloud_opacity", v)
@export var shader_cloud_horizon_fade: float = 0.481:
    set(v):
        shader_cloud_horizon_fade = v
        _set_shader_param("cloud_horizon_fade", v)
@export var shader_cloud_top_fade: float = 0.118:
    set(v):
        shader_cloud_top_fade = v
        _set_shader_param("cloud_top_fade", v)
@export var shader_cloud_light_color: Color = Color(1, 0.98, 0.95, 1):
    set(v):
        shader_cloud_light_color = v
        _set_shader_param("cloud_light_color", v)
@export var shader_cloud_shadow_color: Color = Color(0.898, 0.898, 0.898, 1):
    set(v):
        shader_cloud_shadow_color = v
        _set_shader_param("cloud_shadow_color", v)
@export var shader_cloud_forward_scatter: float = 1.5:
    set(v):
        shader_cloud_forward_scatter = v
        _set_shader_param("cloud_forward_scatter", v)
@export var shader_cloud_backscatter: float = 0.390:
    set(v):
        shader_cloud_backscatter = v
        _set_shader_param("cloud_backscatter", v)
@export var shader_sun_cloud_occlusion: float = 0.406:
    set(v):
        shader_sun_cloud_occlusion = v
        _set_shader_param("sun_cloud_occlusion", v)


func _enter_tree() -> void:
    if Engine.is_editor_hint() or is_inside_tree():
        _rendered_day = day_of_year
    _rendered_time = time_of_day
    _init_sky()

func _ready() -> void:
    _is_ready = true
    _init_sky()
    _update_sun_transform()
    _update_cloud_time()
    _update_cloud_wind()
    set_process(true)

func _process(_delta: float) -> void:
    _update_effect()

func apply_now() -> void:
    _init_sky()
    _request_time_update(true)
    _update_effect()

func _refresh() -> void:
    if is_inside_tree():
        _init_sky()

func _get_directional_light() -> DirectionalLight3D:
    if not is_inside_tree(): return null
    if not directional_light_path.is_empty():
        return get_node_or_null(directional_light_path) as DirectionalLight3D
    var root = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
    if root:
        return root.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
    return null

func _get_world_environment() -> WorldEnvironment:
    if not is_inside_tree(): return null
    if not world_environment_path.is_empty():
        return get_node_or_null(world_environment_path) as WorldEnvironment
    var root = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
    if root:
        return root.find_child("WorldEnvironment", true, false) as WorldEnvironment
    return null

func _init_sky() -> void:
    var env_node = _get_world_environment()
    if not env_node: return
    var env = env_node.environment
    if not env: return

    if env.sky != SKY_RES:
        env.sky = SKY_RES

    _sky_material = SKY_MATERIAL_RES
    if _sky_material and _is_ready:
        _sync_shader_params()

func _set_shader_param(param_name: String, value: Variant) -> void:
    if not _sky_material:
        _sky_material = SKY_MATERIAL_RES
    if _sky_material:
        _sky_material.set_shader_parameter(param_name, value)

func _sync_shader_params() -> void:
    if not _sky_material: return
    _sky_material.set_shader_parameter("lower_sky_color", shader_lower_sky_color)
    _sky_material.set_shader_parameter("horizon_color", shader_horizon_color)
    _sky_material.set_shader_parameter("zenith_color", shader_zenith_color)
    _sky_material.set_shader_parameter("sky_energy", shader_sky_energy)
    _sky_material.set_shader_parameter("horizon_height", shader_horizon_height)
    _sky_material.set_shader_parameter("horizon_softness", shader_horizon_softness)
    _sky_material.set_shader_parameter("zenith_curve", shader_zenith_curve)
    _sky_material.set_shader_parameter("horizon_glow_strength", shader_horizon_glow_strength)

    _sky_material.set_shader_parameter("sunset_bottom_color", shader_sunset_bottom_color)
    _sky_material.set_shader_parameter("sunset_horizon_color", shader_sunset_horizon_color)
    _sky_material.set_shader_parameter("sunset_zenith_color", shader_sunset_zenith_color)
    _sky_material.set_shader_parameter("sunset_cloud_color", shader_sunset_cloud_color)
    _sky_material.set_shader_parameter("sunset_sun_color", shader_sunset_sun_color)

    _sky_material.set_shader_parameter("night_lower_sky_color", shader_night_lower_sky_color)
    _sky_material.set_shader_parameter("night_horizon_color", shader_night_horizon_color)
    _sky_material.set_shader_parameter("night_zenith_color", shader_night_zenith_color)
    _sky_material.set_shader_parameter("night_sky_energy", shader_night_sky_energy)
    _sky_material.set_shader_parameter("stars_color", shader_stars_color)
    _sky_material.set_shader_parameter("stars_energy", shader_stars_energy)

    _sky_material.set_shader_parameter("sun_color", shader_sun_color)
    _sky_material.set_shader_parameter("sun_disk_size", shader_sun_disk_size)
    _sky_material.set_shader_parameter("sun_disk_softness", shader_sun_disk_softness)
    _sky_material.set_shader_parameter("sun_disk_strength", shader_sun_disk_strength)
    _sky_material.set_shader_parameter("sun_halo_size", shader_sun_halo_size)
    _sky_material.set_shader_parameter("sun_halo_strength", shader_sun_halo_strength)
    _sky_material.set_shader_parameter("sun_atmosphere_size", shader_sun_atmosphere_size)
    _sky_material.set_shader_parameter("sun_atmosphere_strength", shader_sun_atmosphere_strength)
    _sky_material.set_shader_parameter("sun_energy_scale", shader_sun_energy_scale)

    _sky_material.set_shader_parameter("moon_color", shader_moon_color)
    _sky_material.set_shader_parameter("moon_size", shader_moon_size)
    _sky_material.set_shader_parameter("moon_glow_strength", shader_moon_glow_strength)
    _sky_material.set_shader_parameter("moon_eclipse_size", shader_moon_eclipse_size)
    _sky_material.set_shader_parameter("moon_tex", shader_moon_tex)

    _sky_material.set_shader_parameter("cloud_tex_a", shader_cloud_tex_a)
    _sky_material.set_shader_parameter("cloud_tex_b", shader_cloud_tex_b)
    _sky_material.set_shader_parameter("cloud_scroll_a", shader_cloud_scroll_a)
    _sky_material.set_shader_parameter("cloud_scroll_b", shader_cloud_scroll_b)
    _sky_material.set_shader_parameter("cloud_scale_a", shader_cloud_scale_a)
    _sky_material.set_shader_parameter("cloud_scale_b", shader_cloud_scale_b)
    _sky_material.set_shader_parameter("cloud_plane_height", shader_cloud_plane_height)
    _sky_material.set_shader_parameter("cloud_plane_curve", shader_cloud_plane_curve)
    _sky_material.set_shader_parameter("cloud_warp_strength", shader_cloud_warp_strength)
    _sky_material.set_shader_parameter("cloud_coverage", shader_cloud_coverage)
    _sky_material.set_shader_parameter("cloud_softness", shader_cloud_softness)
    _sky_material.set_shader_parameter("cloud_opacity", shader_cloud_opacity)
    _sky_material.set_shader_parameter("cloud_horizon_fade", shader_cloud_horizon_fade)
    _sky_material.set_shader_parameter("cloud_top_fade", shader_cloud_top_fade)
    _sky_material.set_shader_parameter("cloud_light_color", shader_cloud_light_color)
    _sky_material.set_shader_parameter("cloud_shadow_color", shader_cloud_shadow_color)
    _sky_material.set_shader_parameter("cloud_forward_scatter", shader_cloud_forward_scatter)
    _sky_material.set_shader_parameter("cloud_backscatter", shader_cloud_backscatter)
    _sky_material.set_shader_parameter("sun_cloud_occlusion", shader_sun_cloud_occlusion)

    _sky_material.set_shader_parameter("cloud_time", _get_cloud_time_value())
    _sky_material.set_shader_parameter("cloud_motion_scale", shader_cloud_motion_scale)
    _apply_cloud_wind_params()

func _get_cloud_time_value() -> float:
    return ((float(_rendered_day - 1) * 24.0) + _rendered_time) * shader_cloud_time_scale


func _update_cloud_time() -> void:
    _set_shader_param("cloud_time", _get_cloud_time_value())


func _get_global_wind_direction() -> Vector2:
    var direction := shader_cloud_wind_direction
    if shader_cloud_use_global_wind:
        direction = ProjectSettings.get_setting("shader_globals/gnd_wind_direction/value", direction)
    return direction


func _get_global_wind_speed() -> float:
    var speed := 1.0
    if shader_cloud_use_global_wind:
        speed = float(ProjectSettings.get_setting("shader_globals/gnd_wind_speed/value", speed))
    return speed * shader_cloud_wind_speed_multiplier


func _apply_cloud_wind_params() -> void:
    _sky_material.set_shader_parameter("cloud_wind_direction", _get_global_wind_direction())
    _sky_material.set_shader_parameter("cloud_wind_speed", _get_global_wind_speed())


func _update_cloud_wind() -> void:
    if not _sky_material:
        _sky_material = SKY_MATERIAL_RES
    if _sky_material:
        _apply_cloud_wind_params()


func _request_time_update(snap: bool = false) -> void:
    if not is_inside_tree():
        return
    var target_hours = float(day_of_year) * 24.0 + time_of_day
    var current_hours = float(_rendered_day) * 24.0 + _rendered_time

    if Engine.is_editor_hint() or time_transition_duration <= 0.0 or snap:
        if _time_tween: _time_tween.kill()
        _apply_total_hours(target_hours)
    else:
        if _time_tween: _time_tween.kill()
        _time_tween = create_tween()
        _time_tween.tween_method(_apply_total_hours, current_hours, target_hours, time_transition_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _apply_total_hours(total_hours: float) -> void:
    var new_day = int(floor(total_hours / 24.0))
    var new_time = fmod(total_hours, 24.0)
    if new_day != _rendered_day:
        day_changed.emit(new_day)
    _rendered_day = new_day
    _rendered_time = new_time

    _update_sun_transform()
    _update_cloud_time()
    time_changed.emit(_rendered_day, _rendered_time)

func _update_sun_transform() -> void:
    var light = _get_directional_light()
    if not is_inside_tree(): return

    var current_day = float(_rendered_day) + _rendered_time / 24.0
    var moon_phase = fmod(current_day / 29.53, 1.0)
    moon_phase_debug = moon_phase

    var theta_sun = deg_to_rad(360.0 / 365.0 * (current_day + 10.0))
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

    var sidereal_time = deg_to_rad(current_day * 360.0 + _rendered_time * 15.0)
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

    var sun_energy = sun_light_energy * smoothstep(-0.05, 0.05, s_alt)
    var moon_energy = moon_light_energy * smoothstep(0.0, 0.05, m_alt) * (1.0 - smoothstep(-0.1, 0.0, s_alt))

    if sun_energy >= moon_energy:
        if light:
            light.global_transform.basis = dir_to_basis.call(sun_dir)
            light.light_color = sun_light_color.lerp(sunset_light_color, sunset_blend)
            light.light_energy = sun_energy
        _is_daytime = true
    else:
        if light:
            light.global_transform.basis = dir_to_basis.call(moon_dir)
            light.light_color = moon_light_color
            light.light_energy = moon_energy
        _is_daytime = false

    _set_shader_param("gi_tint", gi_night_tint.lerp(gi_day_tint, day_blend))
    _set_shader_param("gi_energy_multiplier", lerp(gi_night_energy, gi_day_energy, day_blend) + sunset_blend * 0.5)

    var env_node = _get_world_environment()
    if env_node and env_node.environment:
        var env = env_node.environment
        env.ambient_light_color = ambient_color_night.lerp(ambient_color_day, day_blend)
        env.ambient_light_energy = lerp(ambient_energy_night, ambient_energy_day, pow(day_blend, 0.5)) + sunset_blend * 0.8

        var fog_day_mix = fog_color_night.lerp(fog_color_day, day_blend)
        env.fog_light_color = fog_day_mix.lerp(sunset_light_color, sunset_blend * 0.5)
        env.fog_density = lerp(fog_density_night, fog_density_day, day_blend)
        env.fog_sky_affect = lerp(fog_sky_affect_night, fog_sky_affect_day, day_blend)
        env.fog_depth_begin = lerp(fog_distance_begin_night, fog_distance_begin_day, day_blend)
        env.fog_depth_end = lerp(fog_distance_night, fog_distance_day, day_blend)

        var vol_day_mix = vol_fog_albedo_night.lerp(vol_fog_albedo_day, day_blend)
        env.volumetric_fog_albedo = vol_day_mix.lerp(sunset_light_color, sunset_blend * 0.3)

        current_vol_fog_min_density = lerp(vol_fog_min_density_night, vol_fog_min_density_day, day_blend)
        current_vol_fog_max_density = lerp(vol_fog_density_night, vol_fog_density_day, day_blend)

        if manage_vol_fog_density:
            env.volumetric_fog_density = current_vol_fog_max_density

        env.volumetric_fog_sky_affect = lerp(vol_fog_sky_affect_night, vol_fog_sky_affect_day, day_blend)
        env.volumetric_fog_length = lerp(vol_fog_length_night, vol_fog_length_day, day_blend)

        # SDFGI Workarounds application
        var base_inject = lerp(vol_fog_ambient_inject_night, vol_fog_ambient_inject_day, day_blend)

        var dip_center = 0.05
        var dip_width = 0.15
        var dip_factor = 1.0 - smoothstep(0.0, dip_width, abs(s_alt - dip_center))
        var dip_blend = smoothstep(0.0, 1.0, dip_factor)

        #env.volumetric_fog_ambient_inject = base_inject + dip_blend * vol_fog_ambient_inject_sunset_boost

        # Emission boost to actually light up the fog
        #var target_emission = vol_fog_emission_dip_color * vol_fog_emission_dip_energy
        #env.volumetric_fog_emission = Color(0,0,0).lerp(target_emission, dip_blend)

        #env.ambient_light_sky_contribution = lerp(sky_contribution_night, sky_contribution_day, day_blend)

func _ensure_effect_installed() -> void:
    var env_node = _get_world_environment()
    if not env_node: return
    var compositor = env_node.compositor
    if not compositor:
        compositor = Compositor.new()
        env_node.compositor = compositor

    var effects: Array[CompositorEffect] = compositor.compositor_effects
    effects = effects.filter(func(item): return item != null)

    var existing: CompositorEffect = null
    for item in effects:
        if item.get_script() == SUN_SHAFTS_EFFECT_SCRIPT:
            existing = item
            break

    if existing:
        _compositor_effect = existing
    else:
        _compositor_effect = SUN_SHAFTS_EFFECT_SCRIPT.new()
        effects.append(_compositor_effect)
        compositor.compositor_effects = effects

func _update_effect() -> void:
    _ensure_effect_installed()
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

    _compositor_effect.set("shaft_color", sunshafts_shaft_color)
    _compositor_effect.set("density", sunshafts_density)
    _compositor_effect.set("bright_threshold", sunshafts_bright_threshold)
    _compositor_effect.set("weight", sunshafts_weight)
    _compositor_effect.set("decay", sunshafts_decay)
    _compositor_effect.set("exposure", sunshafts_exposure)
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
