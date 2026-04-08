@tool
class_name Skydome
extends Node

const SUN_SHAFTS_EFFECT_SCRIPT := preload("res://scenery/SunShaftsCompositorEffect.gd")
const SKY_MATERIAL_RES := preload("res://scenery/materials/M_filmic_procedural_sky.tres")
const SKY_RES := preload("res://materials/sky_filmic.tres")

@export_group("Time & Date")
@export_range(1, 365) var day_of_year: int = 180:
    set(v):
        day_of_year = v
        _update_sun_transform()
@export_range(0.0, 24.0) var time_of_day: float = 12.0:
    set(v):
        time_of_day = v
        _update_sun_transform()
@export_range(-90.0, 90.0) var latitude: float = 45.0:
    set(v):
        latitude = v
        _update_sun_transform()

@export_group("Light Settings")
@export var sun_light_color: Color = Color(1.0, 0.93, 0.85):
    set(v):
        sun_light_color = v
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
@export var shader_sky_energy: float = 0.242000011495:
    set(v):
        shader_sky_energy = v
        _set_shader_param("sky_energy", v)
@export var shader_horizon_height: float = 0.17800002149454003:
    set(v):
        shader_horizon_height = v
        _set_shader_param("horizon_height", v)
@export var shader_horizon_softness: float = 0.24:
    set(v):
        shader_horizon_softness = v
        _set_shader_param("horizon_softness", v)
@export var shader_zenith_curve: float = 0.40500001597762003:
    set(v):
        shader_zenith_curve = v
        _set_shader_param("zenith_curve", v)
@export var shader_horizon_glow_strength: float = 1.00400004769:
    set(v):
        shader_horizon_glow_strength = v
        _set_shader_param("horizon_glow_strength", v)
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
@export_group("Sky Shader: GI")
@export var shader_gi_tint: Color = Color(0.8, 0.75, 0.7, 1.0):
    set(v):
        shader_gi_tint = v
        _set_shader_param("gi_tint", v)
@export var shader_gi_energy_multiplier: float = 0.6:
    set(v):
        shader_gi_energy_multiplier = v
        _set_shader_param("gi_energy_multiplier", v)
@export_group("Sky Shader: Sun")
@export var shader_sun_color: Color = Color(1, 0.98, 0.9, 1):
    set(v):
        shader_sun_color = v
        _set_shader_param("sun_color", v)
@export var shader_sun_disk_size: float = 0.0670000031825:
    set(v):
        shader_sun_disk_size = v
        _set_shader_param("sun_disk_size", v)
@export var shader_sun_disk_softness: float = 0.5730000272175:
    set(v):
        shader_sun_disk_softness = v
        _set_shader_param("sun_disk_softness", v)
@export var shader_sun_disk_strength: float = 0.630000029925:
    set(v):
        shader_sun_disk_strength = v
        _set_shader_param("sun_disk_strength", v)
@export var shader_sun_halo_size: float = 0.4110000195225:
    set(v):
        shader_sun_halo_size = v
        _set_shader_param("sun_halo_size", v)
@export var shader_sun_halo_strength: float = 0.7250000344375:
    set(v):
        shader_sun_halo_strength = v
        _set_shader_param("sun_halo_strength", v)
@export var shader_sun_atmosphere_size: float = 0.4630000219925:
    set(v):
        shader_sun_atmosphere_size = v
        _set_shader_param("sun_atmosphere_size", v)
@export var shader_sun_atmosphere_strength: float = 0.3010000142975:
    set(v):
        shader_sun_atmosphere_strength = v
        _set_shader_param("sun_atmosphere_strength", v)
@export var shader_sun_energy_scale: float = 0.378000017955:
    set(v):
        shader_sun_energy_scale = v
        _set_shader_param("sun_energy_scale", v)
@export_group("Sky Shader: Moon")
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
@export var shader_cloud_plane_height: float = 0.18700000748547:
    set(v):
        shader_cloud_plane_height = v
        _set_shader_param("cloud_plane_height", v)
@export var shader_cloud_plane_curve: float = 0.5950000282625:
    set(v):
        shader_cloud_plane_curve = v
        _set_shader_param("cloud_plane_curve", v)
@export var shader_cloud_warp_strength: float = 0.0530000025175:
    set(v):
        shader_cloud_warp_strength = v
        _set_shader_param("cloud_warp_strength", v)
@export var shader_cloud_coverage: float = 0.2000000095:
    set(v):
        shader_cloud_coverage = v
        _set_shader_param("cloud_coverage", v)
@export var shader_cloud_softness: float = 0.04600000148648:
    set(v):
        shader_cloud_softness = v
        _set_shader_param("cloud_softness", v)
@export var shader_cloud_opacity: float = 0.4410000209475:
    set(v):
        shader_cloud_opacity = v
        _set_shader_param("cloud_opacity", v)
@export var shader_cloud_horizon_fade: float = 0.4810000228475:
    set(v):
        shader_cloud_horizon_fade = v
        _set_shader_param("cloud_horizon_fade", v)
@export var shader_cloud_top_fade: float = 0.118000005605:
    set(v):
        shader_cloud_top_fade = v
        _set_shader_param("cloud_top_fade", v)
@export var shader_cloud_light_color: Color = Color(1, 0.98, 0.95, 1):
    set(v):
        shader_cloud_light_color = v
        _set_shader_param("cloud_light_color", v)
@export var shader_cloud_shadow_color: Color = Color(0.8984375, 0.8984375, 0.8984375, 1):
    set(v):
        shader_cloud_shadow_color = v
        _set_shader_param("cloud_shadow_color", v)
@export var shader_cloud_forward_scatter: float = 1.5:
    set(v):
        shader_cloud_forward_scatter = v
        _set_shader_param("cloud_forward_scatter", v)
@export var shader_cloud_backscatter: float = 0.390000018525:
    set(v):
        shader_cloud_backscatter = v
        _set_shader_param("cloud_backscatter", v)
@export var shader_sun_cloud_occlusion: float = 0.406000019285:
    set(v):
        shader_sun_cloud_occlusion = v
        _set_shader_param("sun_cloud_occlusion", v)


func _enter_tree() -> void:
    if Engine.is_editor_hint() or is_inside_tree():
        _init_sky()

func _ready() -> void:
    _is_ready = true
    _init_sky()
    _update_sun_transform()
    set_process(true)

func _process(_delta: float) -> void:
    _update_effect()

func _refresh() -> void:
    if is_inside_tree():
        _init_sky()

func _get_directional_light() -> DirectionalLight3D:
    if not is_inside_tree(): return null
    if not directional_light_path.is_empty():
        return get_node_or_null(directional_light_path) as DirectionalLight3D
    var tree = get_tree()
    if tree and tree.current_scene:
        return tree.current_scene.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
    return null

func _get_world_environment() -> WorldEnvironment:
    if not is_inside_tree(): return null
    if not world_environment_path.is_empty():
        return get_node_or_null(world_environment_path) as WorldEnvironment
    var tree = get_tree()
    if tree and tree.current_scene:
        return tree.current_scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
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
    _sky_material.set_shader_parameter("night_lower_sky_color", shader_night_lower_sky_color)
    _sky_material.set_shader_parameter("night_horizon_color", shader_night_horizon_color)
    _sky_material.set_shader_parameter("night_zenith_color", shader_night_zenith_color)
    _sky_material.set_shader_parameter("night_sky_energy", shader_night_sky_energy)
    _sky_material.set_shader_parameter("stars_color", shader_stars_color)
    _sky_material.set_shader_parameter("gi_tint", shader_gi_tint)
    _sky_material.set_shader_parameter("gi_energy_multiplier", shader_gi_energy_multiplier)
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

func _update_sun_transform() -> void:
    var light = _get_directional_light()
    if not light: return

    var current_day = float(day_of_year) + time_of_day / 24.0
    var moon_phase = fmod(current_day / 29.53, 1.0)
    moon_phase_debug = moon_phase

    var theta_sun = deg_to_rad(360.0 / 365.0 * (current_day + 10.0))
    var declination_sun = deg_to_rad(-23.45) * cos(theta_sun)

    var theta_moon = theta_sun - moon_phase * TAU
    var declination_moon = deg_to_rad(-23.45) * cos(theta_moon)

    var hour_angle = deg_to_rad(15.0 * (time_of_day - 12.0))
    var lat_rad = deg_to_rad(latitude)

    var get_dir = func(ha: float, dec: float) -> Vector3:
        var y = sin(lat_rad) * sin(dec) + cos(lat_rad) * cos(dec) * cos(ha)
        var x = -cos(dec) * sin(ha)
        var z = sin(lat_rad) * cos(dec) * cos(ha) - cos(lat_rad) * sin(dec)
        return Vector3(x, y, z).normalized()

    var sun_dir = get_dir.call(hour_angle, declination_sun)
    var moon_hour_angle = hour_angle - moon_phase * TAU
    var moon_dir = get_dir.call(moon_hour_angle, declination_moon)

    _set_shader_param("custom_sun_dir", sun_dir)
    _set_shader_param("custom_moon_dir", moon_dir)

    var dir_to_basis = func(dir: Vector3) -> Basis:
        var up = Vector3.UP
        if abs(dir.y) > 0.999:
            up = Vector3.RIGHT
        var right = up.cross(dir).normalized()
        var new_up = dir.cross(right).normalized()
        return Basis(right, new_up, dir)

    var s_alt = sun_dir.y
    var m_alt = moon_dir.y

    if s_alt > 0.0:
        light.global_transform.basis = dir_to_basis.call(sun_dir)
        light.light_color = sun_light_color
        light.light_energy = sun_light_energy * smoothstep(0.0, 0.05, s_alt)
        _is_daytime = true
    else:
        light.global_transform.basis = dir_to_basis.call(moon_dir)
        light.light_color = moon_light_color
        light.light_energy = moon_light_energy * smoothstep(0.0, 0.05, m_alt)
        _is_daytime = false

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
    # The basis.z is actually the direction towards the light source in our setup
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
