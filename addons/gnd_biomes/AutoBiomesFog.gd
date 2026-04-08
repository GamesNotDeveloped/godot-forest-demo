@tool
class_name AutoBiomesFog
extends Node

@export var biomes_path: NodePath
@export var world_environment_path: NodePath
@export var sample_target_path: NodePath
@export var skydome_path: NodePath

@export_range(0.0, 1.0, 0.0001, "or_greater") var max_density: float = 0.0
@export_range(0.01, 60.0, 0.01, "or_greater") var sample_interval: float = 0.1:
    set(value):
        sample_interval = maxf(value, 0.01)
        _update_timer_configuration()
@export_range(0.0, 64.0, 0.1, "or_greater") var radius: float = 3.0
@export_range(0.0, 1.0, 0.0001, "or_greater") var min_fog_density: float = 0.0
@export_range(0.01, 20.0, 0.01, "or_greater") var tween_duration: float = 0.25:
    set(value):
        tween_duration = maxf(value, 0.01)

var _biomes: Biomes
var _world_environment: WorldEnvironment
var _sample_target: Node3D
var _skydome: Skydome
var _sample_timer: Timer
var _fog_tween: Tween


func _ready() -> void:
    _biomes = get_node(biomes_path) as Biomes
    _world_environment = get_node(world_environment_path) as WorldEnvironment
    _sample_target = get_node(sample_target_path) as Node3D
    _skydome = get_node(skydome_path) as Skydome
    _ensure_sample_timer()
    _sample_timer.start()
    _sample_and_apply_fog()


func _exit_tree() -> void:
    if _fog_tween != null:
        _fog_tween.kill()
        _fog_tween = null


func _ensure_sample_timer() -> void:
    if _sample_timer == null:
        _sample_timer = Timer.new()
        _sample_timer.one_shot = false
        _sample_timer.autostart = false
        _sample_timer.wait_time = sample_interval
        add_child(_sample_timer, false, INTERNAL_MODE_FRONT)

    if not _sample_timer.timeout.is_connected(_on_sample_timer_timeout):
        _sample_timer.timeout.connect(_on_sample_timer_timeout)


func _update_timer_configuration() -> void:
    if _sample_timer == null:
        return
    _sample_timer.wait_time = sample_interval
    if is_inside_tree():
        _sample_timer.start()


func _on_sample_timer_timeout() -> void:
    _sample_and_apply_fog()


func _sample_and_apply_fog() -> void:
    var environment := _world_environment.environment
    if environment == null or not environment.volumetric_fog_enabled:
        return

    var biome_sample := clampf(_biomes.sample_mask_value_at_world_position(_sample_target.global_position, radius), 0.0, 1.0)
    var biome_density := lerpf(min_fog_density, max_density, biome_sample)
    var target_density := _skydome.get_current_vol_fog_density() + biome_density
    if _fog_tween != null:
        _fog_tween.kill()
    _fog_tween = create_tween()
    _fog_tween.tween_property(environment, "volumetric_fog_density", target_density, tween_duration)
