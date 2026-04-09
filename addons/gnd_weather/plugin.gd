@tool
extends EditorPlugin

const RAIN_VOLUME_GIZMO_PLUGIN_SCRIPT := preload("res://addons/gnd_weather/RainVolumeGizmoPlugin.gd")
const RAIN_VOLUME_SCRIPT := preload("res://addons/gnd_weather/RainVolume.gd")
const PROBE_BUTTON_TEXT := "Weather Probes"
const PROBE_COLUMNS := 3
const PROBE_ROWS := 3
const PROBE_DEPTH_SLICES := 2
const PROBE_NEAR_DEPTH := 2.5
const PROBE_FAR_DEPTH := 8.0
const PROBE_FIELD_SCALE := 1.0
const PROBE_RADIUS := 4.0
const PROBE_HIGH_COLOR := Color(0.25, 0.78, 1.0, 0.92)
const PROBE_LOW_COLOR := Color(1.0, 0.45, 0.18, 0.92)

var _rain_volume_gizmo_plugin: RainVolumeGizmoPlugin
var _weather_probes_button: Button


func _enter_tree() -> void:
    _rain_volume_gizmo_plugin = RAIN_VOLUME_GIZMO_PLUGIN_SCRIPT.new()
    _rain_volume_gizmo_plugin.undo_redo = get_undo_redo()
    add_node_3d_gizmo_plugin(_rain_volume_gizmo_plugin)
    _weather_probes_button = Button.new()
    _weather_probes_button.text = PROBE_BUTTON_TEXT
    _weather_probes_button.toggle_mode = true
    _weather_probes_button.toggled.connect(_on_weather_probes_toggled)
    add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _weather_probes_button)
    set_force_draw_over_forwarding_enabled()
    set_process(true)


func _exit_tree() -> void:
    if _weather_probes_button != null:
        remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _weather_probes_button)
        _weather_probes_button.queue_free()
        _weather_probes_button = null
    if _rain_volume_gizmo_plugin != null:
        remove_node_3d_gizmo_plugin(_rain_volume_gizmo_plugin)
        _rain_volume_gizmo_plugin = null


func _process(_delta: float) -> void:
    if _weather_probes_button != null and _weather_probes_button.button_pressed:
        update_overlays()


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
    if _weather_probes_button == null or not _weather_probes_button.button_pressed:
        return

    var camera := _get_editor_camera()
    if camera == null:
        return

    var scene_root := get_editor_interface().get_edited_scene_root()
    if scene_root == null:
        return

    var rain_volumes := _collect_rain_volumes(scene_root)
    if rain_volumes.is_empty():
        return

    var probe_positions := WeatherServer.get_visible_rain_probe_positions(
        camera.global_transform,
        camera,
        PROBE_COLUMNS,
        PROBE_ROWS,
        PROBE_DEPTH_SLICES,
        PROBE_NEAR_DEPTH,
        PROBE_FAR_DEPTH,
        PROBE_FIELD_SCALE
    )
    var viewport_rect := overlay.get_rect()
    for probe_position in probe_positions:
        if camera.is_position_behind(probe_position):
            continue

        var screen_position := camera.unproject_position(probe_position)
        if not viewport_rect.has_point(screen_position):
            continue

        var strength := WeatherServer.get_rain_participation_strength_for_volumes(
            rain_volumes,
            probe_position,
            1.0
        )
        var probe_color := PROBE_LOW_COLOR.lerp(PROBE_HIGH_COLOR, clampf(strength, 0.0, 1.0))
        overlay.draw_circle(screen_position, PROBE_RADIUS, probe_color)
        overlay.draw_arc(screen_position, PROBE_RADIUS + 1.5, 0.0, TAU, 20, Color(probe_color.r, probe_color.g, probe_color.b, 0.95), 1.5, true)


func _on_weather_probes_toggled(_enabled: bool) -> void:
    update_overlays()


func _get_editor_camera() -> Camera3D:
    var editor_viewport := get_editor_interface().get_editor_viewport_3d(0)
    if editor_viewport == null:
        return null
    return editor_viewport.get_camera_3d()


func _collect_rain_volumes(root: Node) -> Array:
    var rain_volumes: Array = []
    if root == null:
        return rain_volumes

    for child in root.find_children("*", "VisualInstance3D", true, false):
        if child is RainVolume or child.get_script() == RAIN_VOLUME_SCRIPT:
            rain_volumes.append(child)
    return rain_volumes
