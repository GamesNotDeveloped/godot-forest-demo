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
@export var surface_size: Vector2 = Vector2(3.495, 2.2)
@export_range(0.0, 0.2, 0.001) var surface_height_offset: float = 0.078
@export_range(0.1, 5.0, 0.05) var probe_interval_sec: float = 0.4
@export_range(0.0, 2.0, 0.01) var probe_height: float = 0.12
@export_range(0.1, 20.0, 0.05) var rain_smoothing_speed: float = 10.35
@export_range(0.0, 1.0, 0.01) var rain_ripple_threshold: float = 0.31
@export_range(0.0, 1.0, 0.01) var rain_wave_threshold: float = 0.22
@export_range(0.0, 1.0, 0.01) var roughness_dry: float = 0.68
@export_range(0.0, 1.0, 0.01) var roughness_wet: float = 0.64
@export_range(0.0, 1.0, 0.01) var specular_wet: float = 0.75
@export var shallow_color: Color = Color(0.11, 0.15, 0.13, 1.0)
@export var deep_color: Color = Color(0.03, 0.06, 0.07, 1.0)
@export var foam_color: Color = Color(0.84, 0.88, 0.82, 1.0)
@export_range(0.0, 8.0, 0.01) var depth_absorption: float = 1.35
@export_range(0.0, 0.1, 0.0005) var refraction_strength: float = 0.014
@export_range(0.0, 1.0, 0.01) var fresnel_strength: float = 0.72
@export_range(0.5, 8.0, 0.05) var fresnel_power: float = 5.0
@export_range(0.0, 1.0, 0.01) var surface_roughness: float = 0.04
@export_range(0.0, 1.0, 0.01) var ripple_roughness_reduction: float = 0.02
@export_range(0.0, 1.0, 0.01) var specular_strength: float = 0.75
@export_range(0.1, 20.0, 0.1) var wave_speed: float = 0.35
@export_range(0.1, 20.0, 0.1) var wave_scale: float = 0.1
@export_range(0.0, 2.0, 0.01) var wave_intensity: float = 0.24
@export_range(0.1, 20.0, 0.1) var secondary_wave_speed: float = 0.55
@export_range(0.1, 20.0, 0.1) var secondary_wave_scale: float = 2.8
@export_range(0.0, 2.0, 0.01) var secondary_wave_intensity: float = 0.05
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

var _mesh: PlaneMesh
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
    if _mesh == null:
        _mesh = PlaneMesh.new()
        _mesh.orientation = PlaneMesh.FACE_Y
    _mesh.size = Vector2(maxf(surface_size.x, 0.1), maxf(surface_size.y, 0.1))

    if _material == null:
        _material = ShaderMaterial.new()
        _material.shader = PUDDLE_SURFACE_SHADER

    if not _instance_rid.is_valid():
        _instance_rid = RenderingServer.instance_create()
        RenderingServer.instance_set_base(_instance_rid, _mesh.get_rid())
        RenderingServer.instance_geometry_set_material_override(_instance_rid, _material.get_rid())


func _sync_render_state() -> void:
    if _mesh == null or _material == null or not _instance_rid.is_valid():
        return

    _mesh.orientation = PlaneMesh.FACE_Y
    _mesh.size = Vector2(maxf(surface_size.x, 0.1), maxf(surface_size.y, 0.1))

    var world_3d := get_world_3d()
    if world_3d != null:
        RenderingServer.instance_set_scenario(_instance_rid, world_3d.scenario)

    var render_transform := global_transform.translated_local(Vector3(0.0, surface_height_offset, 0.0))
    RenderingServer.instance_set_transform(_instance_rid, render_transform)

    _material.set_shader_parameter("mask_texture", mask_texture)
    _material.set_shader_parameter("shallow_color", shallow_color)
    _material.set_shader_parameter("deep_color", deep_color)
    _material.set_shader_parameter("foam_color", foam_color)
    _material.set_shader_parameter("rain_strength", _current_rain_strength)
    _material.set_shader_parameter("rain_ripple_threshold", rain_ripple_threshold)
    _material.set_shader_parameter("rain_wave_threshold", rain_wave_threshold)
    _material.set_shader_parameter("puddle_alpha_cutoff", puddle_alpha_cutoff)
    _material.set_shader_parameter("depth_absorption", depth_absorption)
    _material.set_shader_parameter("refraction_strength", refraction_strength)
    _material.set_shader_parameter("fresnel_strength", fresnel_strength)
    _material.set_shader_parameter("fresnel_power", fresnel_power)
    var effective_surface_roughness := clampf(
        lerpf(roughness_dry, roughness_wet, _current_rain_strength) * 0.06,
        0.01,
        0.18
    )
    _material.set_shader_parameter("surface_roughness", maxf(surface_roughness, effective_surface_roughness))
    _material.set_shader_parameter("ripple_roughness_reduction", ripple_roughness_reduction)
    _material.set_shader_parameter("specular_strength", specular_wet)
    _material.set_shader_parameter("ripple_intensity", ripple_intensity)
    _material.set_shader_parameter("ripple_scale", ripple_scale)
    _material.set_shader_parameter("ripple_speed", ripple_speed)
    _material.set_shader_parameter("ripple_max_radius", ripple_max_radius)
    _material.set_shader_parameter("wave_intensity", wave_intensity)
    _material.set_shader_parameter("wave_scale", wave_scale)
    _material.set_shader_parameter("wave_speed", wave_speed)
    _material.set_shader_parameter("secondary_wave_intensity", secondary_wave_intensity)
    _material.set_shader_parameter("secondary_wave_scale", secondary_wave_scale)
    _material.set_shader_parameter("secondary_wave_speed", secondary_wave_speed)
    _material.set_shader_parameter("edge_foam_strength", edge_foam_strength)
    _material.set_shader_parameter("normal_strength", normal_strength)


func _sample_local_rain() -> void:
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
    var half_width := maxf(surface_size.x, 0.1) * 0.5
    var half_depth := maxf(surface_size.y, 0.1) * 0.5
    var world_position := global_transform.origin
    world_position += basis.x * (offset.x * half_width)
    world_position += basis.z * (offset.y * half_depth)
    world_position.y += probe_height + surface_height_offset
    return world_position
