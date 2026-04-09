class_name WeatherServer
extends RefCounted

static var _rain_volumes_by_world: Dictionary = {}


static func add_rain_volume(world_3d: World3D, volume_rid: RID, volume: RainVolume) -> void:
    if world_3d == null or not volume_rid.is_valid() or volume == null:
        return

    var world_id := world_3d.get_instance_id()
    var world_bucket: Dictionary = _rain_volumes_by_world.get(world_id, {})
    world_bucket[volume_rid.get_id()] = volume
    _rain_volumes_by_world[world_id] = world_bucket


static func remove_rain_volume(world_3d: World3D, volume_rid: RID) -> void:
    if world_3d == null or not volume_rid.is_valid():
        return

    var world_id := world_3d.get_instance_id()
    var world_bucket: Dictionary = _rain_volumes_by_world.get(world_id, {})
    if world_bucket.is_empty():
        return

    world_bucket.erase(volume_rid.get_id())
    if world_bucket.is_empty():
        _rain_volumes_by_world.erase(world_id)
    else:
        _rain_volumes_by_world[world_id] = world_bucket


static func get_rain_participation_strength(
    world_3d: World3D,
    world_position: Vector3,
    base_strength: float
) -> float:
    var intensity: float = clampf(base_strength, 0.0, 1.0)
    for volume in _collect_rain_volumes_at_position(world_3d, world_position):
        var blend: float = volume.get_precipitation_blend(world_position)
        if blend <= 0.0:
            continue

        var precipitation_delta: float = volume.get_precipitation_delta() * blend
        var precipitation_multiplier: float = lerpf(1.0, volume.get_precipitation_multiplier(), blend)
        intensity = clampf((intensity + precipitation_delta) * precipitation_multiplier, 0.0, 1.0)
    return intensity


static func _collect_rain_volumes_at_position(world_3d: World3D, world_position: Vector3) -> Array:
    if world_3d == null:
        return []

    var world_bucket: Dictionary = _rain_volumes_by_world.get(world_3d.get_instance_id(), {})
    if world_bucket.is_empty():
        return []

    var stale_ids: Array[int] = []
    var volumes: Array = []
    for volume_id in world_bucket.keys():
        var volume := world_bucket[volume_id] as RainVolume
        if not is_instance_valid(volume):
            stale_ids.append(volume_id)
            continue
        if not volume.is_inside_tree() or volume.get_world_3d() != world_3d:
            stale_ids.append(volume_id)
            continue
        if not volume.is_rain_volume_enabled():
            continue
        if volume.get_precipitation_blend(world_position) > 0.0:
            volumes.append(volume)

    if not stale_ids.is_empty():
        for volume_id in stale_ids:
            world_bucket.erase(volume_id)
        if world_bucket.is_empty():
            _rain_volumes_by_world.erase(world_3d.get_instance_id())
        else:
            _rain_volumes_by_world[world_3d.get_instance_id()] = world_bucket

    volumes.sort_custom(func(a: RainVolume, b: RainVolume) -> bool:
        if a.volume_priority == b.volume_priority:
            return a.get_instance_id() < b.get_instance_id()
        return a.volume_priority < b.volume_priority
    )
    return volumes
