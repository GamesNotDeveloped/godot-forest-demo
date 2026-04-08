@tool
class_name AutoBiomesFog
extends Node

const SAMPLE_TIMER_NAME := "__biomes_fog_timer"
const DENSITY_EPSILON := 0.0001

@export var biomes_path: NodePath
@export var world_environment_path: NodePath
@export var sample_target_path: NodePath

@export_range(0.01, 60.0, 0.01, "or_greater") var sample_interval: float = 0.1:
    set(value):
        sample_interval = maxf(value, 0.01)
        _update_timer_configuration()

@export_range(0.0, 64.0, 0.1, "or_greater") var radius: float = 3.0
@export_range(0.0, 1.0, 0.0001, "or_greater") var min_fog_density: float = 0.0
@export_range(-1.0, 1.0, 0.0001, "or_greater") var max_density: float = -1.0

@export_range(0.01, 20.0, 0.01, "or_greater") var tween_duration: float = 0.25:
    set(value):
        tween_duration = maxf(value, 0.01)

var _sample_timer: Timer
var _fog_tween: Tween
var _current_environment: Environment
var _max_fog_density := 0.0
var _last_target_density := INF


func _ready() -> void:
    _ensure_sample_timer()
    _update_timer_configuration()
    _refresh_environment_cache()
    _sample_and_apply_fog()


func _exit_tree() -> void:
    if _fog_tween != null:
        _fog_tween.kill()
        _fog_tween = null


func _ensure_sample_timer() -> void:
    _sample_timer = get_node_or_null(SAMPLE_TIMER_NAME) as Timer
    if _sample_timer != null:
        if not _sample_timer.timeout.is_connected(_on_sample_timer_timeout):
            _sample_timer.timeout.connect(_on_sample_timer_timeout)
        return

    _sample_timer = Timer.new()
    _sample_timer.name = SAMPLE_TIMER_NAME
    _sample_timer.one_shot = false
    _sample_timer.autostart = false
    _sample_timer.timeout.connect(_on_sample_timer_timeout)
    add_child(_sample_timer, false, INTERNAL_MODE_FRONT)


func _update_timer_configuration() -> void:
    if _sample_timer == null:
        return
    _sample_timer.wait_time = maxf(sample_interval, 0.01)
    if is_inside_tree():
        _sample_timer.start()


func _on_sample_timer_timeout() -> void:
    _sample_and_apply_fog()


func _sample_and_apply_fog() -> void:
    var environment := _get_environment()
    if environment == null:
        return
    if not environment.volumetric_fog_enabled:
        return

    var biomes := get_node_or_null(biomes_path) as Biomes
    var sample_target := get_node_or_null(sample_target_path) as Node3D
    if biomes == null or sample_target == null:
        return

    _refresh_environment_cache()
    var sample := clampf(biomes.sample_mask_value_at_world_position(sample_target.global_position, radius), 0.0, 1.0)
    var effective_max_density := _get_effective_max_density()
    var target_density := lerpf(min_fog_density, effective_max_density, sample)
    if absf(target_density - _last_target_density) <= DENSITY_EPSILON:
        return

    _last_target_density = target_density
    if _fog_tween != null:
        _fog_tween.kill()
    _fog_tween = create_tween()
    _fog_tween.tween_property(environment, "volumetric_fog_density", target_density, tween_duration)


func _get_environment() -> Environment:
    var world_environment := get_node_or_null(world_environment_path) as WorldEnvironment
    if world_environment == null:
        return null
    return world_environment.environment


func _refresh_environment_cache() -> void:
    var environment := _get_environment()
    if environment == null:
        _current_environment = null
        _max_fog_density = 0.0
        _last_target_density = INF
        return

    if environment != _current_environment:
        _current_environment = environment
        _max_fog_density = environment.volumetric_fog_density
        _last_target_density = INF


func _get_effective_max_density() -> float:
    if max_density >= 0.0:
        return max_density
    return _max_fog_density


func apply_profile_override(max_density_override: float) -> void:
    max_density = max_density_override
    _refresh_environment_cache()

    if _fog_tween != null:
        _fog_tween.kill()
        _fog_tween = null

    var environment := _get_environment()
    if environment == null:
        return

    if not environment.volumetric_fog_enabled:
        environment.volumetric_fog_density = 0.0
        _last_target_density = 0.0
        return

    var biomes := get_node_or_null(biomes_path) as Biomes
    var sample_target := get_node_or_null(sample_target_path) as Node3D
    if biomes == null or sample_target == null:
        environment.volumetric_fog_density = _get_effective_max_density()
        _last_target_density = environment.volumetric_fog_density
        return

    var sample := clampf(biomes.sample_mask_value_at_world_position(sample_target.global_position, radius), 0.0, 1.0)
    var target_density := lerpf(min_fog_density, _get_effective_max_density(), sample)
    environment.volumetric_fog_density = target_density
    _last_target_density = target_density
