@tool
extends EditorPlugin

const RAIN_VOLUME_GIZMO_PLUGIN_SCRIPT := preload("res://addons/gnd_weather/RainVolumeGizmoPlugin.gd")

var _rain_volume_gizmo_plugin: RainVolumeGizmoPlugin


func _enter_tree() -> void:
    _rain_volume_gizmo_plugin = RAIN_VOLUME_GIZMO_PLUGIN_SCRIPT.new()
    _rain_volume_gizmo_plugin.undo_redo = get_undo_redo()
    add_node_3d_gizmo_plugin(_rain_volume_gizmo_plugin)


func _exit_tree() -> void:
    if _rain_volume_gizmo_plugin != null:
        remove_node_3d_gizmo_plugin(_rain_volume_gizmo_plugin)
        _rain_volume_gizmo_plugin = null
