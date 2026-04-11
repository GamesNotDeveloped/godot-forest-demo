class_name WeatherServer
extends RefCounted

const WIND_DIRECTION_GLOBAL := &"gnd_wind_direction"
const WIND_SPEED_GLOBAL := &"gnd_wind_speed"
const WIND_TIME_GLOBAL := &"gnd_wind_time"
const WIND_DIRECTION_SETTING := &"shader_globals/gnd_wind_direction"
const WIND_SPEED_SETTING := &"shader_globals/gnd_wind_speed"
const WIND_STRENGTH_SETTING := &"shader_globals/gnd_wind_strength"
const WIND_TIME_SETTING := &"shader_globals/gnd_wind_time"
const WIND_TURBULENCE_SETTING := &"shader_globals/gnd_wind_turbulence"
const WIND_PATTERN_SETTING := &"shader_globals/gnd_wind_pattern"
const WIND_DIRECTION_VALUE_SETTING := &"shader_globals/gnd_wind_direction/value"
const WIND_SPEED_VALUE_SETTING := &"shader_globals/gnd_wind_speed/value"
const WIND_STRENGTH_VALUE_SETTING := &"shader_globals/gnd_wind_strength/value"
const WIND_TIME_VALUE_SETTING := &"shader_globals/gnd_wind_time/value"
const WIND_TURBULENCE_VALUE_SETTING := &"shader_globals/gnd_wind_turbulence/value"
const WIND_PATTERN_VALUE_SETTING := &"shader_globals/gnd_wind_pattern/value"
const VISIBLE_RAIN_PROBE_REFERENCE_DISTANCE := 8.0
const RAIN_FIELD_FEATHER_RENDER_CUTOFF := 0.24
const RAIN_PROBE_SUPPRESSIVE_FEATHER_BLEND_START := 0.28
const RAIN_PROBE_SUPPRESSIVE_FEATHER_BLEND_END := 0.94
const RAIN_FIELD_LOWER_CULL_SAMPLE_FACTORS := [0.18, 0.42]
const RAIN_FIELD_RESAMPLE_INTERVAL_MSEC := 250
const RAIN_FIELD_FOOTPRINT_OFFSETS := [
    Vector3.ZERO,
    Vector3(1.0, 0.0, 1.0),
    Vector3(1.0, 0.0, -1.0),
    Vector3(-1.0, 0.0, 1.0),
    Vector3(-1.0, 0.0, -1.0),
]

class WeatherRuntime extends RefCounted:
    signal weather_state_changed
    signal thunder(strength: float)

    var precipitation_intensity: float = 0.0
    var cloud_density: float = 0.15
    var precipitation_wind_strength: float = 4.0
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
    var _lightning_activity: float = 0.0
    var _lightning_flash: float = 0.0
    var _shelter_factor: float = 0.0
    var _local_emission_scale: float = 1.0
    var _wind_time: float = 0.0
    var _pending_flash_pulses: int = 0
    var _next_flash_delay: float = 0.0
    var _next_lightning_burst: float = 0.0
    var _rng := RandomNumberGenerator.new()

    func _init() -> void:
        _rng.randomize()

    func configure(
        next_precipitation_intensity: float,
        next_cloud_density: float,
        next_precipitation_wind_strength: float,
        next_storm_threshold: float,
        next_sheltered_volumetric_emission_scale: float,
        next_lightning_enabled: bool,
        next_lightning_min_interval: float,
        next_lightning_max_interval: float,
        next_lightning_flash_decay: float
    ) -> void:
        precipitation_intensity = clampf(next_precipitation_intensity, 0.0, 1.0)
        cloud_density = clampf(next_cloud_density, 0.0, 1.0)
        precipitation_wind_strength = maxf(next_precipitation_wind_strength, 0.0)
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
        if delta > 0.0:
            _wind_time += delta * WeatherServer._get_weather_controlled_wind_speed_for_runtime(self, 1.0)

        var next_flash := move_toward(_lightning_flash, 0.0, delta * lightning_flash_decay)
        if absf(next_flash - _lightning_flash) > 0.0001:
            _lightning_flash = next_flash
            changed = true

        if not lightning_enabled or _lightning_activity <= 0.02:
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
                _trigger_lightning_pulse(_lightning_activity)
            elif changed:
                weather_state_changed.emit()
            return

        _next_lightning_burst -= delta
        if _next_lightning_burst <= 0.0:
            _pending_flash_pulses = _rng.randi_range(1, 3)
            _next_flash_delay = _rng.randf_range(0.02, 0.18)
            _reset_lightning_schedule(_lightning_activity)
            weather_state_changed.emit()
        elif changed:
            weather_state_changed.emit()

    func get_weather_state() -> Dictionary:
        return {
            "global_precipitation": _global_precipitation,
            "cloud_density": cloud_density,
            "local_precipitation": _local_precipitation,
            "storm_factor": _storm_factor,
            "lightning_flash": _lightning_flash,
            "shelter_factor": _shelter_factor,
            "local_emission_scale": _local_emission_scale,
        }

    func _refresh_precipitation_state(world_3d: World3D) -> bool:
        var next_global := clampf(precipitation_intensity, 0.0, 1.0)
        var next_local := next_global
        var lightning_multiplier := 1.0
        if _has_observer_sample and world_3d != null:
            next_local = WeatherServer.get_rain_participation_strength(
                world_3d,
                _observer_position,
                next_global
            )
            lightning_multiplier = WeatherServer.get_rain_lightning_multiplier(
                world_3d,
                _observer_position
            )

        var next_storm_input := clampf(maxf(next_global, next_local), 0.0, 1.0)
        var next_storm := _compute_storm_factor(next_storm_input)
        var next_lightning_activity := clampf(next_storm * lightning_multiplier, 0.0, 1.0)
        var next_shelter := 0.0
        if next_global > 0.0001 and next_local < next_global:
            next_shelter = clampf((next_global - next_local) / next_global, 0.0, 1.0)
        var next_local_emission_scale := lerpf(1.0, sheltered_volumetric_emission_scale, next_shelter)

        var changed := (
            absf(_global_precipitation - next_global) > 0.0001
            or absf(_local_precipitation - next_local) > 0.0001
            or absf(_storm_factor - next_storm) > 0.0001
            or absf(_lightning_activity - next_lightning_activity) > 0.0001
            or absf(_shelter_factor - next_shelter) > 0.0001
            or absf(_local_emission_scale - next_local_emission_scale) > 0.0001
        )

        _global_precipitation = next_global
        _local_precipitation = next_local
        _storm_factor = next_storm
        _lightning_activity = next_lightning_activity
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
static var _rain_volume_revision_by_world: Dictionary = {}
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
    _notify_rain_volumes_changed(world_3d)


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
    _notify_rain_volumes_changed(world_3d)


static func mark_rain_volumes_changed(world_3d: World3D) -> void:
    _notify_rain_volumes_changed(world_3d)


static func get_rain_volume_revision(world_3d: World3D) -> int:
    if world_3d == null:
        return 0

    return int(_rain_volume_revision_by_world.get(world_3d.get_instance_id(), 0))


static func configure_visible_rain_probe_field(
    world_3d: World3D,
    cache_key: int,
    max_probes: int,
    distance: float
) -> void:
    if world_3d == null or cache_key < 0:
        return

    var world_id := world_3d.get_instance_id()
    var world_bucket: Dictionary = _visible_rain_probe_configs_by_world.get(world_id, {})
    world_bucket[cache_key] = {
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

    var world_id := world_3d.get_instance_id()
    _weather_runtime_by_world.erase(world_id)
    _rain_volume_revision_by_world.erase(world_id)
    _apply_weather_controlled_wind(null)


static func configure_weather_state(
    world_3d: World3D,
    precipitation_intensity: float,
    cloud_density: float,
    precipitation_wind_strength: float,
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
        cloud_density,
        precipitation_wind_strength,
        storm_threshold,
        sheltered_volumetric_emission_scale,
        lightning_enabled,
        lightning_min_interval,
        lightning_max_interval,
        lightning_flash_decay
    )
    _apply_weather_controlled_wind(world_3d)


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
    _apply_weather_controlled_wind(world_3d)


static func get_weather_state(world_3d: World3D) -> Dictionary:
    var runtime := get_weather_runtime(world_3d)
    if runtime == null:
        return {}
    return runtime.get_weather_state()


static func ensure_wind_project_settings() -> void:
    var dirty := false

    if not ProjectSettings.has_setting(String(WIND_DIRECTION_SETTING)):
        ProjectSettings.set_setting(String(WIND_DIRECTION_SETTING), {
            "type": "vec2",
            "value": Vector2(0.8, 0.3),
        })
        dirty = true

    if not ProjectSettings.has_setting(String(WIND_SPEED_SETTING)):
        ProjectSettings.set_setting(String(WIND_SPEED_SETTING), {
            "type": "float",
            "value": 1.0,
        })
        dirty = true

    if not ProjectSettings.has_setting(String(WIND_STRENGTH_SETTING)):
        ProjectSettings.set_setting(String(WIND_STRENGTH_SETTING), {
            "type": "float",
            "value": 4.0,
        })
        dirty = true

    if not ProjectSettings.has_setting(String(WIND_TIME_SETTING)):
        ProjectSettings.set_setting(String(WIND_TIME_SETTING), {
            "type": "float",
            "value": 0.0,
        })
        dirty = true

    if not ProjectSettings.has_setting(String(WIND_TURBULENCE_SETTING)):
        ProjectSettings.set_setting(String(WIND_TURBULENCE_SETTING), {
            "type": "float",
            "value": 1.0,
        })
        dirty = true

    if not ProjectSettings.has_setting(String(WIND_PATTERN_SETTING)):
        ProjectSettings.set_setting(String(WIND_PATTERN_SETTING), {
            "type": "sampler2D",
            "value": "res://grass/wind_pattern.png",
        })
        dirty = true

    if dirty and Engine.is_editor_hint():
        ProjectSettings.save()


static func get_global_wind_direction(fallback: Vector2 = Vector2(0.8, 0.3)) -> Vector2:
    ensure_wind_project_settings()
    var direction := fallback
    if ProjectSettings.has_setting(String(WIND_DIRECTION_VALUE_SETTING)):
        direction = ProjectSettings.get_setting(String(WIND_DIRECTION_VALUE_SETTING), direction)
    if direction.length_squared() <= 0.0001:
        return Vector2(0.8, 0.3)
    return direction.normalized()


static func get_global_wind_speed(fallback: float = 1.0) -> float:
    ensure_wind_project_settings()
    if ProjectSettings.has_setting(String(WIND_SPEED_VALUE_SETTING)):
        return maxf(float(ProjectSettings.get_setting(String(WIND_SPEED_VALUE_SETTING), fallback)), 0.0)
    return maxf(fallback, 0.0)


static func get_precipitation_wind_strength(fallback: float = 4.0) -> float:
    ensure_wind_project_settings()
    if ProjectSettings.has_setting(String(WIND_STRENGTH_VALUE_SETTING)):
        return maxf(float(ProjectSettings.get_setting(String(WIND_STRENGTH_VALUE_SETTING), fallback)), 0.0)
    return maxf(fallback, 0.0)


static func get_weather_controlled_wind_speed(world_3d: World3D, fallback: float = 1.0) -> float:
    var base_speed := get_global_wind_speed(fallback)
    var precipitation_boost := 0.0
    if world_3d != null:
        var runtime := _weather_runtime_by_world.get(world_3d.get_instance_id()) as WeatherRuntime
        if runtime != null:
            precipitation_boost = clampf(runtime.precipitation_intensity, 0.0, 1.0) * runtime.precipitation_wind_strength
    return maxf(base_speed + precipitation_boost, 0.0)


static func get_weather_controlled_wind_time(world_3d: World3D) -> float:
    if world_3d == null:
        return 0.0
    var runtime := _weather_runtime_by_world.get(world_3d.get_instance_id()) as WeatherRuntime
    if runtime == null:
        return 0.0
    return runtime._wind_time


static func _get_weather_controlled_wind_speed_for_runtime(runtime: WeatherRuntime, fallback: float = 1.0) -> float:
    if runtime == null:
        return get_global_wind_speed(fallback)
    var base_speed := get_global_wind_speed(fallback)
    var precipitation_boost := clampf(runtime.precipitation_intensity, 0.0, 1.0) * runtime.precipitation_wind_strength
    return maxf(base_speed + precipitation_boost, 0.0)


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
        int(config.get("max_probes", 24)),
        float(config.get("distance", 8.0))
    )


static func get_configured_visible_rain_probe_spacing(
    world_3d: World3D,
    cache_key: int,
    camera: Camera3D
) -> float:
    var layout: Dictionary = get_configured_visible_rain_probe_field_layout(world_3d, cache_key, camera)
    return _get_visible_rain_probe_layout_spacing(layout)


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


static func get_rain_lightning_multiplier(
    world_3d: World3D,
    world_position: Vector3
) -> float:
    return get_rain_lightning_multiplier_for_volumes(
        _get_active_rain_volumes(world_3d),
        world_position
    )


static func get_rain_lightning_multiplier_for_volumes(
    volumes: Array,
    world_position: Vector3
) -> float:
    return _get_rain_lightning_multiplier_for_sorted_volumes(_sort_rain_volumes(volumes), world_position)


static func _get_rain_lightning_multiplier_for_sorted_volumes(
    sorted_volumes: Array,
    world_position: Vector3
) -> float:
    var multiplier := 1.0
    for volume in sorted_volumes:
        var blend: float = volume.get_precipitation_blend(world_position)
        if blend <= 0.0:
            continue

        multiplier *= lerpf(1.0, volume.get_lightning_multiplier(), blend)
    return maxf(multiplier, 0.0)


static func get_rain_participation_strength_for_volumes(
    volumes: Array,
    world_position: Vector3,
    base_strength: float
) -> float:
    return _get_rain_participation_strength_for_sorted_volumes(_sort_rain_volumes(volumes), world_position, base_strength)


static func _get_rain_participation_strength_for_sorted_volumes(
    sorted_volumes: Array,
    world_position: Vector3,
    base_strength: float
) -> float:
    var intensity: float = clampf(base_strength, 0.0, 1.0)
    for volume in sorted_volumes:
        var blend: float = volume.get_precipitation_blend(world_position)
        if blend <= 0.0:
            continue

        var precipitation_delta: float = volume.get_precipitation_delta() * blend
        var precipitation_multiplier: float = lerpf(1.0, volume.get_precipitation_multiplier(), blend)
        intensity = clampf((intensity + precipitation_delta) * precipitation_multiplier, 0.0, 1.0)
    return intensity


static func _get_rain_probe_render_strength_for_sorted_volumes(
    sorted_volumes: Array,
    world_position: Vector3,
    base_strength: float
) -> float:
    var intensity: float = clampf(base_strength, 0.0, 1.0)
    for volume in sorted_volumes:
        var blend: float = volume.get_precipitation_blend(world_position)
        if blend <= 0.0:
            continue

        var precipitation_multiplier: float = volume.get_precipitation_multiplier()
        var full_intensity: float = clampf(
            (intensity + volume.get_precipitation_delta()) * precipitation_multiplier,
            0.0,
            1.0
        )
        var effective_blend: float = blend
        if full_intensity < intensity - 0.0001 and blend < 1.0:
            effective_blend = _remap_probe_render_suppressive_blend(blend)

        var precipitation_delta: float = volume.get_precipitation_delta() * effective_blend
        var blended_multiplier: float = lerpf(1.0, precipitation_multiplier, effective_blend)
        intensity = clampf((intensity + precipitation_delta) * blended_multiplier, 0.0, 1.0)
    return intensity


static func _get_rain_participation_strength_for_volumes_footprint_min(
    sorted_volumes: Array,
    world_position: Vector3,
    base_strength: float,
    footprint_half_extent: float
) -> float:
    var min_intensity := 1.0

    for sample_offset_scale in RAIN_FIELD_FOOTPRINT_OFFSETS:
        min_intensity = minf(
            min_intensity,
            _get_rain_probe_render_strength_for_sorted_volumes(
                sorted_volumes,
                world_position + sample_offset_scale * footprint_half_extent,
                base_strength
            )
        )
        if min_intensity <= 0.001:
            return 0.0

    return clampf(min_intensity, 0.0, 1.0)


static func get_rain_render_field_state(
    world_3d: World3D,
    cache_key: int,
    layer_key: StringName,
    view_transform: Transform3D,
    camera: Camera3D,
    view_origin: Vector3,
    sample_y: float,
    layer_center_y: float,
    base_strength: float,
    half_extents: Vector3,
    cell_spacing: float,
    jitter_ratio: float,
    rain_direction: Vector3,
    rain_motion_half_span: float
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
    var last_refresh_time_msec: int = int(cache.get("last_refresh_time_msec", 0))
    var cached_active_count: int = int(cache.get("active_count", 0))
    var current_time_msec: int = Time.get_ticks_msec()
    if (
        last_refresh_time_msec > 0
        and current_time_msec - last_refresh_time_msec < RAIN_FIELD_RESAMPLE_INTERVAL_MSEC
    ):
        return {
            "count": cached_active_count,
            "positions": positions,
            "custom_data": custom_data,
        }

    var jitter_amount: float = clampf(jitter_ratio, 0.0, 1.0) * spacing * 0.5
    var normalized_rain_direction := rain_direction.normalized()
    var snapped_grid_x: int = int(floor(view_origin.x / spacing))
    var snapped_grid_z: int = int(floor(view_origin.z / spacing))
    var active_count: int = 0
    var probe_layout: Dictionary = {}
    var probe_values := PackedFloat32Array()

    if camera != null:
        probe_layout = get_configured_visible_rain_probe_field_layout(world_3d, cache_key, camera)
        if not probe_layout.is_empty():
            probe_values = _get_visible_rain_probe_values_for_layout(
                world_3d,
                cache_key,
                view_transform,
                camera,
                clamped_strength,
                active_volumes,
                probe_layout
            )

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

            var instance_position := Vector3(world_x, layer_center_y, world_z)
            var intensity: float = _get_rain_participation_strength_for_volumes_footprint_min(
                active_volumes,
                instance_position,
                clamped_strength,
                spacing * 0.45
            )
            var feather_mask := _get_rain_field_feather_render_mask_for_volumes(
                active_volumes,
                instance_position,
                clamped_strength,
                spacing * 0.45
            )
            if rain_motion_half_span > 0.0:
                for sample_factor in RAIN_FIELD_LOWER_CULL_SAMPLE_FACTORS:
                    var lower_sample_position := instance_position + normalized_rain_direction * (rain_motion_half_span * float(sample_factor))
                    intensity = minf(
                        intensity,
                        _get_rain_participation_strength_for_volumes_footprint_min(
                            active_volumes,
                            lower_sample_position,
                            clamped_strength,
                            spacing * 0.45
                        )
                    )
                    feather_mask = minf(
                        feather_mask,
                        _get_rain_field_feather_render_mask_for_volumes(
                            active_volumes,
                            lower_sample_position,
                            clamped_strength,
                            spacing * 0.45
                        )
                    )
            if not probe_layout.is_empty() and not probe_values.is_empty():
                var probe_intensity := _sample_visible_rain_probe_layout_footprint_min(
                    view_transform,
                    probe_layout,
                    instance_position,
                    spacing * 0.45,
                    probe_values
                )
                if probe_intensity >= 0.0:
                    intensity = minf(intensity, probe_intensity)
                if rain_motion_half_span > 0.0:
                    for sample_factor in RAIN_FIELD_LOWER_CULL_SAMPLE_FACTORS:
                        var lower_probe_sample_position := instance_position + normalized_rain_direction * (rain_motion_half_span * float(sample_factor))
                        var lower_probe_intensity := _sample_visible_rain_probe_layout_footprint_min(
                            view_transform,
                            probe_layout,
                            lower_probe_sample_position,
                            spacing * 0.45,
                            probe_values
                        )
                        if lower_probe_intensity >= 0.0:
                            intensity = minf(intensity, lower_probe_intensity)
            if intensity <= 0.001 or feather_mask <= RAIN_FIELD_FEATHER_RENDER_CUTOFF:
                continue

            positions[active_count] = instance_position
            custom_data[active_count] = Color(
                _get_rain_field_phase(grid_x, grid_z),
                _get_rain_field_instance_alpha(intensity) * _normalize_rain_field_feather_mask(feather_mask),
                _get_rain_field_variation(grid_x, grid_z),
                _hash_to_unit_float(grid_x, grid_z, 313)
            )
            active_count += 1

    cache["positions"] = positions
    cache["custom_data"] = custom_data
    cache["active_count"] = active_count
    cache["last_refresh_time_msec"] = current_time_msec
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
        values[probe_index] = _get_rain_probe_render_strength_for_sorted_volumes(
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


static func _notify_rain_volumes_changed(world_3d: World3D) -> void:
    if world_3d == null:
        return

    var world_id := world_3d.get_instance_id()
    _rain_volume_revision_by_world[world_id] = int(_rain_volume_revision_by_world.get(world_id, 0)) + 1
    _visible_rain_probe_fields_by_world.erase(world_id)
    _rain_render_fields_by_world.erase(world_id)


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


static func _apply_weather_controlled_wind(world_3d: World3D) -> void:
    ensure_wind_project_settings()
    RenderingServer.global_shader_parameter_set(StringName(WIND_DIRECTION_GLOBAL), get_global_wind_direction())
    RenderingServer.global_shader_parameter_set(
        StringName(WIND_SPEED_GLOBAL),
        get_weather_controlled_wind_speed(world_3d)
    )
    RenderingServer.global_shader_parameter_set(
        StringName(WIND_TIME_GLOBAL),
        get_weather_controlled_wind_time(world_3d)
    )


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
            "active_count": 0,
            "last_refresh_time_msec": 0,
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
    max_probes: int,
    distance: float
) -> Dictionary:
    var safe_max_probes: int = maxi(max_probes, 1)
    var safe_far_depth: float = maxf(distance, 0.1)
    var near_depth: float = minf(0.1, safe_far_depth)
    var axis_count: int = maxi(int(ceil(pow(float(safe_max_probes), 1.0 / 3.0))), 1)
    var probe_columns: int = axis_count
    var probe_rows: int = axis_count
    var probe_depth_slices: int = axis_count
    var probe_count: int = probe_columns * probe_rows * probe_depth_slices

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


static func _get_visible_rain_probe_layout_spacing(layout: Dictionary) -> float:
    if layout.is_empty():
        return -1.0

    var distance: float = maxf(float(layout.get("distance", 0.1)), 0.1)
    var near_depth: float = clampf(float(layout.get("near_depth", 0.1)), 0.0, distance)
    var depth_span: float = maxf(distance - near_depth, 0.1)
    var field_scale: float = maxf(float(layout.get("field_scale", 1.0)), 0.01)
    var half_extent: float = maxf(distance * field_scale * 0.5, 0.05)
    var columns: int = maxi(int(layout.get("probe_columns", 1)), 1)
    var rows: int = maxi(int(layout.get("probe_rows", 1)), 1)
    var depth_slices: int = maxi(int(layout.get("probe_depth_slices", 1)), 1)
    var lateral_spacing: float = (half_extent * 2.0) / maxf(float(columns - 1), 1.0)
    var vertical_spacing: float = (half_extent * 2.0) / maxf(float(rows - 1), 1.0)
    var depth_spacing: float = depth_span / maxf(float(depth_slices - 1), 1.0)
    return maxf(minf(lateral_spacing, minf(vertical_spacing, depth_spacing)), 0.1)


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
    var u: float = 0.0 if probe_columns <= 1 else lerpf(-1.0, 1.0, float(column_index) / float(probe_columns - 1))
    var v: float = 0.0 if probe_rows <= 1 else lerpf(1.0, -1.0, float(row_index) / float(probe_rows - 1))

    var safe_near_depth: float = minf(maxf(near_depth, 0.0), far_depth)
    var depth_span: float = maxf(far_depth - safe_near_depth, 0.1)
    var center_depth: float = safe_near_depth + depth_span * 0.5
    var half_extent: float = maxf(far_depth * field_scale * 0.5, 0.05)
    var forward: Vector3 = -view_transform.basis.z
    var right: Vector3 = view_transform.basis.x
    var up: Vector3 = view_transform.basis.y
    return (
        view_transform.origin
        + forward * center_depth
        + right * (u * half_extent)
        + up * (v * half_extent)
        + forward * ((depth_t - 0.5) * depth_span)
    )


static func _get_visible_rain_probe_half_extents(camera: Camera3D, depth: float, field_scale: float) -> Vector2:
    var half_extent: float = maxf(depth * field_scale * 0.5, 0.05)
    return Vector2(half_extent, half_extent)


static func _get_visible_rain_probe_values_for_layout(
    world_3d: World3D,
    cache_key: int,
    view_transform: Transform3D,
    camera: Camera3D,
    base_strength: float,
    active_volumes: Array,
    layout: Dictionary
) -> PackedFloat32Array:
    var columns: int = maxi(int(layout.get("probe_columns", 1)), 1)
    var rows: int = maxi(int(layout.get("probe_rows", 1)), 1)
    var depth_slices: int = maxi(int(layout.get("probe_depth_slices", 1)), 1)
    var probe_count: int = columns * rows * depth_slices
    var cache: Dictionary = _ensure_visible_rain_probe_field_cache(world_3d, cache_key, probe_count)
    var values: PackedFloat32Array = cache.get("values", PackedFloat32Array())
    var near_depth: float = float(layout.get("near_depth", 0.5))
    var far_depth: float = float(layout.get("far_depth", 1.0))
    var field_scale: float = float(layout.get("field_scale", 1.0))

    for probe_index in range(probe_count):
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
        values[probe_index] = _get_rain_probe_render_strength_for_sorted_volumes(
            active_volumes,
            probe_position,
            base_strength
        )

    cache["values"] = values
    cache["cursor"] = 0
    cache["ready"] = true
    _store_visible_rain_probe_field_cache(world_3d, cache_key, cache)
    return values


static func _sample_visible_rain_probe_layout_nearest(
    view_transform: Transform3D,
    layout: Dictionary,
    world_position: Vector3,
    values: PackedFloat32Array
) -> float:
    if layout.is_empty() or values.is_empty():
        return -1.0

    var columns: int = maxi(int(layout.get("probe_columns", 1)), 1)
    var rows: int = maxi(int(layout.get("probe_rows", 1)), 1)
    var depth_slices: int = maxi(int(layout.get("probe_depth_slices", 1)), 1)
    var near_depth: float = maxf(float(layout.get("near_depth", 0.1)), 0.0)
    var far_depth: float = maxf(float(layout.get("far_depth", near_depth)), near_depth)
    var field_scale: float = maxf(float(layout.get("field_scale", 1.0)), 0.01)
    var half_extents: Vector2 = _get_visible_rain_probe_half_extents(null, far_depth, field_scale)
    var forward: Vector3 = -view_transform.basis.z
    var right: Vector3 = view_transform.basis.x
    var up: Vector3 = view_transform.basis.y
    var sample_offset: Vector3 = world_position - view_transform.origin
    var sample_depth: float = forward.dot(sample_offset)
    if sample_depth < near_depth or sample_depth > far_depth:
        return -1.0

    var sample_x: float = right.dot(sample_offset)
    var sample_y: float = up.dot(sample_offset)
    if absf(sample_x) > half_extents.x or absf(sample_y) > half_extents.y:
        return -1.0

    var column_t: float = 0.0 if columns <= 1 else clampf(sample_x / maxf(half_extents.x * 2.0, 0.0001) + 0.5, 0.0, 1.0)
    var row_t: float = 0.0 if rows <= 1 else clampf(0.5 - sample_y / maxf(half_extents.y * 2.0, 0.0001), 0.0, 1.0)
    var depth_t: float = 0.0 if depth_slices <= 1 else clampf(
        (sample_depth - near_depth) / maxf(far_depth - near_depth, 0.0001),
        0.0,
        1.0
    )
    var column_index: int = int(round(column_t * float(columns - 1)))
    var row_index: int = int(round(row_t * float(rows - 1)))
    var slice_index: int = int(round(depth_t * float(depth_slices - 1)))
    var probe_index: int = slice_index * columns * rows + row_index * columns + column_index
    if probe_index < 0 or probe_index >= values.size():
        return -1.0
    return values[probe_index]


static func _sample_visible_rain_probe_layout_footprint_min(
    view_transform: Transform3D,
    layout: Dictionary,
    world_position: Vector3,
    footprint_half_extent: float,
    values: PackedFloat32Array
) -> float:
    var min_value := INF
    var has_sample := false

    for sample_offset_scale in RAIN_FIELD_FOOTPRINT_OFFSETS:
        var sample_value := _sample_visible_rain_probe_layout_nearest(
            view_transform,
            layout,
            world_position + sample_offset_scale * footprint_half_extent,
            values
        )
        if sample_value < 0.0:
            continue
        min_value = minf(min_value, sample_value)
        has_sample = true
        if min_value <= 0.001:
            return 0.0

    if not has_sample:
        return -1.0
    return min_value


static func _get_rain_field_feather_render_mask_for_volumes(
    sorted_volumes: Array,
    world_position: Vector3,
    base_strength: float,
    footprint_half_extent: float
) -> float:
    var min_mask := 1.0

    for sample_offset_scale in RAIN_FIELD_FOOTPRINT_OFFSETS:
        min_mask = minf(
            min_mask,
            _get_rain_field_feather_render_mask_at_position(
                sorted_volumes,
                world_position + sample_offset_scale * footprint_half_extent,
                base_strength
            )
        )
        if min_mask <= 0.0:
            return 0.0

    return clampf(min_mask, 0.0, 1.0)


static func _remap_probe_render_suppressive_blend(blend: float) -> float:
    return _smoothstepf(
        clampf(blend, 0.0, 1.0),
        RAIN_PROBE_SUPPRESSIVE_FEATHER_BLEND_START,
        RAIN_PROBE_SUPPRESSIVE_FEATHER_BLEND_END
    )


static func _get_rain_field_feather_render_mask_at_position(
    sorted_volumes: Array,
    world_position: Vector3,
    base_strength: float
) -> float:
    var intensity: float = clampf(base_strength, 0.0, 1.0)
    var render_mask := 1.0

    for volume in sorted_volumes:
        var blend: float = volume.get_precipitation_blend(world_position)
        if blend <= 0.0:
            continue

        var full_intensity: float = clampf(
            (intensity + volume.get_precipitation_delta()) * volume.get_precipitation_multiplier(),
            0.0,
            1.0
        )
        var blended_intensity: float = clampf(
            (intensity + volume.get_precipitation_delta() * blend)
            * lerpf(1.0, volume.get_precipitation_multiplier(), blend),
            0.0,
            1.0
        )
        if full_intensity < intensity - 0.0001:
            var suppression_strength := clampf(
                (intensity - full_intensity) / maxf(intensity, 0.0001),
                0.0,
                1.0
            )
            var feather_visibility := 1.0 - smoothstep(0.08, 0.62, blend)
            render_mask *= lerpf(1.0, feather_visibility, suppression_strength)

        intensity = blended_intensity

    return clampf(render_mask, 0.0, 1.0)


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


static func _get_rain_field_instance_alpha(intensity: float) -> float:
    return pow(clampf(intensity, 0.0, 1.0), 1.65)


static func _normalize_rain_field_feather_mask(feather_mask: float) -> float:
    return clampf(
        (feather_mask - RAIN_FIELD_FEATHER_RENDER_CUTOFF) / maxf(1.0 - RAIN_FIELD_FEATHER_RENDER_CUTOFF, 0.0001),
        0.0,
        1.0
    )


static func _smoothstepf(value: float, start: float, end: float) -> float:
    var t := clampf((value - start) / maxf(end - start, 0.0001), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


static func _get_rain_field_variation(grid_x: int, grid_z: int) -> float:
    return _hash_to_unit_float(grid_x, grid_z, 211)


static func _hash_to_unit_float(grid_x: int, grid_z: int, seed: int) -> float:
    var hash_value: int = int(grid_x * 73856093) ^ int(grid_z * 19349663) ^ int(seed * 83492791)
    hash_value = int(((hash_value << 13) ^ hash_value) & 0x7fffffff)
    return float(hash_value % 1000000) / 999999.0
