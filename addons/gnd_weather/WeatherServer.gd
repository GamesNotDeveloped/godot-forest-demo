class_name WeatherServer
extends RefCounted

class WeatherRuntime extends RefCounted:
    signal weather_state_changed
    signal thunder(strength: float)

    var precipitation_intensity: float = 0.0
    var storm_threshold: float = 0.82
    var sheltered_volumetric_emission_scale: float = 0.0
    var lightning_enabled: bool = true
    var lightning_min_interval: float = 3.2
    var lightning_max_interval: float = 9.5
    var lightning_flash_decay: float = 4.8

    var _observer_position: Vector3 = Vector3.ZERO
    var _has_observer_sample: bool = false
    var _global_precipitation: float = 0.0
    var _local_precipitation: float = 0.0
    var _storm_factor: float = 0.0
    var _lightning_flash: float = 0.0
    var _shelter_factor: float = 0.0
    var _local_emission_scale: float = 1.0
    var _pending_flash_pulses: int = 0
    var _next_flash_delay: float = 0.0
    var _next_lightning_burst: float = 0.0
    var _rng := RandomNumberGenerator.new()

    func _init() -> void:
        _rng.randomize()

    func configure(
        next_precipitation_intensity: float,
        next_storm_threshold: float,
        next_sheltered_volumetric_emission_scale: float,
        next_lightning_enabled: bool,
        next_lightning_min_interval: float,
        next_lightning_max_interval: float,
        next_lightning_flash_decay: float
    ) -> void:
        precipitation_intensity = clampf(next_precipitation_intensity, 0.0, 1.0)
        storm_threshold = clampf(next_storm_threshold, 0.0, 1.0)
        sheltered_volumetric_emission_scale = clampf(next_sheltered_volumetric_emission_scale, 0.0, 1.0)
        lightning_enabled = next_lightning_enabled
        lightning_min_interval = maxf(next_lightning_min_interval, 0.1)
        lightning_max_interval = maxf(next_lightning_max_interval, 0.1)
        lightning_flash_decay = maxf(next_lightning_flash_decay, 0.1)

    func set_observer_sample(world_position: Vector3) -> void:
        _observer_position = world_position
        _has_observer_sample = true

    func clear_observer_sample() -> void:
        _observer_position = Vector3.ZERO
        _has_observer_sample = false

    func update(world_3d: World3D, delta: float) -> void:
        var changed := _refresh_precipitation_state(world_3d)

        var next_flash := move_toward(_lightning_flash, 0.0, delta * lightning_flash_decay)
        if absf(next_flash - _lightning_flash) > 0.0001:
            _lightning_flash = next_flash
            changed = true

        if not lightning_enabled or _storm_factor <= 0.02:
            if _pending_flash_pulses != 0 or _next_flash_delay != 0.0 or _next_lightning_burst != 0.0:
                _pending_flash_pulses = 0
                _next_flash_delay = 0.0
                _next_lightning_burst = 0.0
                changed = true
            if changed:
                weather_state_changed.emit()
            return

        if _pending_flash_pulses > 0:
            _next_flash_delay -= delta
            if _next_flash_delay <= 0.0:
                _trigger_lightning_pulse(_storm_factor)
            elif changed:
                weather_state_changed.emit()
            return

        _next_lightning_burst -= delta
        if _next_lightning_burst <= 0.0:
            _pending_flash_pulses = _rng.randi_range(1, 3)
            _next_flash_delay = _rng.randf_range(0.02, 0.18)
            _reset_lightning_schedule(_storm_factor)
            weather_state_changed.emit()
        elif changed:
            weather_state_changed.emit()

    func get_weather_state() -> Dictionary:
        return {
            "global_precipitation": _global_precipitation,
            "local_precipitation": _local_precipitation,
            "storm_factor": _storm_factor,
            "lightning_flash": _lightning_flash,
            "shelter_factor": _shelter_factor,
            "local_emission_scale": _local_emission_scale,
        }

    func _refresh_precipitation_state(world_3d: World3D) -> bool:
        var next_global := clampf(precipitation_intensity, 0.0, 1.0)
        var next_local := next_global
        if _has_observer_sample and world_3d != null:
            next_local = WeatherServer.get_rain_participation_strength(
                world_3d,
                _observer_position,
                next_global
            )

        var next_storm := _compute_storm_factor(next_local)
        var next_shelter := 0.0
        if next_global > 0.0001 and next_local < next_global:
            next_shelter = clampf((next_global - next_local) / next_global, 0.0, 1.0)
        var next_local_emission_scale := lerpf(1.0, sheltered_volumetric_emission_scale, next_shelter)

        var changed := (
            absf(_global_precipitation - next_global) > 0.0001
            or absf(_local_precipitation - next_local) > 0.0001
            or absf(_storm_factor - next_storm) > 0.0001
            or absf(_shelter_factor - next_shelter) > 0.0001
            or absf(_local_emission_scale - next_local_emission_scale) > 0.0001
        )

        _global_precipitation = next_global
        _local_precipitation = next_local
        _storm_factor = next_storm
        _shelter_factor = next_shelter
        _local_emission_scale = next_local_emission_scale

        return changed

    func _compute_storm_factor(intensity: float) -> float:
        if intensity <= storm_threshold:
            return 0.0

        var denominator := maxf(1.0 - storm_threshold, 0.0001)
        var t := clampf((intensity - storm_threshold) / denominator, 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)

    func _trigger_lightning_pulse(storm_factor: float) -> void:
        var flash_strength := _rng.randf_range(0.62, 1.0) * (0.52 + storm_factor * 0.48)
        _lightning_flash = maxf(_lightning_flash, flash_strength)
        thunder.emit(clampf(flash_strength, 0.0, 1.0))
        _pending_flash_pulses -= 1

        if _pending_flash_pulses > 0:
            _next_flash_delay = _rng.randf_range(0.05, 0.22)

        weather_state_changed.emit()

    func _reset_lightning_schedule(storm_factor: float) -> void:
        var min_interval := lerpf(lightning_max_interval * 0.45, lightning_min_interval, clampf(storm_factor, 0.0, 1.0))
        var max_interval := lerpf(lightning_max_interval * 1.15, lightning_max_interval * 0.55, clampf(storm_factor, 0.0, 1.0))
        min_interval = maxf(0.35, min_interval)
        max_interval = maxf(min_interval + 0.1, max_interval)
        _next_lightning_burst = _rng.randf_range(min_interval, max_interval)

static var _rain_volumes_by_world: Dictionary = {}
static var _visible_rain_probe_fields_by_world: Dictionary = {}
static var _visible_rain_probe_configs_by_world: Dictionary = {}
static var _weather_runtime_by_world: Dictionary = {}
static var _rain_render_fields_by_world: Dictionary = {}


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


static func configure_visible_rain_probe_field(
    world_3d: World3D,
    cache_key: int,
    density: float,
    max_probes: int,
    distance: float
) -> void:
    if world_3d == null or cache_key < 0:
        return

    var world_id := world_3d.get_instance_id()
    var world_bucket: Dictionary = _visible_rain_probe_configs_by_world.get(world_id, {})
    world_bucket[cache_key] = {
        "density": maxf(density, 0.01),
        "max_probes": maxi(max_probes, 1),
        "distance": maxf(distance, 0.1),
    }
    _visible_rain_probe_configs_by_world[world_id] = world_bucket
    clear_visible_rain_participation_cache(world_3d, cache_key)


static func clear_visible_rain_probe_field_config(world_3d: World3D, cache_key: int) -> void:
    if world_3d == null or cache_key < 0:
        return

    var world_id := world_3d.get_instance_id()
    var world_bucket: Dictionary = _visible_rain_probe_configs_by_world.get(world_id, {})
    if world_bucket.is_empty():
        return

    world_bucket.erase(cache_key)
    if world_bucket.is_empty():
        _visible_rain_probe_configs_by_world.erase(world_id)
    else:
        _visible_rain_probe_configs_by_world[world_id] = world_bucket

    clear_visible_rain_participation_cache(world_3d, cache_key)


static func get_weather_runtime(world_3d: World3D) -> WeatherRuntime:
    if world_3d == null:
        return null

    var world_id := world_3d.get_instance_id()
    var runtime := _weather_runtime_by_world.get(world_id) as WeatherRuntime
    if runtime != null:
        return runtime

    runtime = WeatherRuntime.new()
    _weather_runtime_by_world[world_id] = runtime
    return runtime


static func clear_weather_runtime(world_3d: World3D) -> void:
    if world_3d == null:
        return

    _weather_runtime_by_world.erase(world_3d.get_instance_id())


static func configure_weather_state(
    world_3d: World3D,
    precipitation_intensity: float,
    storm_threshold: float,
    sheltered_volumetric_emission_scale: float,
    lightning_enabled: bool,
    lightning_min_interval: float,
    lightning_max_interval: float,
    lightning_flash_decay: float
) -> void:
    var runtime := get_weather_runtime(world_3d)
    if runtime == null:
        return

    runtime.configure(
        precipitation_intensity,
        storm_threshold,
        sheltered_volumetric_emission_scale,
        lightning_enabled,
        lightning_min_interval,
        lightning_max_interval,
        lightning_flash_decay
    )


static func set_weather_observer_sample(world_3d: World3D, world_position: Vector3) -> void:
    var runtime := get_weather_runtime(world_3d)
    if runtime == null:
        return
    runtime.set_observer_sample(world_position)


static func clear_weather_observer_sample(world_3d: World3D) -> void:
    var runtime := get_weather_runtime(world_3d)
    if runtime == null:
        return
    runtime.clear_observer_sample()


static func update_weather_state(world_3d: World3D, delta: float) -> void:
    var runtime := get_weather_runtime(world_3d)
    if runtime == null:
        return
    runtime.update(world_3d, delta)


static func get_weather_state(world_3d: World3D) -> Dictionary:
    var runtime := get_weather_runtime(world_3d)
    if runtime == null:
        return {}
    return runtime.get_weather_state()


static func get_configured_visible_rain_probe_field_layout(
    world_3d: World3D,
    cache_key: int,
    camera: Camera3D
) -> Dictionary:
    if world_3d == null or cache_key < 0:
        return {}

    var world_id := world_3d.get_instance_id()
    var world_bucket: Dictionary = _visible_rain_probe_configs_by_world.get(world_id, {})
    var config: Dictionary = world_bucket.get(cache_key, {})
    if config.is_empty():
        return {}

    return _build_visible_rain_probe_field_layout(
        camera,
        float(config.get("density", 0.25)),
        int(config.get("max_probes", 24)),
        float(config.get("distance", 8.0))
    )


static func get_registered_visible_rain_probe_positions(
    world_3d: World3D,
    view_transform: Transform3D,
    camera: Camera3D
) -> PackedVector3Array:
    if world_3d == null:
        return PackedVector3Array()

    var world_id := world_3d.get_instance_id()
    var world_bucket: Dictionary = _visible_rain_probe_configs_by_world.get(world_id, {})
    if world_bucket.is_empty():
        return PackedVector3Array()

    var positions := PackedVector3Array()
    for cache_key in world_bucket.keys():
        var layout: Dictionary = get_configured_visible_rain_probe_field_layout(world_3d, int(cache_key), camera)
        if layout.is_empty():
            continue

        var field_positions := get_visible_rain_probe_positions(
            view_transform,
            camera,
            int(layout.get("probe_columns", 1)),
            int(layout.get("probe_rows", 1)),
            int(layout.get("probe_depth_slices", 1)),
            float(layout.get("near_depth", 0.5)),
            float(layout.get("far_depth", 1.0)),
            float(layout.get("field_scale", 1.0))
        )
        positions.append_array(field_positions)

    return positions


static func get_rain_participation_strength(
    world_3d: World3D,
    world_position: Vector3,
    base_strength: float
) -> float:
    return get_rain_participation_strength_for_volumes(
        _get_active_rain_volumes(world_3d),
        world_position,
        base_strength
    )


static func get_rain_participation_strength_for_volumes(
    volumes: Array,
    world_position: Vector3,
    base_strength: float
) -> float:
    var intensity: float = clampf(base_strength, 0.0, 1.0)
    for volume in _sort_rain_volumes(volumes):
        var blend: float = volume.get_precipitation_blend(world_position)
        if blend <= 0.0:
            continue

        var precipitation_delta: float = volume.get_precipitation_delta() * blend
        var precipitation_multiplier: float = lerpf(1.0, volume.get_precipitation_multiplier(), blend)
        intensity = clampf((intensity + precipitation_delta) * precipitation_multiplier, 0.0, 1.0)
    return intensity


static func get_rain_render_field_state(
    world_3d: World3D,
    cache_key: int,
    layer_key: StringName,
    view_origin: Vector3,
    sample_y: float,
    layer_center_y: float,
    base_strength: float,
    half_extents: Vector3,
    cell_spacing: float,
    jitter_ratio: float
) -> Dictionary:
    if world_3d == null or cache_key < 0 or layer_key == &"":
        return {
            "count": 0,
            "positions": PackedVector3Array(),
            "custom_data": PackedColorArray(),
        }

    var clamped_strength: float = clampf(base_strength, 0.0, 1.0)
    var active_volumes: Array = _get_active_rain_volumes(world_3d)
    if clamped_strength <= 0.001 and active_volumes.is_empty():
        clear_rain_render_field_cache(world_3d, cache_key)
        return {
            "count": 0,
            "positions": PackedVector3Array(),
            "custom_data": PackedColorArray(),
        }

    var spacing: float = maxf(cell_spacing, 0.1)
    var safe_half_extents := Vector3(
        maxf(absf(half_extents.x), spacing * 0.5),
        maxf(absf(half_extents.y), 0.1),
        maxf(absf(half_extents.z), spacing * 0.5)
    )
    var radius_x: int = maxi(1, int(ceil(safe_half_extents.x / spacing)))
    var radius_z: int = maxi(1, int(ceil(safe_half_extents.z / spacing)))
    var columns: int = radius_x * 2 + 1
    var rows: int = radius_z * 2 + 1
    var max_count: int = columns * rows
    var cache: Dictionary = _ensure_rain_render_field_cache(world_3d, cache_key, layer_key, max_count)
    var positions: PackedVector3Array = cache.get("positions", PackedVector3Array())
    var custom_data: PackedColorArray = cache.get("custom_data", PackedColorArray())
    var jitter_amount: float = clampf(jitter_ratio, 0.0, 1.0) * spacing * 0.5
    var snapped_grid_x: int = int(floor(view_origin.x / spacing))
    var snapped_grid_z: int = int(floor(view_origin.z / spacing))
    var active_count: int = 0

    for row_index in range(rows):
        var grid_z: int = snapped_grid_z + row_index - radius_z
        for column_index in range(columns):
            var grid_x: int = snapped_grid_x + column_index - radius_x
            var jitter_x: float = _get_rain_field_jitter(grid_x, grid_z, 17) * jitter_amount
            var jitter_z: float = _get_rain_field_jitter(grid_x, grid_z, 43) * jitter_amount
            var world_x: float = float(grid_x) * spacing + jitter_x
            var world_z: float = float(grid_z) * spacing + jitter_z
            if absf(world_x - view_origin.x) > safe_half_extents.x + spacing:
                continue
            if absf(world_z - view_origin.z) > safe_half_extents.z + spacing:
                continue

            var sample_position := Vector3(world_x, sample_y, world_z)
            var intensity: float = get_rain_participation_strength_for_volumes(
                active_volumes,
                sample_position,
                clamped_strength
            )
            if intensity <= 0.001:
                continue

            positions[active_count] = Vector3(world_x, layer_center_y, world_z)
            custom_data[active_count] = Color(
                _get_rain_field_phase(grid_x, grid_z),
                intensity,
                _get_rain_field_variation(grid_x, grid_z),
                _hash_to_unit_float(grid_x, grid_z, 313)
            )
            active_count += 1

    cache["positions"] = positions
    cache["custom_data"] = custom_data
    _store_rain_render_field_cache(world_3d, cache_key, layer_key, cache)
    return {
        "count": active_count,
        "positions": positions,
        "custom_data": custom_data,
    }


static func get_visible_rain_participation_strength(
    world_3d: World3D,
    cache_key: int,
    view_transform: Transform3D,
    camera: Camera3D,
    base_strength: float,
    probe_columns: int,
    probe_rows: int,
    probe_depth_slices: int,
    near_depth: float,
    far_depth: float,
    field_scale: float,
    refresh_budget: int
) -> float:
    var state: Dictionary = get_visible_rain_probe_field_state(
        world_3d,
        cache_key,
        view_transform,
        camera,
        base_strength,
        probe_columns,
        probe_rows,
        probe_depth_slices,
        near_depth,
        far_depth,
        field_scale,
        refresh_budget
    )
    return float(state.get("strength", 0.0))


static func get_configured_visible_rain_participation_strength(
    world_3d: World3D,
    cache_key: int,
    view_transform: Transform3D,
    camera: Camera3D,
    base_strength: float
) -> float:
    var state := get_configured_visible_rain_probe_field_state(
        world_3d,
        cache_key,
        view_transform,
        camera,
        base_strength
    )
    return float(state.get("strength", 0.0))


static func get_visible_rain_probe_field_state(
    world_3d: World3D,
    cache_key: int,
    view_transform: Transform3D,
    camera: Camera3D,
    base_strength: float,
    probe_columns: int,
    probe_rows: int,
    probe_depth_slices: int,
    near_depth: float,
    far_depth: float,
    field_scale: float,
    refresh_budget: int
) -> Dictionary:
    if world_3d == null or cache_key < 0:
        return {
            "strength": 0.0,
            "nearest_depth": 0.0,
            "has_visible_rain": false,
        }

    var clamped_strength: float = clampf(base_strength, 0.0, 1.0)
    var active_volumes: Array = _get_active_rain_volumes(world_3d)
    if clamped_strength <= 0.001 and active_volumes.is_empty():
        clear_visible_rain_participation_cache(world_3d, cache_key)
        return {
            "strength": 0.0,
            "nearest_depth": 0.0,
            "has_visible_rain": false,
        }

    var columns: int = maxi(probe_columns, 1)
    var rows: int = maxi(probe_rows, 1)
    var depth_slices: int = maxi(probe_depth_slices, 1)
    var probe_count: int = columns * rows * depth_slices
    var budget: int = clampi(refresh_budget, 1, probe_count)
    var cache: Dictionary = _ensure_visible_rain_probe_field_cache(world_3d, cache_key, probe_count)
    var values: PackedFloat32Array = cache.get("values", PackedFloat32Array())
    var cursor: int = int(cache.get("cursor", 0))
    var ready: bool = bool(cache.get("ready", false))

    if not ready:
        budget = probe_count

    for offset in range(budget):
        var probe_index: int = (cursor + offset) % probe_count
        var probe_position: Vector3 = _get_visible_rain_probe_world_position(
            view_transform,
            camera,
            columns,
            rows,
            depth_slices,
            near_depth,
            far_depth,
            field_scale,
            probe_index
        )
        values[probe_index] = get_rain_participation_strength_for_volumes(
            active_volumes,
            probe_position,
            clamped_strength
        )

    cache["values"] = values
    cache["cursor"] = (cursor + budget) % probe_count
    cache["ready"] = true
    _store_visible_rain_probe_field_cache(world_3d, cache_key, cache)
    return _get_visible_rain_probe_field_state(
        values,
        columns * rows,
        depth_slices,
        near_depth,
        far_depth
    )


static func get_configured_visible_rain_probe_field_state(
    world_3d: World3D,
    cache_key: int,
    view_transform: Transform3D,
    camera: Camera3D,
    base_strength: float
) -> Dictionary:
    var layout: Dictionary = get_configured_visible_rain_probe_field_layout(world_3d, cache_key, camera)
    if layout.is_empty():
        return {
            "strength": 0.0,
            "nearest_depth": 0.0,
            "has_visible_rain": false,
        }

    return get_visible_rain_probe_field_state(
        world_3d,
        cache_key,
        view_transform,
        camera,
        base_strength,
        int(layout.get("probe_columns", 1)),
        int(layout.get("probe_rows", 1)),
        int(layout.get("probe_depth_slices", 1)),
        float(layout.get("near_depth", 0.5)),
        float(layout.get("far_depth", 1.0)),
        float(layout.get("field_scale", 1.0)),
        int(layout.get("refresh_budget", 1))
    )


static func get_visible_rain_probe_positions(
    view_transform: Transform3D,
    camera: Camera3D,
    probe_columns: int,
    probe_rows: int,
    probe_depth_slices: int,
    near_depth: float,
    far_depth: float,
    field_scale: float
) -> PackedVector3Array:
    var columns: int = maxi(probe_columns, 1)
    var rows: int = maxi(probe_rows, 1)
    var depth_slices: int = maxi(probe_depth_slices, 1)
    var probe_count: int = columns * rows * depth_slices
    var positions := PackedVector3Array()
    positions.resize(probe_count)

    for probe_index in range(probe_count):
        positions[probe_index] = _get_visible_rain_probe_world_position(
            view_transform,
            camera,
            columns,
            rows,
            depth_slices,
            near_depth,
            far_depth,
            field_scale,
            probe_index
        )

    return positions


static func clear_visible_rain_participation_cache(world_3d: World3D, cache_key: int) -> void:
    if world_3d == null or cache_key < 0:
        return

    var world_id: int = world_3d.get_instance_id()
    var world_fields: Dictionary = _visible_rain_probe_fields_by_world.get(world_id, {})
    if world_fields.is_empty():
        return

    world_fields.erase(cache_key)
    if world_fields.is_empty():
        _visible_rain_probe_fields_by_world.erase(world_id)
    else:
        _visible_rain_probe_fields_by_world[world_id] = world_fields


static func clear_rain_render_field_cache(world_3d: World3D, cache_key: int) -> void:
    if world_3d == null or cache_key < 0:
        return

    var world_id: int = world_3d.get_instance_id()
    var world_fields: Dictionary = _rain_render_fields_by_world.get(world_id, {})
    if world_fields.is_empty():
        return

    var cache_prefix: String = "%s:" % [cache_key]
    var stale_keys: Array[String] = []
    for field_cache_id in world_fields.keys():
        var field_cache_key: String = str(field_cache_id)
        if field_cache_key.begins_with(cache_prefix):
            stale_keys.append(field_cache_key)

    for field_cache_key in stale_keys:
        world_fields.erase(field_cache_key)

    if world_fields.is_empty():
        _rain_render_fields_by_world.erase(world_id)
    else:
        _rain_render_fields_by_world[world_id] = world_fields


static func _collect_rain_volumes_at_position(world_3d: World3D, world_position: Vector3) -> Array:
    var volumes: Array = []
    for volume in _get_active_rain_volumes(world_3d):
        if volume.get_precipitation_blend(world_position) > 0.0:
            volumes.append(volume)
    return volumes


static func _get_active_rain_volumes(world_3d: World3D) -> Array:
    if world_3d == null:
        return []

    var world_id: int = world_3d.get_instance_id()
    var world_bucket: Dictionary = _rain_volumes_by_world.get(world_id, {})
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
        volumes.append(volume)

    if not stale_ids.is_empty():
        for volume_id in stale_ids:
            world_bucket.erase(volume_id)
        if world_bucket.is_empty():
            _rain_volumes_by_world.erase(world_id)
        else:
            _rain_volumes_by_world[world_id] = world_bucket

    return _sort_rain_volumes(volumes)


static func _sort_rain_volumes(volumes: Array) -> Array:
    var sorted_volumes: Array = []
    for volume in volumes:
        var rain_volume := volume as RainVolume
        if rain_volume == null:
            continue
        if not is_instance_valid(rain_volume):
            continue
        if not rain_volume.is_rain_volume_enabled():
            continue
        sorted_volumes.append(rain_volume)

    sorted_volumes.sort_custom(func(a: RainVolume, b: RainVolume) -> bool:
        if a.volume_priority == b.volume_priority:
            return a.get_instance_id() < b.get_instance_id()
        return a.volume_priority < b.volume_priority
    )
    return sorted_volumes


static func _ensure_visible_rain_probe_field_cache(world_3d: World3D, cache_key: int, probe_count: int) -> Dictionary:
    var world_id: int = world_3d.get_instance_id()
    var world_fields: Dictionary = _visible_rain_probe_fields_by_world.get(world_id, {})
    var cache: Dictionary = world_fields.get(cache_key, {})
    var current_count: int = int(cache.get("count", -1))
    var values: PackedFloat32Array = cache.get("values", PackedFloat32Array())

    if current_count != probe_count or values.size() != probe_count:
        values = PackedFloat32Array()
        values.resize(probe_count)
        cache = {
            "count": probe_count,
            "cursor": 0,
            "ready": false,
            "values": values,
        }
        world_fields[cache_key] = cache
        _visible_rain_probe_fields_by_world[world_id] = world_fields

    return cache


static func _store_visible_rain_probe_field_cache(world_3d: World3D, cache_key: int, cache: Dictionary) -> void:
    var world_id: int = world_3d.get_instance_id()
    var world_fields: Dictionary = _visible_rain_probe_fields_by_world.get(world_id, {})
    world_fields[cache_key] = cache
    _visible_rain_probe_fields_by_world[world_id] = world_fields


static func _ensure_rain_render_field_cache(
    world_3d: World3D,
    cache_key: int,
    layer_key: StringName,
    max_count: int
) -> Dictionary:
    var world_id: int = world_3d.get_instance_id()
    var world_fields: Dictionary = _rain_render_fields_by_world.get(world_id, {})
    var field_cache_id: String = _make_rain_render_field_cache_id(cache_key, layer_key)
    var cache: Dictionary = world_fields.get(field_cache_id, {})
    var current_count: int = int(cache.get("max_count", -1))
    var positions: PackedVector3Array = cache.get("positions", PackedVector3Array())
    var custom_data: PackedColorArray = cache.get("custom_data", PackedColorArray())

    if current_count != max_count or positions.size() != max_count or custom_data.size() != max_count:
        positions = PackedVector3Array()
        positions.resize(max_count)
        custom_data = PackedColorArray()
        custom_data.resize(max_count)
        cache = {
            "max_count": max_count,
            "positions": positions,
            "custom_data": custom_data,
        }
        world_fields[field_cache_id] = cache
        _rain_render_fields_by_world[world_id] = world_fields

    return cache


static func _store_rain_render_field_cache(
    world_3d: World3D,
    cache_key: int,
    layer_key: StringName,
    cache: Dictionary
) -> void:
    var world_id: int = world_3d.get_instance_id()
    var world_fields: Dictionary = _rain_render_fields_by_world.get(world_id, {})
    world_fields[_make_rain_render_field_cache_id(cache_key, layer_key)] = cache
    _rain_render_fields_by_world[world_id] = world_fields


static func _make_rain_render_field_cache_id(cache_key: int, layer_key: StringName) -> String:
    return "%s:%s" % [cache_key, String(layer_key)]


static func _build_visible_rain_probe_field_layout(
    camera: Camera3D,
    density: float,
    max_probes: int,
    distance: float
) -> Dictionary:
    var safe_density: float = maxf(density, 0.01)
    var safe_max_probes: int = maxi(max_probes, 1)
    var safe_far_depth: float = maxf(distance, 0.1)
    var near_depth: float = minf(maxf(safe_far_depth * 0.25, 0.5), safe_far_depth)
    var far_half_extents: Vector2 = _get_visible_rain_probe_half_extents(camera, safe_far_depth, 1.0)
    var full_width: float = maxf(far_half_extents.x * 2.0, 0.1)
    var full_height: float = maxf(far_half_extents.y * 2.0, 0.1)

    var probe_columns: int = maxi(int(ceil(full_width * safe_density)) + 1, 1)
    var probe_rows: int = maxi(int(ceil(full_height * safe_density)) + 1, 1)
    var probe_depth_slices: int = maxi(int(ceil(safe_far_depth * safe_density * 0.35)) + 1, 1)
    var probe_count: int = probe_columns * probe_rows * probe_depth_slices

    if probe_count > safe_max_probes:
        var scale: float = pow(float(probe_count) / float(safe_max_probes), 1.0 / 3.0)
        probe_columns = maxi(int(floor(float(probe_columns) / scale)), 1)
        probe_rows = maxi(int(floor(float(probe_rows) / scale)), 1)
        probe_depth_slices = maxi(int(floor(float(probe_depth_slices) / scale)), 1)
        probe_count = probe_columns * probe_rows * probe_depth_slices

        while probe_count > safe_max_probes:
            if probe_columns >= probe_rows and probe_columns >= probe_depth_slices and probe_columns > 1:
                probe_columns -= 1
            elif probe_rows >= probe_depth_slices and probe_rows > 1:
                probe_rows -= 1
            elif probe_depth_slices > 1:
                probe_depth_slices -= 1
            else:
                break
            probe_count = probe_columns * probe_rows * probe_depth_slices

    return {
        "density": safe_density,
        "max_probes": safe_max_probes,
        "distance": safe_far_depth,
        "probe_columns": probe_columns,
        "probe_rows": probe_rows,
        "probe_depth_slices": probe_depth_slices,
        "near_depth": near_depth,
        "far_depth": safe_far_depth,
        "field_scale": 1.0,
        "refresh_budget": probe_columns * probe_rows * probe_depth_slices,
    }


static func _get_visible_rain_probe_world_position(
    view_transform: Transform3D,
    camera: Camera3D,
    probe_columns: int,
    probe_rows: int,
    probe_depth_slices: int,
    near_depth: float,
    far_depth: float,
    field_scale: float,
    probe_index: int
) -> Vector3:
    var slice_index: int = probe_index / (probe_columns * probe_rows)
    var plane_index: int = probe_index % (probe_columns * probe_rows)
    var row_index: int = plane_index / probe_columns
    var column_index: int = plane_index % probe_columns

    var depth_t: float = 0.0 if probe_depth_slices <= 1 else float(slice_index) / float(probe_depth_slices - 1)
    var depth: float = lerpf(maxf(near_depth, 0.1), maxf(far_depth, near_depth), depth_t)
    var u: float = 0.0 if probe_columns <= 1 else lerpf(-1.0, 1.0, float(column_index) / float(probe_columns - 1))
    var v: float = 0.0 if probe_rows <= 1 else lerpf(1.0, -1.0, float(row_index) / float(probe_rows - 1))

    var half_extents: Vector2 = _get_visible_rain_probe_half_extents(camera, depth, field_scale)
    var forward: Vector3 = -view_transform.basis.z
    var right: Vector3 = view_transform.basis.x
    var up: Vector3 = view_transform.basis.y
    return (
        view_transform.origin
        + forward * depth
        + right * (u * half_extents.x)
        + up * (v * half_extents.y)
    )


static func _get_visible_rain_probe_half_extents(camera: Camera3D, depth: float, field_scale: float) -> Vector2:
    var aspect: float = 16.0 / 9.0
    if camera != null:
        var viewport := camera.get_viewport()
        if viewport != null:
            var visible_rect: Rect2 = viewport.get_visible_rect()
            if visible_rect.size.y > 0.0:
                aspect = visible_rect.size.x / visible_rect.size.y

    var half_height: float
    if camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
        half_height = camera.size * 0.5
    else:
        var vertical_fov: float = 70.0 if camera == null else camera.fov
        half_height = tan(deg_to_rad(vertical_fov) * 0.5) * depth

    half_height *= maxf(field_scale, 0.01)
    var half_width: float = half_height * aspect
    return Vector2(half_width, half_height)


static func _get_visible_rain_probe_field_max(values: PackedFloat32Array) -> float:
    var visible_intensity: float = 0.0
    for value in values:
        visible_intensity = maxf(visible_intensity, value)
    return visible_intensity


static func _get_visible_rain_probe_field_state(
    values: PackedFloat32Array,
    plane_probe_count: int,
    probe_depth_slices: int,
    near_depth: float,
    far_depth: float
) -> Dictionary:
    var visible_intensity: float = 0.0
    var nearest_visible_depth: float = 0.0
    var has_visible_rain: bool = false

    for probe_index in range(values.size()):
        var value: float = values[probe_index]
        if value <= 0.001:
            continue

        visible_intensity = maxf(visible_intensity, value)
        var depth: float = _get_visible_rain_probe_depth(
            plane_probe_count,
            probe_depth_slices,
            near_depth,
            far_depth,
            probe_index
        )
        if not has_visible_rain or depth < nearest_visible_depth:
            nearest_visible_depth = depth
            has_visible_rain = true

    return {
        "strength": visible_intensity,
        "nearest_depth": nearest_visible_depth,
        "has_visible_rain": has_visible_rain,
    }


static func _get_visible_rain_probe_depth(
    plane_probe_count: int,
    probe_depth_slices: int,
    near_depth: float,
    far_depth: float,
    probe_index: int
) -> float:
    var safe_plane_probe_count: int = maxi(plane_probe_count, 1)
    var safe_depth_slices: int = maxi(probe_depth_slices, 1)
    var slice_index: int = 0 if safe_depth_slices <= 1 else probe_index / safe_plane_probe_count
    slice_index = clampi(slice_index, 0, safe_depth_slices - 1)
    var depth_t: float = 0.0 if safe_depth_slices <= 1 else float(slice_index) / float(safe_depth_slices - 1)
    return lerpf(maxf(near_depth, 0.1), maxf(far_depth, near_depth), depth_t)


static func _get_rain_field_jitter(grid_x: int, grid_z: int, seed: int) -> float:
    return _hash_to_unit_float(grid_x, grid_z, seed) * 2.0 - 1.0


static func _get_rain_field_phase(grid_x: int, grid_z: int) -> float:
    return _hash_to_unit_float(grid_x, grid_z, 101)


static func _get_rain_field_variation(grid_x: int, grid_z: int) -> float:
    return _hash_to_unit_float(grid_x, grid_z, 211)


static func _hash_to_unit_float(grid_x: int, grid_z: int, seed: int) -> float:
    var hash_value: int = int(grid_x * 73856093) ^ int(grid_z * 19349663) ^ int(seed * 83492791)
    hash_value = int(((hash_value << 13) ^ hash_value) & 0x7fffffff)
    return float(hash_value % 1000000) / 999999.0
