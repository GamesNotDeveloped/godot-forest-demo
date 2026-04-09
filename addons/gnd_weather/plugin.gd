@tool
extends EditorPlugin

const RAIN_VOLUME_GIZMO_PLUGIN_SCRIPT := preload("res://addons/gnd_weather/RainVolumeGizmoPlugin.gd")
const PROBE_BUTTON_TEXT := "Weather Probes"
const RAIN_MESHES_BUTTON_TEXT := "Rain Meshes"
const PROBE_REFRESH_INTERVAL := 0.2
const RAIN_MESH_SYNC_INTERVAL := 1.0
const PROBE_WORLD_SCALE_MIN := 0.03
const PROBE_WORLD_SCALE_MAX := 0.18
const PROBE_WORLD_SCALE_FACTOR := 0.015
const PROBE_COLOR := Color(0.25, 0.78, 1.0, 0.92)
const RAIN_MESH_NEAR_COLOR := Color(0.18, 1.0, 0.72, 0.36)
const RAIN_MESH_MID_COLOR := Color(1.0, 0.82, 0.2, 0.3)

var _rain_volume_gizmo_plugin: RainVolumeGizmoPlugin
var _weather_probes_button: CheckBox
var _rain_meshes_button: CheckBox
var _probe_refresh_timer: Timer
var _probe_mesh: SphereMesh
var _probe_material: StandardMaterial3D
var _probe_instance_rids: Array[RID] = []
var _preview_weather_node_ids: Array[int] = []
var _debug_rain_mesh_node_ids: Array[int] = []
var _rain_mesh_sync_accumulator: float = 0.0


func _enter_tree() -> void:
    WeatherServer.ensure_wind_project_settings()
    _rain_volume_gizmo_plugin = RAIN_VOLUME_GIZMO_PLUGIN_SCRIPT.new()
    _rain_volume_gizmo_plugin.undo_redo = get_undo_redo()
    add_node_3d_gizmo_plugin(_rain_volume_gizmo_plugin)
    _weather_probes_button = CheckBox.new()
    _weather_probes_button.text = PROBE_BUTTON_TEXT
    _weather_probes_button.tooltip_text = "Show weather rain probes in the 3D editor viewport."
    _weather_probes_button.toggled.connect(_on_weather_probes_toggled)
    add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _weather_probes_button)
    _rain_meshes_button = CheckBox.new()
    _rain_meshes_button.text = RAIN_MESHES_BUTTON_TEXT
    _rain_meshes_button.tooltip_text = "Show rain mesh spawn positions in the 3D editor viewport."
    _rain_meshes_button.toggled.connect(_on_rain_meshes_toggled)
    add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _rain_meshes_button)
    _probe_refresh_timer = Timer.new()
    _probe_refresh_timer.wait_time = PROBE_REFRESH_INTERVAL
    _probe_refresh_timer.one_shot = false
    _probe_refresh_timer.timeout.connect(_on_probe_refresh_timeout)
    add_child(_probe_refresh_timer, false, INTERNAL_MODE_FRONT)
    set_force_draw_over_forwarding_enabled()


func _exit_tree() -> void:
    _clear_probe_preview()
    _clear_rain_mesh_preview()
    _clear_registered_probe_configs()
    if _probe_refresh_timer != null:
        _probe_refresh_timer.stop()
        _probe_refresh_timer.queue_free()
        _probe_refresh_timer = null
    if _weather_probes_button != null:
        remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _weather_probes_button)
        _weather_probes_button.queue_free()
        _weather_probes_button = null
    if _rain_meshes_button != null:
        remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _rain_meshes_button)
        _rain_meshes_button.queue_free()
        _rain_meshes_button = null
    if _rain_volume_gizmo_plugin != null:
        remove_node_3d_gizmo_plugin(_rain_volume_gizmo_plugin)
        _rain_volume_gizmo_plugin = null


func _handles(object: Object) -> bool:
    return object is Node3D


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
    return


func _on_weather_probes_toggled(_enabled: bool) -> void:
    if _weather_probes_button != null and _weather_probes_button.button_pressed:
        _sync_debug_preview(true)
    else:
        _clear_probe_preview()
    _update_refresh_timer_state()
    if not _is_any_debug_preview_enabled():
        _clear_registered_probe_configs()


func _on_rain_meshes_toggled(_enabled: bool) -> void:
    if _rain_meshes_button != null and _rain_meshes_button.button_pressed:
        _rain_mesh_sync_accumulator = RAIN_MESH_SYNC_INTERVAL
        _sync_debug_preview(true)
    else:
        _clear_rain_mesh_preview()
    _update_refresh_timer_state()
    if not _is_any_debug_preview_enabled():
        _clear_registered_probe_configs()


func _on_probe_refresh_timeout() -> void:
    if not _is_any_debug_preview_enabled():
        return
    _rain_mesh_sync_accumulator += PROBE_REFRESH_INTERVAL
    _sync_debug_preview(false)


func _get_editor_camera() -> Camera3D:
    var editor_viewport := get_editor_interface().get_editor_viewport_3d(0)
    if editor_viewport == null:
        return null
    return editor_viewport.get_camera_3d()


func _sync_debug_preview(force_rain_mesh_sync: bool = false) -> void:
    var camera := _get_editor_camera()
    _sync_weather_node_editor_preview_cameras(camera)

    if _rain_meshes_button != null and _rain_meshes_button.button_pressed:
        if force_rain_mesh_sync or _rain_mesh_sync_accumulator >= RAIN_MESH_SYNC_INTERVAL:
            _sync_rain_mesh_debug_preview()
            _rain_mesh_sync_accumulator = 0.0
    else:
        _clear_rain_mesh_preview()
        _rain_mesh_sync_accumulator = 0.0

    if camera == null:
        _clear_probe_preview()
        return

    var world_3d := camera.get_world_3d()
    if world_3d == null:
        _clear_probe_preview()
        return

    _sync_registered_probe_configs(world_3d)
    if _weather_probes_button != null and _weather_probes_button.button_pressed:
        _sync_probe_preview(world_3d, camera)
    else:
        _clear_probe_preview()


func _sync_probe_preview(world_3d: World3D, camera: Camera3D) -> void:
    var probe_positions := WeatherServer.get_registered_visible_rain_probe_positions(world_3d, camera.global_transform, camera)
    _ensure_probe_mesh_resources()
    _ensure_instance_count(_probe_instance_rids, probe_positions.size(), _probe_mesh.get_rid(), RID(), world_3d)

    for index in range(probe_positions.size()):
        var probe_position: Vector3 = probe_positions[index]
        var probe_instance := _probe_instance_rids[index]
        if not probe_instance.is_valid():
            continue

        var distance_to_camera := camera.global_position.distance_to(probe_position)
        var probe_scale := clampf(distance_to_camera * PROBE_WORLD_SCALE_FACTOR, PROBE_WORLD_SCALE_MIN, PROBE_WORLD_SCALE_MAX)
        var transform := Transform3D(Basis().scaled(Vector3.ONE * probe_scale), probe_position)
        RenderingServer.instance_set_transform(probe_instance, transform)
        RenderingServer.instance_set_scenario(probe_instance, world_3d.scenario)


func _sync_rain_mesh_debug_preview() -> void:
    var active_weather_node_ids: Array[int] = []
    for weather_node in _get_edited_weather_nodes():
        if weather_node == null:
            continue
        active_weather_node_ids.append(weather_node.get_instance_id())
        weather_node.set_rain_mesh_debug_preview(true, RAIN_MESH_NEAR_COLOR, RAIN_MESH_MID_COLOR)

    for weather_node_id in _debug_rain_mesh_node_ids:
        if active_weather_node_ids.has(weather_node_id):
            continue
        var stale_node := instance_from_id(weather_node_id) as WeatherNode
        if stale_node != null:
            stale_node.set_rain_mesh_debug_preview(false, RAIN_MESH_NEAR_COLOR, RAIN_MESH_MID_COLOR)

    _debug_rain_mesh_node_ids = active_weather_node_ids


func _ensure_probe_mesh_resources() -> void:
    if _probe_mesh != null and _probe_material != null:
        return

    _probe_material = StandardMaterial3D.new()
    _probe_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _probe_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _probe_material.no_depth_test = false
    _probe_material.albedo_color = PROBE_COLOR
    _probe_material.emission_enabled = true
    _probe_material.emission = PROBE_COLOR

    _probe_mesh = SphereMesh.new()
    _probe_mesh.radius = 0.5
    _probe_mesh.height = 1.0
    _probe_mesh.radial_segments = 8
    _probe_mesh.rings = 4
    _probe_mesh.material = _probe_material


func _ensure_instance_count(
    instance_rids: Array[RID],
    target_count: int,
    mesh_rid: RID,
    material_rid: RID,
    world_3d: World3D
) -> void:
    while instance_rids.size() < target_count:
        var debug_instance := RenderingServer.instance_create()
        RenderingServer.instance_set_base(debug_instance, mesh_rid)
        if material_rid.is_valid():
            RenderingServer.instance_geometry_set_material_override(debug_instance, material_rid)
        RenderingServer.instance_set_scenario(debug_instance, world_3d.scenario)
        instance_rids.append(debug_instance)

    while instance_rids.size() > target_count:
        var debug_instance := instance_rids.pop_back()
        if debug_instance.is_valid():
            RenderingServer.free_rid(debug_instance)


func _clear_probe_preview() -> void:
    for probe_instance in _probe_instance_rids:
        if probe_instance.is_valid():
            RenderingServer.free_rid(probe_instance)
    _probe_instance_rids.clear()


func _clear_rain_mesh_preview() -> void:
    for weather_node_id in _debug_rain_mesh_node_ids:
        var weather_node := instance_from_id(weather_node_id) as WeatherNode
        if weather_node != null:
            weather_node.set_rain_mesh_debug_preview(false, RAIN_MESH_NEAR_COLOR, RAIN_MESH_MID_COLOR)
    _debug_rain_mesh_node_ids.clear()


func _clear_registered_probe_configs() -> void:
    var camera := _get_editor_camera()
    if camera == null:
        _preview_weather_node_ids.clear()
        return

    var world_3d := camera.get_world_3d()
    if world_3d == null:
        _preview_weather_node_ids.clear()
        return

    for weather_node_id in _preview_weather_node_ids:
        WeatherServer.clear_visible_rain_probe_field_config(world_3d, weather_node_id)
    _preview_weather_node_ids.clear()


func _sync_registered_probe_configs(world_3d: World3D) -> void:
    var active_weather_node_ids: Array[int] = []
    for weather_node in _get_edited_weather_nodes():
        if weather_node == null:
            continue

        var weather_node_id: int = weather_node.get_instance_id()
        active_weather_node_ids.append(weather_node_id)
        WeatherServer.configure_visible_rain_probe_field(
            world_3d,
            weather_node_id,
            weather_node.rain_probe_max_count,
            weather_node.rain_probe_distance
        )

    for weather_node_id in _preview_weather_node_ids:
        if active_weather_node_ids.has(weather_node_id):
            continue
        WeatherServer.clear_visible_rain_probe_field_config(world_3d, weather_node_id)

    _preview_weather_node_ids = active_weather_node_ids


func _update_refresh_timer_state() -> void:
    if _probe_refresh_timer == null:
        return
    if _is_any_debug_preview_enabled():
        _probe_refresh_timer.start()
    else:
        _probe_refresh_timer.stop()


func _is_any_debug_preview_enabled() -> bool:
    return (
        (_weather_probes_button != null and _weather_probes_button.button_pressed)
        or (_rain_meshes_button != null and _rain_meshes_button.button_pressed)
    )


func _get_edited_weather_nodes() -> Array:
    var root := get_editor_interface().get_edited_scene_root()
    if root == null:
        return []

    var weather_nodes: Array = []
    if root is WeatherNode:
        weather_nodes.append(root)

    for child in root.find_children("*", "WeatherNode", true, false):
        weather_nodes.append(child)

    return weather_nodes


func _sync_weather_node_editor_preview_cameras(camera: Camera3D) -> void:
    for weather_node in _get_edited_weather_nodes():
        if weather_node == null:
            continue
        weather_node.set_editor_preview_camera(camera)
