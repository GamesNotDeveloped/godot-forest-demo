@tool
extends EditorPlugin

func _enter_tree() -> void:
    WeatherServer.ensure_wind_project_settings()
