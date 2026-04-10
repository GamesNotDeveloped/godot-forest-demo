@tool
extends Node3D
class_name PuddleSurface3D

const PUDDLE_SURFACE_SHADER := preload("res://addons/gnd_weather/puddle_surface.gdshader")
const PROBE_OFFSETS: Array[Vector2] = [
    Vector2.ZERO,
    Vector2(-0.35, -0.35),
    Vector2(0.35, -0.35),
    Vector2(-0.35, 0.35),
    Vector2(0.35, 0.35),
]

@export var mask_texture: Texture2D
@export var mesh: Mesh:
    set(value):
        mesh = value
        if is_inside_tree():
            _ensure_render_resources()
            _sync_render_state()
@export_range(0.0, 0.2, 0.001) var surface_height_offset: float = 0.078
@export_range(0.0, 500.0, 0.1) var visibility_range_begin: float = 6.0
@export_range(0.0, 500.0, 0.1) var visibility_range_end: float = 10.0
@export_range(0.1, 5.0, 0.05) var probe_interval_sec: float = 0.4
@export_range(0.0, 2.0, 0.01) var probe_height: float = 0.12
@export_range(0.1, 20.0, 0.05) var rain_smoothing_speed: float = 10.35
@export_range(0.0, 1.0, 0.01) var rain_ripple_threshold: float = 0.31
@export_range(0.0, 1.0, 0.01) var specular_wet: float = 0.75
@export_range(0.0, 0.1, 0.0005) var refraction_strength: float = 0.014
@export_range(0.0, 1.0, 0.01) var refraction_mix: float = 1.0
@export_range(0.0, 1.0, 0.01) var surface_roughness: float = 0.04
@export_range(0.0, 1.0, 0.01) var ripple_roughness_reduction: float = 0.02
@export_range(0.1, 4.0, 0.01) var ripple_speed: float = 0.67
@export_range(0.1, 10.0, 0.01) var ripple_scale: float = 0.1
@export_range(0.0, 5.0, 0.01) var ripple_max_radius: float = 1.0
@export_range(0.0, 2.0, 0.01) var ripple_intensity: float = 0.9
@export_range(0.0, 1.0, 0.01) var edge_foam_strength: float = 0.08
@export_range(0.0, 8.0, 0.01) var normal_strength: float = 1.0
@export_range(0.0, 1.0, 0.01) var puddle_alpha_cutoff: float = 0.07

var _probe_timer := 0.0
var _target_rain_strength := 0.0
var _current_rain_strength := 0.0

var _material: ShaderMaterial
var _instance_rid: RID


func _ready() -> void:
    set_notify_transform(true)
    _ensure_render_resources()
    _sync_render_state()
    _probe_timer = 0.0
    set_process(true)


func _exit_tree() -> void:
    if _instance_rid.is_valid():
        RenderingServer.free_rid(_instance_rid)
        _instance_rid = RID()


func _process(delta: float) -> void:
    _probe_timer -= delta
    if _probe_timer <= 0.0:
        _probe_timer = maxf(probe_interval_sec, 0.1)
        _sample_local_rain()

    _current_rain_strength = move_toward(
        _current_rain_strength,
        _target_rain_strength,
        maxf(rain_smoothing_speed, 0.1) * delta
    )
    _sync_render_state()


func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSFORM_CHANGED:
        _sync_render_state()
    elif what == NOTIFICATION_ENTER_WORLD:
        _sync_render_state()


func _ensure_render_resources() -> void:
    if _material == null:
        _material = ShaderMaterial.new()
        _material.shader = PUDDLE_SURFACE_SHADER

    if not _instance_rid.is_valid():
        _instance_rid = RenderingServer.instance_create()
        RenderingServer.instance_geometry_set_material_override(_instance_rid, _material.get_rid())

    var render_mesh := _get_render_mesh()
    if render_mesh != null:
        RenderingServer.instance_set_base(_instance_rid, render_mesh.get_rid())
    else:
        RenderingServer.instance_set_base(_instance_rid, RID())


func _sync_render_state() -> void:
    if _material == null or not _instance_rid.is_valid():
        return

    var render_mesh := _get_render_mesh()
    if render_mesh == null:
        RenderingServer.instance_set_base(_instance_rid, RID())
        return

    RenderingServer.instance_set_base(_instance_rid, render_mesh.get_rid())

    var world_3d := get_world_3d()
    if world_3d != null:
        RenderingServer.instance_set_scenario(_instance_rid, world_3d.scenario)

    var render_transform := global_transform.translated_local(Vector3(0.0, surface_height_offset, 0.0))
    RenderingServer.instance_set_transform(_instance_rid, render_transform)

    _material.set_shader_parameter("mask_texture", mask_texture)
    _material.set_shader_parameter("rain_strength", _current_rain_strength)
    _material.set_shader_parameter("rain_ripple_threshold", rain_ripple_threshold)
    _material.set_shader_parameter("puddle_alpha_cutoff", puddle_alpha_cutoff)
    _material.set_shader_parameter("visibility_range_begin", visibility_range_begin)
    _material.set_shader_parameter("visibility_range_end", maxf(visibility_range_end, visibility_range_begin + 0.001))
    _material.set_shader_parameter("refraction_strength", refraction_strength)
    _material.set_shader_parameter("refraction_mix", refraction_mix)
    _material.set_shader_parameter("surface_roughness", clampf(surface_roughness, 0.01, 0.18))
    _material.set_shader_parameter("ripple_roughness_reduction", ripple_roughness_reduction)
    _material.set_shader_parameter("specular_strength", specular_wet)
    _material.set_shader_parameter("ripple_intensity", ripple_intensity)
    _material.set_shader_parameter("ripple_scale", ripple_scale)
    _material.set_shader_parameter("ripple_speed", ripple_speed)
    _material.set_shader_parameter("ripple_max_radius", ripple_max_radius)
    _material.set_shader_parameter("edge_foam_strength", edge_foam_strength)
    _material.set_shader_parameter("normal_strength", normal_strength)


func _sample_local_rain() -> void:
    if mesh == null:
        _target_rain_strength = 0.0
        return
    var world_3d := get_world_3d()
    if world_3d == null:
        _target_rain_strength = 0.0
        return

    var weather_state := WeatherServer.get_weather_state(world_3d)
    var base_strength: float = clampf(float(weather_state.get("global_precipitation", 0.0)), 0.0, 1.0)
    var total := 0.0
    for probe_offset in PROBE_OFFSETS:
        total += WeatherServer.get_rain_participation_strength(
            world_3d,
            _get_probe_world_position(probe_offset),
            base_strength
        )
    _target_rain_strength = clampf(total / float(PROBE_OFFSETS.size()), 0.0, 1.0)


func _get_probe_world_position(offset: Vector2) -> Vector3:
    var basis := global_transform.basis.orthonormalized()
    var footprint := _get_probe_footprint_size()
    var half_width := footprint.x * 0.5
    var half_depth := footprint.y * 0.5
    var world_position := global_transform.origin
    world_position += basis.x * (offset.x * half_width)
    world_position += basis.z * (offset.y * half_depth)
    world_position.y += probe_height + surface_height_offset
    return world_position


func _get_render_mesh() -> Mesh:
    return mesh


func _get_probe_footprint_size() -> Vector2:
    if mesh == null:
        return Vector2(0.1, 0.1)
    var aabb := mesh.get_aabb()
    var width := maxf(absf(aabb.size.x), 0.1)
    var depth := maxf(absf(aabb.size.z), 0.1)
    return Vector2(width, depth)
