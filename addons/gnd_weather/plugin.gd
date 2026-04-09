@tool
extends EditorPlugin

const RAIN_VOLUME_GIZMO_PLUGIN_SCRIPT := preload("res://addons/gnd_weather/RainVolumeGizmoPlugin.gd")
const PROBE_BUTTON_TEXT := "Weather Probes"
const PROBE_REFRESH_INTERVAL := 1.0
const PROBE_WORLD_SCALE_MIN := 0.03
const PROBE_WORLD_SCALE_MAX := 0.18
const PROBE_WORLD_SCALE_FACTOR := 0.015
const PROBE_COLOR := Color(0.25, 0.78, 1.0, 0.92)

var _rain_volume_gizmo_plugin: RainVolumeGizmoPlugin
var _weather_probes_button: CheckBox
var _probe_refresh_timer: Timer
var _probe_mesh: SphereMesh
var _probe_material: StandardMaterial3D
var _probe_instance_rids: Array[RID] = []
var _preview_weather_node_ids: Array[int] = []


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
    _probe_refresh_timer = Timer.new()
    _probe_refresh_timer.wait_time = PROBE_REFRESH_INTERVAL
    _probe_refresh_timer.one_shot = false
    _probe_refresh_timer.timeout.connect(_on_probe_refresh_timeout)
    add_child(_probe_refresh_timer, false, INTERNAL_MODE_FRONT)
    set_force_draw_over_forwarding_enabled()


func _exit_tree() -> void:
    _clear_probe_preview()
    _clear_registered_probe_configs()
    if _probe_refresh_timer != null:
        _probe_refresh_timer.stop()
        _probe_refresh_timer.queue_free()
        _probe_refresh_timer = null
    if _weather_probes_button != null:
        remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _weather_probes_button)
        _weather_probes_button.queue_free()
        _weather_probes_button = null
    if _rain_volume_gizmo_plugin != null:
        remove_node_3d_gizmo_plugin(_rain_volume_gizmo_plugin)
        _rain_volume_gizmo_plugin = null


func _handles(object: Object) -> bool:
    return object is Node3D


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
    return


func _on_weather_probes_toggled(_enabled: bool) -> void:
    if _weather_probes_button != null and _weather_probes_button.button_pressed:
        _sync_probe_preview()
        if _probe_refresh_timer != null:
            _probe_refresh_timer.start()
    else:
        if _probe_refresh_timer != null:
            _probe_refresh_timer.stop()
        _clear_probe_preview()
        _clear_registered_probe_configs()


func _on_probe_refresh_timeout() -> void:
    if _weather_probes_button == null or not _weather_probes_button.button_pressed:
        return
    _sync_probe_preview()


func _get_editor_camera() -> Camera3D:
    var editor_viewport := get_editor_interface().get_editor_viewport_3d(0)
    if editor_viewport == null:
        return null
    return editor_viewport.get_camera_3d()


func _sync_probe_preview() -> void:
    var camera := _get_editor_camera()
    if camera == null:
        _clear_probe_preview()
        return

    var world_3d := camera.get_world_3d()
    if world_3d == null:
        _clear_probe_preview()
        return

    _sync_registered_probe_configs(world_3d)
    var probe_positions := WeatherServer.get_registered_visible_rain_probe_positions(
        world_3d,
        camera.global_transform,
        camera
    )
    _ensure_probe_mesh_resources()
    _ensure_probe_instance_count(probe_positions.size(), world_3d)

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


func _ensure_probe_instance_count(target_count: int, world_3d: World3D) -> void:
    while _probe_instance_rids.size() < target_count:
        var probe_instance := RenderingServer.instance_create()
        RenderingServer.instance_set_base(probe_instance, _probe_mesh.get_rid())
        RenderingServer.instance_set_scenario(probe_instance, world_3d.scenario)
        _probe_instance_rids.append(probe_instance)

    while _probe_instance_rids.size() > target_count:
        var probe_instance := _probe_instance_rids.pop_back()
        if probe_instance.is_valid():
            RenderingServer.free_rid(probe_instance)


func _clear_probe_preview() -> void:
    for probe_instance in _probe_instance_rids:
        if probe_instance.is_valid():
            RenderingServer.free_rid(probe_instance)
    _probe_instance_rids.clear()


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
            weather_node.rain_probe_density,
            weather_node.rain_probe_max_count,
            weather_node.rain_probe_distance
        )

    for weather_node_id in _preview_weather_node_ids:
        if active_weather_node_ids.has(weather_node_id):
            continue
        WeatherServer.clear_visible_rain_probe_field_config(world_3d, weather_node_id)

    _preview_weather_node_ids = active_weather_node_ids


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
