extends CanvasLayer

signal world_time_scale_changed(scale: float)

const WIND_DIRECTION_OPTIONS := [
    {"label": "N", "value": Vector2(0.0, -1.0)},
    {"label": "NE", "value": Vector2(0.70710677, -0.70710677)},
    {"label": "E", "value": Vector2(1.0, 0.0)},
    {"label": "SE", "value": Vector2(0.70710677, 0.70710677)},
    {"label": "S", "value": Vector2(0.0, 1.0)},
    {"label": "SW", "value": Vector2(-0.70710677, 0.70710677)},
    {"label": "W", "value": Vector2(-1.0, 0.0)},
    {"label": "NW", "value": Vector2(-0.70710677, -0.70710677)},
]
const GND_WIND_DIRECTION_SETTING := "shader_globals/gnd_wind_direction/value"
const GND_WIND_SPEED_SETTING := "shader_globals/gnd_wind_speed/value"
const STORM_RAIN_START_RATIO := 0.4
const SKYDOME_FOG_RAIN_START_RATIO := 0.6
const SKYDOME_FOG_DENSITY_MAX := 0.4
const RAINBOW_INTENSITY_MAX := 0.12
const RAINBOW_RAIN_START_RATIO := 0.2
const RAINBOW_RAIN_END_RATIO := 0.5
const RAINBOW_CLOUD_FADE_START_RATIO := 0.2
const RAINBOW_CLOUD_FADE_END_RATIO := 0.5

var _weather: WeatherNode
var _skydome: Skydome

@onready var _weather_panel: PanelContainer = $WeatherControlsRoot/WeatherPanel
@onready var _wind_value_label: Label = $WeatherControlsRoot/WeatherPanel/Row/WindGroup/Row/WindValueLabel
@onready var _rain_value_label: Label = $WeatherControlsRoot/WeatherPanel/Row/RainGroup/Row/RainValueLabel
@onready var _cloud_value_label: Label = $WeatherControlsRoot/WeatherPanel/Row/CloudGroup/Row/CloudValueLabel
@onready var _time_value_label: Label = $WeatherControlsRoot/WeatherPanel/Row/TimeGroup/Row/TimeValueLabel
@onready var _time_scale_value_label: Label = $WeatherControlsRoot/WeatherPanel/Row/TimeScaleGroup/Row/TimeScaleValueLabel
@onready var _wind_strength_slider: HSlider = $WeatherControlsRoot/WeatherPanel/Row/WindGroup/Row/WindSlider
@onready var _wind_direction_button: OptionButton = $WeatherControlsRoot/WeatherPanel/Row/WindDirectionGroup/WindDirectionButton
@onready var _rain_slider: HSlider = $WeatherControlsRoot/WeatherPanel/Row/RainGroup/Row/RainSlider
@onready var _cloud_slider: HSlider = $WeatherControlsRoot/WeatherPanel/Row/CloudGroup/Row/CloudSlider
@onready var _time_slider: HSlider = $WeatherControlsRoot/WeatherPanel/Row/TimeGroup/Row/TimeSlider
@onready var _time_scale_slider: HSlider = $WeatherControlsRoot/WeatherPanel/Row/TimeScaleGroup/Row/TimeScaleSlider
var _time_slider_dragging := false


func _ready() -> void:
    layer = 97
    _weather_panel.add_theme_stylebox_override("panel", _make_panel_style())
    _wind_strength_slider.value_changed.connect(_on_wind_strength_changed)
    _wind_direction_button.item_selected.connect(_on_wind_direction_selected)
    _rain_slider.value_changed.connect(_on_rain_changed)
    _cloud_slider.value_changed.connect(_on_cloud_density_changed)
    _time_slider.value_changed.connect(_on_time_changed)
    _time_slider.drag_started.connect(_on_time_drag_started)
    _time_slider.drag_ended.connect(_on_time_drag_ended)
    _time_scale_slider.value_changed.connect(_on_time_scale_changed)
    for option in WIND_DIRECTION_OPTIONS:
        _wind_direction_button.add_item(option["label"])
    _weather = _find_weather()
    _skydome = _find_skydome()
    if _skydome != null and not _skydome.time_changed.is_connected(_on_skydome_time_changed):
        _skydome.time_changed.connect(_on_skydome_time_changed)
    call_deferred("_sync_with_scene")
    set_process(true)


func _process(_delta: float) -> void:
    if _skydome != null and not _time_slider_dragging:
        _sync_time_control(_skydome.time_of_day)


func _find_weather() -> WeatherNode:
    var host := get_parent()
    if host == null:
        return null
    return host.get_node_or_null("Weather") as WeatherNode


func _find_skydome() -> Skydome:
    var host := get_parent()
    if host == null:
        return null
    return host.get_node_or_null("Skydome") as Skydome


func _sync_with_scene() -> void:
    _sync_weather_controls()
    if _skydome != null:
        _sync_time_control(_skydome.time_of_day)
    _sync_time_scale_control(_get_initial_time_scale())


func _sync_weather_controls() -> void:
    var wind_strength := _get_wind_strength_ratio()
    _wind_strength_slider.set_value_no_signal(wind_strength)
    _wind_value_label.text = "%d%%" % int(round(wind_strength * 100.0))
    _wind_direction_button.select(_find_closest_direction_index(_get_current_wind_direction()))

    if _weather != null:
        _rain_slider.set_value_no_signal(_weather.precipitation_intensity)
        _rain_value_label.text = "%d%%" % int(round(_weather.precipitation_intensity * 100.0))
        _cloud_slider.set_value_no_signal(_weather.cloud_density)
        _cloud_value_label.text = "%d%%" % int(round(_weather.cloud_density * 100.0))
    _sync_rainbow_intensity()


func _sync_time_control(time_of_day: float) -> void:
    _time_slider.set_value_no_signal(time_of_day)
    _time_value_label.text = _format_time_label(time_of_day)


func _on_wind_strength_changed(value: float) -> void:
    _wind_value_label.text = "%d%%" % int(round(value * 100.0))
    _apply_wind_controls(value, _get_direction_from_index(_wind_direction_button.selected))


func _on_wind_direction_selected(index: int) -> void:
    _apply_wind_controls(_wind_strength_slider.value, _get_direction_from_index(index))


func _on_rain_changed(value: float) -> void:
    _rain_value_label.text = "%d%%" % int(round(value * 100.0))
    if _weather != null:
        _weather.set_precipitation_intensity(value)
        _weather.set_cloud_overcast_intensity(value)
        _weather.set_storm_intensity(_get_storm_intensity_from_rain(value))
        _weather.set_storm_fog_intensity(_get_skydome_fog_density_from_rain(value))
    _sync_rainbow_intensity()


func _on_cloud_density_changed(value: float) -> void:
    _cloud_value_label.text = "%d%%" % int(round(value * 100.0))
    if _weather != null:
        _weather.set_cloud_density(value)
    _sync_rainbow_intensity()


func _on_time_changed(value: float) -> void:
    _time_value_label.text = _format_time_label(value)
    if _skydome != null:
        _skydome.time_of_day = value


func _on_time_scale_changed(value: float) -> void:
    _sync_time_scale_control(value)
    world_time_scale_changed.emit(value)


func _on_time_drag_started() -> void:
    _time_slider_dragging = true


func _on_time_drag_ended(_value_changed: bool) -> void:
    _time_slider_dragging = false


func _on_skydome_time_changed(_day: int, time: float) -> void:
    if not _time_slider_dragging:
        _sync_time_control(time)


func _sync_time_scale_control(value: float) -> void:
    if _time_scale_slider != null:
        _time_scale_slider.set_value_no_signal(value)
    if _time_scale_value_label != null:
        _time_scale_value_label.text = "%dx" % value


func _apply_wind_controls(strength_ratio: float, direction: Vector2) -> void:
    if _weather != null:
        _weather.apply_wind_controls(strength_ratio, direction)


func _get_initial_time_scale() -> float:
    var host := get_parent()
    if host != null and host.has_method("get_world_time_scale"):
        return float(host.get_world_time_scale())
    return 1.0


func _get_current_wind_direction() -> Vector2:
    if ProjectSettings.has_setting(GND_WIND_DIRECTION_SETTING):
        var direction := ProjectSettings.get_setting(GND_WIND_DIRECTION_SETTING) as Vector2
        if direction.length_squared() > 0.0001:
            return direction.normalized()
    return Vector2(1.0, 0.0)


func _get_wind_strength_ratio() -> float:
    if ProjectSettings.has_setting(GND_WIND_SPEED_SETTING):
        var speed := float(ProjectSettings.get_setting(GND_WIND_SPEED_SETTING))
        return clampf(inverse_lerp(0.15, 3.0, speed), 0.0, 1.0)
    return 0.3


func _find_closest_direction_index(direction: Vector2) -> int:
    var best_index := 0
    var best_dot := -INF
    var normalized_direction := direction.normalized()
    for index in range(WIND_DIRECTION_OPTIONS.size()):
        var candidate := WIND_DIRECTION_OPTIONS[index]["value"] as Vector2
        var score := normalized_direction.dot(candidate.normalized())
        if score > best_dot:
            best_dot = score
            best_index = index
    return best_index


func _get_direction_from_index(index: int) -> Vector2:
    var safe_index := clampi(index, 0, WIND_DIRECTION_OPTIONS.size() - 1)
    return WIND_DIRECTION_OPTIONS[safe_index]["value"] as Vector2


func _format_time_label(value: float) -> String:
    var wrapped := wrapf(value, 0.0, 24.0)
    var hours := int(floor(wrapped))
    var minutes := int(round((wrapped - float(hours)) * 60.0))
    if minutes >= 60:
        hours = (hours + 1) % 24
        minutes = 0
    return "%02d:%02d" % [hours, minutes]


func _get_storm_intensity_from_rain(rain_ratio: float) -> float:
    var clamped_rain := clampf(rain_ratio, 0.0, 1.0)
    return clampf(inverse_lerp(STORM_RAIN_START_RATIO, 1.0, clamped_rain), 0.0, 1.0)


func _get_skydome_fog_density_from_rain(rain_ratio: float) -> float:
    var clamped_rain := clampf(rain_ratio, 0.0, 1.0)
    return clampf(
        inverse_lerp(SKYDOME_FOG_RAIN_START_RATIO, 1.0, clamped_rain) * SKYDOME_FOG_DENSITY_MAX,
        0.0,
        SKYDOME_FOG_DENSITY_MAX
    )


func _sync_rainbow_intensity() -> void:
    if _skydome == null:
        return

    var rain_ratio := _rain_slider.value
    if _weather != null:
        rain_ratio = _weather.precipitation_intensity

    var cloud_ratio := _cloud_slider.value
    if _weather != null:
        cloud_ratio = _weather.cloud_density

    _skydome.rainbow_intensity = _get_rainbow_intensity_from_weather(rain_ratio, cloud_ratio)


func _get_rainbow_intensity_from_weather(rain_ratio: float, cloud_ratio: float) -> float:
    var clamped_rain := clampf(rain_ratio, 0.0, 1.0)
    var clamped_clouds := clampf(cloud_ratio, 0.0, 1.0)

    var rain_factor := _smoothstep(RAINBOW_RAIN_START_RATIO, RAINBOW_RAIN_END_RATIO, clamped_rain)
    var cloud_factor := 1.0 - _smoothstep(
        RAINBOW_CLOUD_FADE_START_RATIO,
        RAINBOW_CLOUD_FADE_END_RATIO,
        clamped_clouds
    )

    return RAINBOW_INTENSITY_MAX * rain_factor * clampf(cloud_factor, 0.0, 1.0)


func _smoothstep(edge0: float, edge1: float, x: float) -> float:
    if is_equal_approx(edge0, edge1):
        return 1.0 if x >= edge1 else 0.0
    var t := clampf(inverse_lerp(edge0, edge1, x), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


func _make_panel_style() -> StyleBoxFlat:
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color(0.05, 0.055, 0.06, 0.74)
    panel_style.corner_radius_top_left = 14
    panel_style.corner_radius_top_right = 14
    panel_style.corner_radius_bottom_left = 14
    panel_style.corner_radius_bottom_right = 14
    panel_style.border_width_left = 1
    panel_style.border_width_top = 1
    panel_style.border_width_right = 1
    panel_style.border_width_bottom = 1
    panel_style.border_color = Color(0.7, 0.74, 0.68, 0.18)
    panel_style.content_margin_left = 12.0
    panel_style.content_margin_top = 8.0
    panel_style.content_margin_right = 12.0
    panel_style.content_margin_bottom = 8.0
    return panel_style
