extends CanvasLayer

var _buttons: Dictionary = {}
var _active_label: Label
var _buttons_row: HBoxContainer
var _manager: QualityProfilesManager


func _ready() -> void:
    layer = 96
    _build_overlay()
    _manager = _find_manager()
    _rebuild_profile_buttons()
    if _manager != null:
        _manager.profile_changed.connect(_on_manager_profile_changed)
    call_deferred("_sync_with_manager")


func _build_overlay() -> void:
    var root := Control.new()
    root.name = "QualityProfilesRoot"
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_PASS
    add_child(root)

    var panel := PanelContainer.new()
    panel.name = "Panel"
    panel.anchor_left = 0.5
    panel.anchor_right = 0.5
    panel.anchor_top = 1.0
    panel.anchor_bottom = 1.0
    panel.offset_left = -310.0
    panel.offset_top = -58.0
    panel.offset_right = 310.0
    panel.offset_bottom = -14.0
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    root.add_child(panel)

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
    panel.add_theme_stylebox_override("panel", panel_style)

    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", 8)
    panel.add_child(row)

    _active_label = Label.new()
    _active_label.text = "Quality"
    _active_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _active_label.add_theme_font_size_override("font_size", 15)
    _active_label.add_theme_color_override("font_color", Color(0.93, 0.94, 0.9, 0.92))
    row.add_child(_active_label)

    _buttons_row = HBoxContainer.new()
    _buttons_row.add_theme_constant_override("separation", 8)
    row.add_child(_buttons_row)


func _find_manager() -> QualityProfilesManager:
    var host := get_parent()
    if host == null:
        return null
    return host.get_node_or_null("QualityProfilesManager") as QualityProfilesManager


func _rebuild_profile_buttons() -> void:
    _buttons.clear()
    if _buttons_row == null:
        return

    for child in _buttons_row.get_children():
        child.queue_free()

    if _manager == null:
        return

    for profile in _manager.get_profiles():
        if profile == null:
            continue

        var button := Button.new()
        button.text = _get_profile_label(profile)
        button.custom_minimum_size = Vector2(88.0, 28.0)
        button.focus_mode = Control.FOCUS_NONE
        button.add_theme_font_size_override("font_size", 14)
        button.pressed.connect(_on_profile_button_pressed.bind(profile.id))
        _buttons_row.add_child(button)
        _buttons[profile.id] = button


func _sync_with_manager() -> void:
    if _manager == null:
        _set_active_profile(null)
        return

    _set_active_profile(_manager.get_selected_profile())


func _on_profile_button_pressed(profile_id: StringName) -> void:
    if _manager != null:
        _manager.select_profile_by_id(profile_id)


func _on_manager_profile_changed() -> void:
    _sync_with_manager()


func _set_active_profile(profile: QualityProfile) -> void:
    var active_profile_id: StringName = &""
    if profile == null:
        _active_label.text = "Quality"
    else:
        active_profile_id = profile.id
        _active_label.text = "Quality: %s" % _get_profile_label(profile)

    for candidate_id in _buttons.keys():
        var button := _buttons.get(candidate_id) as Button
        if button == null:
            continue
        var is_active: bool = candidate_id == active_profile_id
        button.add_theme_stylebox_override("normal", _make_button_style(is_active, false))
        button.add_theme_stylebox_override("hover", _make_button_style(is_active, true))
        button.add_theme_stylebox_override("pressed", _make_button_style(is_active, true))
        button.add_theme_color_override("font_color", Color(0.96, 0.97, 0.93, 0.96) if is_active else Color(0.88, 0.89, 0.85, 0.92))


func _get_profile_label(profile: QualityProfile) -> String:
    if profile.name.is_empty():
        return String(profile.id)
    return profile.name


func _make_button_style(is_active: bool, is_hovered: bool) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.corner_radius_top_left = 9
    style.corner_radius_top_right = 9
    style.corner_radius_bottom_left = 9
    style.corner_radius_bottom_right = 9
    style.content_margin_left = 10.0
    style.content_margin_top = 4.0
    style.content_margin_right = 10.0
    style.content_margin_bottom = 4.0
    style.border_width_left = 1
    style.border_width_top = 1
    style.border_width_right = 1
    style.border_width_bottom = 1

    if is_active:
        style.bg_color = Color(0.29, 0.39, 0.27, 0.92) if is_hovered else Color(0.23, 0.33, 0.22, 0.9)
        style.border_color = Color(0.72, 0.82, 0.68, 0.5)
    else:
        style.bg_color = Color(0.18, 0.19, 0.2, 0.88) if is_hovered else Color(0.12, 0.125, 0.13, 0.84)
        style.border_color = Color(0.72, 0.75, 0.7, 0.12)

    return style
