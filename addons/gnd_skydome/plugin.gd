@tool
extends EditorPlugin

const WIND_DIRECTION_SETTING := "shader_globals/gnd_wind_direction"
const WIND_SPEED_SETTING := "shader_globals/gnd_wind_speed"


func _enter_tree() -> void:
    var dirty := false

    if not ProjectSettings.has_setting(WIND_DIRECTION_SETTING):
        ProjectSettings.set_setting(WIND_DIRECTION_SETTING, {
            "type": "vec2",
            "value": Vector2(0.8, 0.3),
        })
        dirty = true

    if not ProjectSettings.has_setting(WIND_SPEED_SETTING):
        ProjectSettings.set_setting(WIND_SPEED_SETTING, {
            "type": "float",
            "value": 1.0,
        })
        dirty = true

    if dirty:
        ProjectSettings.save()
