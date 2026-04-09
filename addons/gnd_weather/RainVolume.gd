@tool
class_name RainVolume
extends VisualInstance3D

enum VolumeShape {
    BOX,
}

@export_group("Rain")
@export var volume_enabled: bool = true
@export var volume_priority: int = 0
@export_range(-10.0, 10.0, 0.01) var precipitation_delta: float = -1.0
@export_range(0.0, 2.0, 0.01) var precipitation_multiplier: float = 1.0

@export_group("Volume")
@export var shape: VolumeShape = VolumeShape.BOX
@export var size: Vector3 = Vector3(4.0, 2.0, 4.0):
    set(value):
        size = Vector3(absf(value.x), absf(value.y), absf(value.z))
        _refresh_cached_volume_shape()
@export_range(0.0, 8.0, 0.01) var edge_feather: float = 0.6:
    set(value):
        edge_feather = maxf(value, 0.0)
        _refresh_cached_volume_shape()

var _registered_world: World3D
var _registered_volume_rid: RID
var _cached_half_size: Vector3 = Vector3(2.0, 1.0, 2.0)
var _cached_outer_half_size: Vector3 = Vector3(2.6, 1.6, 2.6)
var _cached_edge_feather: float = 0.6


func _notification(what: int) -> void:
    if what == NOTIFICATION_READY:
        _refresh_cached_volume_shape()

    if Engine.is_editor_hint():
        return

    if what == NOTIFICATION_ENTER_WORLD:
        _register_in_weather_server()
    elif what == NOTIFICATION_EXIT_WORLD:
        _unregister_from_weather_server()


func is_rain_volume_enabled() -> bool:
    return volume_enabled


func get_precipitation_delta() -> float:
    return clampf(precipitation_delta, -1.0, 1.0)


func get_precipitation_multiplier() -> float:
    return maxf(precipitation_multiplier, 0.0)


func contains_world_position(world_position: Vector3) -> bool:
    if shape != VolumeShape.BOX:
        return false

    var local_position := global_transform.affine_inverse() * world_position
    return (
        absf(local_position.x) <= _cached_half_size.x
        and absf(local_position.y) <= _cached_half_size.y
        and absf(local_position.z) <= _cached_half_size.z
    )


func get_precipitation_blend(world_position: Vector3) -> float:
    if shape != VolumeShape.BOX:
        return 0.0

    var local_position := global_transform.affine_inverse() * world_position
    var local_abs := Vector3(
        absf(local_position.x),
        absf(local_position.y),
        absf(local_position.z)
    )
    if (
        local_abs.x <= _cached_half_size.x
        and local_abs.y <= _cached_half_size.y
        and local_abs.z <= _cached_half_size.z
    ):
        return 1.0

    if _cached_edge_feather <= 0.0001:
        return 0.0

    var feather_distance := Vector3(
        _cached_outer_half_size.x - local_abs.x,
        _cached_outer_half_size.y - local_abs.y,
        _cached_outer_half_size.z - local_abs.z
    )
    var distance_to_outer_edge := minf(feather_distance.x, minf(feather_distance.y, feather_distance.z))
    if distance_to_outer_edge <= 0.0:
        return 0.0

    var t := clampf(distance_to_outer_edge / _cached_edge_feather, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


func _get_aabb() -> AABB:
    var local_size := _get_safe_size()
    return AABB(-local_size * 0.5, local_size)


func _register_in_weather_server() -> void:
    var world_3d := get_world_3d()
    var volume_rid := get_instance()
    if world_3d == null or not volume_rid.is_valid():
        return

    _registered_world = world_3d
    _registered_volume_rid = volume_rid
    WeatherServer.add_rain_volume(world_3d, volume_rid, self)


func _unregister_from_weather_server() -> void:
    if _registered_world == null or not _registered_volume_rid.is_valid():
        return

    WeatherServer.remove_rain_volume(_registered_world, _registered_volume_rid)
    _registered_world = null
    _registered_volume_rid = RID()


func _get_half_size() -> Vector3:
    return _get_safe_size() * 0.5


func _get_safe_size() -> Vector3:
    return Vector3(maxf(size.x, 0.001), maxf(size.y, 0.001), maxf(size.z, 0.001))


func _refresh_cached_volume_shape() -> void:
    _cached_half_size = _get_safe_size() * 0.5
    _cached_edge_feather = maxf(edge_feather, 0.0)
    var feather_offset := Vector3.ONE * _cached_edge_feather
    _cached_outer_half_size = _cached_half_size + feather_offset
