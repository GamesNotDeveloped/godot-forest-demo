extends CanvasLayer

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
const GND_WIND_STRENGTH_SETTING := "shader_globals/gnd_wind_strength/value"
const SGT_WIND_DIRECTION_SETTING := "shader_globals/sgt_wind_direction/value"
const SGT_WIND_STRENGTH_SETTING := "shader_globals/sgt_wind_strength/value"

var _weather: WeatherNode
var _skydome: Skydome

var _wind_value_label: Label
var _rain_value_label: Label
var _time_value_label: Label
var _wind_strength_slider: HSlider
var _wind_direction_button: OptionButton
var _rain_slider: HSlider
var _time_slider: HSlider
var _time_slider_dragging := false


func _ready() -> void:
	layer = 97
	_build_overlay()
	_weather = _find_weather()
	_skydome = _find_skydome()
	if _skydome != null and not _skydome.time_changed.is_connected(_on_skydome_time_changed):
		_skydome.time_changed.connect(_on_skydome_time_changed)
	call_deferred("_sync_with_scene")
	set_process(true)


func _process(_delta: float) -> void:
	if _skydome != null and not _time_slider_dragging:
		_sync_time_control(_skydome.time_of_day)


func _build_overlay() -> void:
	var root := Control.new()
	root.name = "WeatherControlsRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)

	var panel := PanelContainer.new()
	panel.name = "WeatherPanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -430.0
	panel.offset_right = 430.0
	panel.offset_top = 14.0
	panel.offset_bottom = 136.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	root.add_child(panel)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	row.add_child(_create_title_label("Weather"))

	_wind_strength_slider = _create_slider(0.0, 1.0, 0.01, 170.0)
	_wind_strength_slider.value_changed.connect(_on_wind_strength_changed)
	_wind_value_label = _create_value_label("0%")
	row.add_child(_create_control_group("Wind", _wind_strength_slider, _wind_value_label))

	_wind_direction_button = OptionButton.new()
	_wind_direction_button.focus_mode = Control.FOCUS_NONE
	_wind_direction_button.custom_minimum_size = Vector2(86.0, 28.0)
	_wind_direction_button.item_selected.connect(_on_wind_direction_selected)
	for option in WIND_DIRECTION_OPTIONS:
		_wind_direction_button.add_item(option["label"])
	row.add_child(_create_inline_group("Dir", _wind_direction_button))

	_rain_slider = _create_slider(0.0, 1.0, 0.01, 170.0)
	_rain_slider.value_changed.connect(_on_rain_changed)
	_rain_value_label = _create_value_label("0%")
	row.add_child(_create_control_group("Rain", _rain_slider, _rain_value_label))

	_time_slider = _create_slider(0.0, 23.99, 0.01, 210.0)
	_time_slider.value_changed.connect(_on_time_changed)
	_time_slider.drag_started.connect(_on_time_drag_started)
	_time_slider.drag_ended.connect(_on_time_drag_ended)
	_time_value_label = _create_value_label("12:00")
	row.add_child(_create_control_group("Time", _time_slider, _time_value_label))


func _create_title_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.93, 0.94, 0.9, 0.92))
	return label


func _create_slider(min_value: float, max_value: float, step: float, width: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(width, 24.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider


func _create_value_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(56.0, 0.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_color", Color(0.86, 0.89, 0.85, 0.88))
	label.add_theme_font_size_override("font_size", 13)
	return label


func _create_control_group(title: String, control: Control, value_label: Label) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var header := Label.new()
	header.text = title
	header.add_theme_color_override("font_color", Color(0.72, 0.76, 0.72, 0.9))
	header.add_theme_font_size_override("font_size", 12)
	box.add_child(header)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.add_child(control)
	row.add_child(value_label)
	box.add_child(row)
	return box


func _create_inline_group(title: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var header := Label.new()
	header.text = title
	header.add_theme_color_override("font_color", Color(0.72, 0.76, 0.72, 0.9))
	header.add_theme_font_size_override("font_size", 12)
	box.add_child(header)
	box.add_child(control)
	return box


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


func _sync_weather_controls() -> void:
	var wind_strength := _get_wind_strength_ratio()
	_wind_strength_slider.set_value_no_signal(wind_strength)
	_wind_value_label.text = "%d%%" % int(round(wind_strength * 100.0))
	_wind_direction_button.select(_find_closest_direction_index(_get_current_wind_direction()))

	if _weather != null:
		_rain_slider.set_value_no_signal(_weather.precipitation_intensity)
		_rain_value_label.text = "%d%%" % int(round(_weather.precipitation_intensity * 100.0))


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


func _on_time_changed(value: float) -> void:
	_time_value_label.text = _format_time_label(value)
	if _skydome != null:
		_skydome.time_of_day = value


func _on_time_drag_started() -> void:
	_time_slider_dragging = true


func _on_time_drag_ended(_value_changed: bool) -> void:
	_time_slider_dragging = false


func _on_skydome_time_changed(_day: int, time: float) -> void:
	if not _time_slider_dragging:
		_sync_time_control(time)


func _apply_wind_controls(strength_ratio: float, direction: Vector2) -> void:
	var normalized_direction := direction.normalized()
	var gnd_speed := lerpf(0.15, 3.0, strength_ratio)
	var gnd_strength := lerpf(0.4, 5.0, strength_ratio)
	var sgt_strength := lerpf(0.04, 0.42, strength_ratio)
	var sgt_direction := Vector3(normalized_direction.x, 0.0, normalized_direction.y)
	var time_now := Time.get_ticks_msec() * 0.001

	_set_runtime_wind_value(GND_WIND_DIRECTION_SETTING, normalized_direction, "gnd_wind_direction")
	_set_runtime_wind_value(GND_WIND_SPEED_SETTING, gnd_speed, "gnd_wind_speed")
	_set_runtime_wind_value(GND_WIND_STRENGTH_SETTING, gnd_strength, "gnd_wind_strength")
	_set_runtime_wind_value(SGT_WIND_DIRECTION_SETTING, sgt_direction, "sgt_wind_direction")
	_set_runtime_wind_value(SGT_WIND_STRENGTH_SETTING, sgt_strength, "sgt_wind_strength")
	RenderingServer.global_shader_parameter_set("sgt_wind_movement", Vector3(time_now * gnd_speed * 0.08, time_now * (0.85 + strength_ratio), 0.0))

	if _weather != null:
		_weather.apply_now()
	if _skydome != null:
		_skydome.apply_now()


func _set_runtime_wind_value(setting_path: String, setting_value: Variant, shader_global_name: String) -> void:
	ProjectSettings.set_setting(setting_path, setting_value)
	RenderingServer.global_shader_parameter_set(shader_global_name, setting_value)


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
