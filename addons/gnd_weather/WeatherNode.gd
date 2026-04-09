class_name WeatherNode
extends Node3D

signal thunder(strength: float)
signal rain_strength_changed(strength: float)
signal rain_local_strength_changed(strength: float)

const RAIN_STREAK_SHADER := preload("res://scenery/shaders/rain_streak.gdshader")
const NEAR_FIELD_NAME := "RainNear"
const MID_FIELD_NAME := "RainMid"

@export_group("Nodes")
@export_node_path("Node") var skydome_path: NodePath
@export_node_path("WorldEnvironment") var world_environment_path: NodePath:
    set(value):
        world_environment_path = value
        if is_inside_tree():
            _refresh_environment_cache()

@export_group("Weather")
@export_range(0.0, 1.0, 0.001) var precipitation_intensity: float = 0.0:
    set(value):
        precipitation_intensity = clampf(value, 0.0, 1.0)
        if is_inside_tree():
            _push_weather_server_settings()
            _sync_weather_state(true)
@export_range(0.0, 1.0, 0.001) var storm_threshold: float = 0.82:
    set(value):
        storm_threshold = clampf(value, 0.0, 1.0)
        if is_inside_tree():
            _push_weather_server_settings()
            _sync_weather_state(true)

@export_group("Wind")
@export var use_global_wind: bool = true
@export var wind_direction_project_setting: StringName = &"shader_globals/gnd_wind_direction/value"
@export var wind_speed_project_setting: StringName = &"shader_globals/gnd_wind_speed/value"
@export var wind_direction: Vector2 = Vector2(0.8, 0.3)
@export_range(0.0, 8.0, 0.01) var wind_speed: float = 1.0
@export_range(0.0, 1.0, 0.01) var wind_influence: float = 0.35

@export_group("Rain")
@export var follow_height: float = 7.5
@export var near_emission_extents: Vector3 = Vector3(4.6, 3.0, 4.6)
@export var mid_emission_extents: Vector3 = Vector3(4.2, 2.8, 4.2)
@export_range(0.1, 6.0, 0.05) var density_multiplier: float = 1.2
@export_range(1.0, 80.0, 0.1) var base_fall_speed: float = 26.0
@export_range(0.5, 6.0, 0.05) var rain_streak_alpha_curve_exponent: float = 2.4
@export_range(0.1, 4.0, 0.01) var near_layer_speed_multiplier: float = 1.0
@export_range(0.1, 4.0, 0.01) var mid_layer_speed_multiplier: float = 0.78
@export var mid_layer_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var sheltered_volumetric_emission_scale: float = 0.0:
    set(value):
        sheltered_volumetric_emission_scale = clampf(value, 0.0, 1.0)
        if is_inside_tree():
            _push_weather_server_settings()
            _sync_weather_state(true)
@export var near_rain_color: Color = Color(0.72, 0.74, 0.76, 0.08):
    set(value):
        near_rain_color = value
        _sync_rain_materials()
@export var mid_rain_color: Color = Color(0.66, 0.68, 0.72, 0.055):
    set(value):
        mid_rain_color = value
        _sync_rain_materials()

@export_group("Rain Field")
@export_range(0.1, 4.0, 0.05) var near_field_spacing: float = 0.8
@export_range(0.1, 4.0, 0.05) var mid_field_spacing: float = 1.35
@export_range(0.0, 1.0, 0.01) var near_field_jitter: float = 0.38
@export_range(0.0, 1.0, 0.01) var mid_field_jitter: float = 0.48

@export_group("Rain Probes")
@export_range(0.01, 4.0, 0.01) var rain_probe_density: float = 0.25:
    set(value):
        rain_probe_density = maxf(value, 0.01)
        if is_inside_tree():
            _push_rain_probe_config()
@export_range(1, 256, 1) var rain_probe_max_count: int = 24:
    set(value):
        rain_probe_max_count = maxi(value, 1)
        if is_inside_tree():
            _push_rain_probe_config()
@export_range(0.1, 100.0, 0.1) var rain_probe_distance: float = 8.0:
    set(value):
        rain_probe_distance = maxf(value, 0.1)
        if is_inside_tree():
            _push_rain_probe_config()

@export_group("Storm")
@export var lightning_enabled: bool = true:
    set(value):
        lightning_enabled = value
        if is_inside_tree():
            _push_weather_server_settings()
            _sync_weather_state(true)
@export_range(0.1, 30.0, 0.1) var lightning_min_interval: float = 3.2:
    set(value):
        lightning_min_interval = maxf(value, 0.1)
        if is_inside_tree():
            _push_weather_server_settings()
            _sync_weather_state(true)
@export_range(0.1, 30.0, 0.1) var lightning_max_interval: float = 9.5:
    set(value):
        lightning_max_interval = maxf(value, 0.1)
        if is_inside_tree():
            _push_weather_server_settings()
            _sync_weather_state(true)
@export_range(0.1, 20.0, 0.01) var lightning_flash_decay: float = 4.8:
    set(value):
        lightning_flash_decay = maxf(value, 0.1)
        if is_inside_tree():
            _push_weather_server_settings()
            _sync_weather_state(true)

var _near_rain_field: MultiMeshInstance3D
var _mid_rain_field: MultiMeshInstance3D
var _environment: Environment
var _current_global_precipitation: float = 0.0
var _current_local_precipitation: float = 0.0
var _current_storm_factor: float = 0.0
var _current_lightning_flash: float = 0.0
var _current_shelter_factor: float = 0.0
var _current_local_emission_scale: float = 1.0

var _last_applied_precipitation: float = -1.0
var _last_applied_storm_factor: float = -1.0
var _last_applied_lightning_flash: float = -1.0
var _last_applied_local_emission_scale: float = -1.0
var _last_emitted_rain_strength: float = -1.0
var _last_emitted_local_rain_strength: float = -1.0


func _ready() -> void:
    _refresh_environment_cache()
    _connect_weather_runtime()
    _push_weather_server_settings()
    _push_rain_probe_config()
    _ensure_rain_field_nodes()
    _apply_weather_state(true)
    set_process(true)


func _exit_tree() -> void:
    _disconnect_weather_runtime()
    WeatherServer.clear_weather_observer_sample(get_world_3d())
    WeatherServer.clear_weather_runtime(get_world_3d())
    WeatherServer.clear_visible_rain_participation_cache(get_world_3d(), get_instance_id())
    WeatherServer.clear_visible_rain_probe_field_config(get_world_3d(), get_instance_id())
    WeatherServer.clear_rain_render_field_cache(get_world_3d(), get_instance_id())
    var skydome := _get_skydome()
    if skydome != null and skydome.has_method("clear_weather_overrides"):
        skydome.clear_weather_overrides()


func _process(delta: float) -> void:
    _update_follow_position()
    _update_weather_observer()
    WeatherServer.update_weather_state(get_world_3d(), delta)
    _sync_weather_state()
    _update_rain_rendering()
    _push_weather_state()


func set_precipitation_intensity(value: float) -> void:
    precipitation_intensity = value


func apply_now() -> void:
    _sync_weather_state(true)
    _apply_weather_state(true)


func get_effective_precipitation_intensity() -> float:
    return _current_local_precipitation


func get_precipitation_strength_at_position(world_position: Vector3) -> float:
    return WeatherServer.get_rain_participation_strength(
        get_world_3d(),
        world_position,
        _get_global_precipitation_setting()
    )


func get_storm_factor(precipitation_override: float = -1.0) -> float:
    if precipitation_override < 0.0:
        return _current_storm_factor
    return _compute_storm_factor(precipitation_override)


func _apply_weather_state(force: bool = false) -> void:
    _ensure_rain_field_nodes()
    _update_follow_position()
    _update_weather_observer()
    _sync_weather_state(force)
    _update_rain_rendering()
    _push_weather_state(force)


func _get_skydome() -> Node:
    if not skydome_path.is_empty():
        return get_node_or_null(skydome_path)

    var root := get_tree().current_scene
    if root != null:
        return root.find_child("Skydome", true, false)
    return null


func _get_world_environment() -> WorldEnvironment:
    if not world_environment_path.is_empty():
        return get_node_or_null(world_environment_path) as WorldEnvironment

    return null


func _get_environment() -> Environment:
    return _environment


func _refresh_environment_cache() -> void:
    var env_node := _get_world_environment()
    if env_node != null:
        _environment = env_node.environment
        return

    var world_3d := get_world_3d()
    _environment = world_3d.environment if world_3d != null else null


func _push_rain_probe_config() -> void:
    WeatherServer.configure_visible_rain_probe_field(
        get_world_3d(),
        get_instance_id(),
        rain_probe_density,
        rain_probe_max_count,
        rain_probe_distance
    )


func _connect_weather_runtime() -> void:
    var runtime := WeatherServer.get_weather_runtime(get_world_3d())
    if runtime == null:
        return

    if not runtime.weather_state_changed.is_connected(_on_weather_server_state_changed):
        runtime.weather_state_changed.connect(_on_weather_server_state_changed)
    if not runtime.thunder.is_connected(_on_weather_server_thunder):
        runtime.thunder.connect(_on_weather_server_thunder)


func _disconnect_weather_runtime() -> void:
    var runtime := WeatherServer.get_weather_runtime(get_world_3d())
    if runtime == null:
        return

    if runtime.weather_state_changed.is_connected(_on_weather_server_state_changed):
        runtime.weather_state_changed.disconnect(_on_weather_server_state_changed)
    if runtime.thunder.is_connected(_on_weather_server_thunder):
        runtime.thunder.disconnect(_on_weather_server_thunder)


func _push_weather_server_settings() -> void:
    WeatherServer.configure_weather_state(
        get_world_3d(),
        precipitation_intensity,
        storm_threshold,
        sheltered_volumetric_emission_scale,
        lightning_enabled,
        lightning_min_interval,
        lightning_max_interval,
        lightning_flash_decay
    )


func _update_weather_observer() -> void:
    var follow_target := _get_follow_target()
    if follow_target == null:
        WeatherServer.clear_weather_observer_sample(get_world_3d())
        return

    WeatherServer.set_weather_observer_sample(get_world_3d(), follow_target.global_position)


func _sync_weather_state(force: bool = false) -> void:
    if force:
        WeatherServer.update_weather_state(get_world_3d(), 0.0)
    _apply_weather_state_snapshot(WeatherServer.get_weather_state(get_world_3d()))


func _apply_weather_state_snapshot(state: Dictionary) -> void:
    if state.is_empty():
        state = _get_fallback_weather_state()

    _current_global_precipitation = clampf(float(state.get("global_precipitation", precipitation_intensity)), 0.0, 1.0)
    _current_local_precipitation = clampf(float(state.get("local_precipitation", _current_global_precipitation)), 0.0, 1.0)
    _current_storm_factor = clampf(float(state.get("storm_factor", 0.0)), 0.0, 1.0)
    _current_lightning_flash = clampf(float(state.get("lightning_flash", 0.0)), 0.0, 1.0)
    _current_shelter_factor = clampf(float(state.get("shelter_factor", 0.0)), 0.0, 1.0)
    _current_local_emission_scale = clampf(float(state.get("local_emission_scale", 1.0)), 0.0, 1.0)


func _get_fallback_weather_state() -> Dictionary:
    var global_precipitation := _get_global_precipitation_setting()
    var local_precipitation := global_precipitation
    var follow_target := _get_follow_target()
    if follow_target != null:
        local_precipitation = WeatherServer.get_rain_participation_strength(
            get_world_3d(),
            follow_target.global_position,
            global_precipitation
        )

    var shelter_factor := 0.0
    if global_precipitation > 0.0001 and local_precipitation < global_precipitation:
        shelter_factor = clampf((global_precipitation - local_precipitation) / global_precipitation, 0.0, 1.0)

    return {
        "global_precipitation": global_precipitation,
        "local_precipitation": local_precipitation,
        "storm_factor": _compute_storm_factor(local_precipitation),
        "lightning_flash": 0.0,
        "shelter_factor": shelter_factor,
        "local_emission_scale": lerpf(1.0, sheltered_volumetric_emission_scale, shelter_factor),
    }


func _get_global_precipitation_setting() -> float:
    return clampf(precipitation_intensity, 0.0, 1.0)


func _compute_storm_factor(intensity: float) -> float:
    if intensity <= storm_threshold:
        return 0.0

    var denominator := maxf(1.0 - storm_threshold, 0.0001)
    var t := clampf((intensity - storm_threshold) / denominator, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


func _on_weather_server_state_changed() -> void:
    return


func _on_weather_server_thunder(strength: float) -> void:
    thunder.emit(clampf(strength, 0.0, 1.0))


func _get_follow_target() -> Node3D:
    var viewport := get_viewport()
    if viewport != null:
        var camera := viewport.get_camera_3d()
        if camera != null:
            return camera
    return null


func _ensure_rain_field_nodes() -> void:
    if _near_rain_field == null:
        _near_rain_field = _ensure_rain_field_node(NEAR_FIELD_NAME, near_rain_color)
    if _mid_rain_field == null:
        _mid_rain_field = _ensure_rain_field_node(MID_FIELD_NAME, mid_rain_color)
    _sync_rain_materials()


func _ensure_rain_field_node(node_name: String, tint: Color) -> MultiMeshInstance3D:
    var existing_node := get_node_or_null(node_name)
    if existing_node != null and not (existing_node is MultiMeshInstance3D):
        remove_child(existing_node)
        existing_node.queue_free()

    var rain_field := get_node_or_null(node_name) as MultiMeshInstance3D
    if rain_field != null:
        return rain_field

    rain_field = MultiMeshInstance3D.new()
    rain_field.name = node_name
    rain_field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.use_custom_data = true
    multimesh.instance_count = 0
    multimesh.visible_instance_count = 0

    var quad := QuadMesh.new()
    quad.size = Vector2(0.01, 3.5)

    var material := ShaderMaterial.new()
    material.shader = RAIN_STREAK_SHADER
    material.set_shader_parameter("tint", tint)
    quad.material = material

    multimesh.mesh = quad
    rain_field.multimesh = multimesh
    add_child(rain_field)
    return rain_field


func _sync_rain_materials() -> void:
    _set_rain_field_tint(_near_rain_field, near_rain_color)
    _set_rain_field_tint(_mid_rain_field, mid_rain_color)


func _set_rain_field_tint(rain_field: MultiMeshInstance3D, tint: Color) -> void:
    var material := _get_rain_field_material(rain_field)
    if material == null:
        return
    material.set_shader_parameter("tint", tint)


func _get_rain_field_material(rain_field: MultiMeshInstance3D) -> ShaderMaterial:
    if rain_field == null or rain_field.multimesh == null:
        return null
    var quad := rain_field.multimesh.mesh as QuadMesh
    if quad == null:
        return null
    return quad.material as ShaderMaterial


func _get_rain_field_mesh(rain_field: MultiMeshInstance3D) -> QuadMesh:
    if rain_field == null or rain_field.multimesh == null:
        return null
    return rain_field.multimesh.mesh as QuadMesh


func _update_follow_position() -> void:
    var follow_target := _get_follow_target()
    if follow_target == null:
        return

    global_position = follow_target.global_position + Vector3(0.0, follow_height, 0.0)


func _update_rain_rendering() -> void:
    var follow_target := _get_follow_target()
    var global_intensity := _current_global_precipitation
    var local_intensity := _current_local_precipitation
    _emit_rain_strength_changed(global_intensity)
    _emit_local_rain_strength_changed(local_intensity)

    if follow_target == null or local_intensity <= 0.001:
        _clear_rain_field_layer(_near_rain_field)
        _clear_rain_field_layer(_mid_rain_field)
        return

    var rain_direction := _get_rain_direction(_get_wind_speed())
    var near_layer_intensity: float = _get_layer_intensity(local_intensity, false)
    var mid_layer_intensity: float = _get_layer_intensity(local_intensity, true)
    var sample_y: float = follow_target.global_position.y + 1.0

    var near_card_height: float = _get_rain_field_card_height(near_emission_extents, near_layer_intensity, false)
    var near_spacing: float = _get_rain_field_spacing(near_field_spacing)
    var near_state: Dictionary = WeatherServer.get_rain_render_field_state(
        get_world_3d(),
        get_instance_id(),
        &"near",
        follow_target.global_position,
        sample_y,
        _get_rain_field_center_y(follow_target.global_position.y, near_card_height),
        global_intensity,
        near_emission_extents,
        near_spacing,
        near_field_jitter
    )
    _update_rain_field_layer(
        _near_rain_field,
        near_state,
        near_layer_intensity,
        false,
        rain_direction,
        near_layer_speed_multiplier,
        near_emission_extents,
        near_spacing
    )

    if not mid_layer_enabled:
        _clear_rain_field_layer(_mid_rain_field)
        return

    var mid_card_height: float = _get_rain_field_card_height(mid_emission_extents, mid_layer_intensity, true)
    var mid_spacing: float = _get_rain_field_spacing(mid_field_spacing)
    var mid_state: Dictionary = WeatherServer.get_rain_render_field_state(
        get_world_3d(),
        get_instance_id(),
        &"mid",
        follow_target.global_position,
        sample_y,
        _get_rain_field_center_y(follow_target.global_position.y, mid_card_height),
        global_intensity,
        mid_emission_extents,
        mid_spacing,
        mid_field_jitter
    )
    _update_rain_field_layer(
        _mid_rain_field,
        mid_state,
        mid_layer_intensity,
        true,
        rain_direction,
        mid_layer_speed_multiplier,
        mid_emission_extents,
        mid_spacing
    )


func _update_rain_field_layer(
    rain_field: MultiMeshInstance3D,
    field_state: Dictionary,
    layer_intensity: float,
    is_mid_layer: bool,
    rain_direction: Vector3,
    speed_multiplier: float,
    extents: Vector3,
    field_spacing: float
) -> void:
    if rain_field == null or rain_field.multimesh == null:
        return

    var multimesh := rain_field.multimesh
    var positions: PackedVector3Array = field_state.get("positions", PackedVector3Array())
    var custom_data: PackedColorArray = field_state.get("custom_data", PackedColorArray())
    var visible_count: int = int(field_state.get("count", 0))

    if layer_intensity <= 0.001 or visible_count <= 0:
        multimesh.visible_instance_count = 0
        return

    if multimesh.instance_count != positions.size():
        multimesh.instance_count = positions.size()
    multimesh.visible_instance_count = visible_count

    var card_height: float = _get_rain_field_card_height(extents, layer_intensity, is_mid_layer)
    _update_rain_field_visuals(rain_field, layer_intensity, is_mid_layer, speed_multiplier, card_height, extents, field_spacing)

    var base_basis: Basis = _get_rain_field_basis(rain_direction)
    for index in range(visible_count):
        var instance_position: Vector3 = positions[index] - global_position
        var instance_custom: Color = custom_data[index]
        var variation_scale: float = lerpf(0.85, 1.15, instance_custom.b)
        var instance_basis: Basis = base_basis.scaled(Vector3.ONE * variation_scale)
        multimesh.set_instance_transform(index, Transform3D(instance_basis, instance_position))
        multimesh.set_instance_custom_data(index, instance_custom)


func _clear_rain_field_layer(rain_field: MultiMeshInstance3D) -> void:
    if rain_field == null or rain_field.multimesh == null:
        return
    rain_field.multimesh.visible_instance_count = 0


func _emit_rain_strength_changed(strength: float) -> void:
    var clamped_strength := clampf(strength, 0.0, 1.0)
    if absf(_last_emitted_rain_strength - clamped_strength) <= 0.0001:
        return
    _last_emitted_rain_strength = clamped_strength
    rain_strength_changed.emit(clamped_strength)


func _emit_local_rain_strength_changed(strength: float) -> void:
    var clamped_strength := clampf(strength, 0.0, 1.0)
    if absf(_last_emitted_local_rain_strength - clamped_strength) <= 0.0001:
        return
    _last_emitted_local_rain_strength = clamped_strength
    rain_local_strength_changed.emit(clamped_strength)


func _smooth_factor(value: float, start: float, end: float) -> float:
    var t := clampf((value - start) / maxf(end - start, 0.0001), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


func _get_rain_direction(wind_speed_value: float) -> Vector3:
    var wind_dir := _get_wind_direction()
    var lateral_strength := clampf(wind_speed_value * wind_influence * 0.22, 0.0, 0.82)
    return Vector3(wind_dir.x * lateral_strength, -1.0, wind_dir.y * lateral_strength).normalized()


func _get_layer_intensity(intensity: float, is_mid_layer: bool) -> float:
    if is_mid_layer:
        return _smooth_factor(intensity, 0.32, 0.92)
    return pow(clampf(intensity, 0.0, 1.0), 0.9)


func _get_rain_field_basis(rain_direction: Vector3) -> Basis:
    var down_axis := rain_direction.normalized()
    var reference_up := Vector3.UP
    if absf(down_axis.dot(reference_up)) > 0.98:
        reference_up = Vector3.FORWARD
    var right_axis := reference_up.cross(down_axis).normalized()
    if right_axis.length_squared() <= 0.0001:
        right_axis = Vector3.RIGHT
    var normal_axis := down_axis.cross(right_axis).normalized()
    return Basis(right_axis, down_axis, normal_axis).orthonormalized()


func _update_rain_field_visuals(
    rain_field: MultiMeshInstance3D,
    layer_intensity: float,
    is_mid_layer: bool,
    speed_multiplier: float,
    card_height: float,
    extents: Vector3,
    field_spacing: float
) -> void:
    var mesh := _get_rain_field_mesh(rain_field)
    var material := _get_rain_field_material(rain_field)
    if mesh == null or material == null:
        return

    var base_color := mid_rain_color if is_mid_layer else near_rain_color
    var target_width := (
        lerpf(0.006, 0.0105, layer_intensity)
        if not is_mid_layer
        else lerpf(0.005, 0.009, layer_intensity)
    )
    mesh.size = Vector2(target_width, card_height)

    var alpha_strength := pow(clampf(layer_intensity, 0.0, 1.0), rain_streak_alpha_curve_exponent)
    var alpha_scale := lerpf(0.02, 1.0, alpha_strength)
    var effective_color := Color(
        base_color.r,
        base_color.g,
        base_color.b,
        base_color.a * alpha_scale
    )
    material.set_shader_parameter("tint", effective_color)
    material.set_shader_parameter("width_softness", lerpf(0.14, 0.24, layer_intensity))
    material.set_shader_parameter("tail_softness", lerpf(0.24, 0.62, layer_intensity))
    material.set_shader_parameter("center_bias", lerpf(0.34, 0.68, layer_intensity))
    material.set_shader_parameter(
        "flow_speed",
        (base_fall_speed / 26.0) * lerpf(20.0, 12.0, clampf(layer_intensity, 0.0, 1.0)) * maxf(speed_multiplier, 0.1)
    )
    material.set_shader_parameter("travel_distance", card_height)
    material.set_shader_parameter("respawn_spread", field_spacing * 0.45)
    material.set_shader_parameter(
        "streak_length_scale",
        lerpf(0.18, 1.0, pow(clampf(layer_intensity, 0.0, 1.0), 0.85))
    )

    var local_height: float = maxf(card_height + 6.0, 8.0)
    rain_field.custom_aabb = AABB(
        Vector3(-extents.x - 4.0, -local_height * 0.5, -extents.z - 4.0),
        Vector3((extents.x + 4.0) * 2.0, local_height, (extents.z + 4.0) * 2.0)
    )


func _get_rain_field_card_height(extents: Vector3, layer_intensity: float, is_mid_layer: bool) -> float:
    var base_height: float = maxf(follow_height + extents.y * (1.2 if is_mid_layer else 0.95), 3.0)
    var height_scale := lerpf(0.22, 1.05, pow(clampf(layer_intensity, 0.0, 1.0), 0.9))
    return base_height * height_scale


func _get_rain_field_center_y(follow_y: float, card_height: float) -> float:
    return follow_y + maxf(card_height * 0.5 - 0.9, 0.0)


func _get_rain_field_spacing(base_spacing: float) -> float:
    return maxf(base_spacing / sqrt(maxf(density_multiplier, 0.1)), 0.1)


func _get_wind_direction() -> Vector2:
    var direction := wind_direction
    if use_global_wind and _has_project_setting(wind_direction_project_setting):
        direction = ProjectSettings.get_setting(String(wind_direction_project_setting), direction)

    if direction.length_squared() <= 0.0001:
        return Vector2(0.8, 0.3)
    return direction.normalized()


func _get_wind_speed() -> float:
    var speed := wind_speed
    if use_global_wind and _has_project_setting(wind_speed_project_setting):
        speed = float(ProjectSettings.get_setting(String(wind_speed_project_setting), speed))
    return maxf(speed, 0.0)


func _has_project_setting(setting_name: StringName) -> bool:
    return setting_name != &"" and ProjectSettings.has_setting(String(setting_name))


func _push_weather_state(force: bool = false) -> void:
    var skydome := _get_skydome()
    if skydome == null or not skydome.has_method("set_weather_overrides"):
        return

    var global_precipitation := _current_global_precipitation
    var storm_factor := _current_storm_factor
    var local_emission_scale := _current_local_emission_scale
    if not force:
        var unchanged := (
            absf(_last_applied_precipitation - global_precipitation) <= 0.0001
            and absf(_last_applied_storm_factor - storm_factor) <= 0.0001
            and absf(_last_applied_lightning_flash - _current_lightning_flash) <= 0.0001
            and absf(_last_applied_local_emission_scale - local_emission_scale) <= 0.0001
        )
        if unchanged:
            return

    skydome.set_weather_overrides(global_precipitation, storm_factor, _current_lightning_flash, local_emission_scale)
    _last_applied_precipitation = global_precipitation
    _last_applied_storm_factor = storm_factor
    _last_applied_lightning_flash = _current_lightning_flash
    _last_applied_local_emission_scale = local_emission_scale
