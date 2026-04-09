@tool
class_name RainVolume
extends Area3D

const DEFAULT_WEATHER_LAYER_MASK := 1 << 20

@export_group("Rain")
@export var volume_enabled: bool = true
@export var volume_priority: int = 0
@export_range(-1.0, 1.0, 0.01) var precipitation_delta: float = -1.0
@export_range(0.0, 2.0, 0.01) var precipitation_multiplier: float = 1.0

@export_group("Physics")
@export_flags_3d_physics var weather_collision_layer: int = DEFAULT_WEATHER_LAYER_MASK:
    set(value):
        weather_collision_layer = value
        _apply_collision_settings()


func _enter_tree() -> void:
    _apply_collision_settings()


func _ready() -> void:
    _apply_collision_settings()


func is_rain_volume_enabled() -> bool:
    return volume_enabled


func get_precipitation_delta() -> float:
    return clampf(precipitation_delta, -1.0, 1.0)


func get_precipitation_multiplier() -> float:
    return maxf(precipitation_multiplier, 0.0)


func _apply_collision_settings() -> void:
    monitoring = false
    monitorable = true
    collision_mask = 0
    collision_layer = weather_collision_layer
