@tool
class_name GndMaskPainterPanel
extends VBoxContainer

signal create_mask_requested
signal paint_toggled(enabled: bool)

const RESOLUTION_PRESETS := [256, 512, 1024]

var paint_toggle: CheckButton
var mode_option: OptionButton
var brush_size: SpinBox
var brush_hardness: SpinBox
var brush_opacity: SpinBox
var resolution_option: OptionButton
var create_button: Button
var status_label: Label
var section_label: Label


func _init() -> void:
    name = "MaskPainterPanel"
    _build()


func _build() -> void:
    section_label = Label.new()
    section_label.text = "Mask"
    add_child(section_label)

    var actions_row := HBoxContainer.new()
    add_child(actions_row)

    paint_toggle = CheckButton.new()
    paint_toggle.text = "Paint Mask"
    paint_toggle.toggled.connect(func(enabled: bool) -> void:
        paint_toggled.emit(enabled)
    )
    actions_row.add_child(paint_toggle)

    mode_option = OptionButton.new()
    mode_option.add_item("Paint")
    mode_option.add_item("Erase")
    actions_row.add_child(mode_option)

    brush_size = SpinBox.new()
    brush_size.min_value = 0.1
    brush_size.max_value = 128.0
    brush_size.step = 0.1
    brush_size.value = 2.0
    brush_size.custom_minimum_size = Vector2(90.0, 0.0)
    actions_row.add_child(brush_size)

    brush_hardness = SpinBox.new()
    brush_hardness.min_value = 0.0
    brush_hardness.max_value = 1.0
    brush_hardness.step = 0.01
    brush_hardness.value = 0.35
    brush_hardness.custom_minimum_size = Vector2(80.0, 0.0)
    brush_hardness.tooltip_text = "Brush hardness"
    actions_row.add_child(brush_hardness)

    brush_opacity = SpinBox.new()
    brush_opacity.min_value = 0.0
    brush_opacity.max_value = 1.0
    brush_opacity.step = 0.01
    brush_opacity.value = 1.0
    brush_opacity.custom_minimum_size = Vector2(80.0, 0.0)
    brush_opacity.tooltip_text = "Brush opacity"
    actions_row.add_child(brush_opacity)

    var create_row := HBoxContainer.new()
    add_child(create_row)

    resolution_option = OptionButton.new()
    for resolution in RESOLUTION_PRESETS:
        resolution_option.add_item("%sx%s" % [resolution, resolution], resolution)
    resolution_option.selected = 1
    create_row.add_child(resolution_option)

    create_button = Button.new()
    create_button.text = "Create Mask PNG"
    create_button.pressed.connect(func() -> void:
        create_mask_requested.emit()
    )
    create_row.add_child(create_button)

    status_label = Label.new()
    status_label.text = "Select a supported node to edit its mask."
    add_child(status_label)


func set_mask_label(mask_name: String) -> void:
    var normalized := mask_name.strip_edges()
    if normalized.is_empty():
        normalized = "Mask"
    section_label.text = normalized
    paint_toggle.text = "Paint %s" % normalized
    create_button.text = "Create %s PNG" % normalized


func set_controls_enabled(enabled: bool, busy: bool) -> void:
    var editable := enabled and not busy
    paint_toggle.disabled = not editable
    mode_option.disabled = not editable
    brush_size.editable = editable
    brush_hardness.editable = editable
    brush_opacity.editable = editable
    resolution_option.disabled = not editable
    create_button.disabled = not editable


func clear_target_state() -> void:
    paint_toggle.button_pressed = false


func is_paint_enabled() -> bool:
    return paint_toggle.button_pressed


func get_paint_value() -> float:
    return 1.0 if mode_option.selected == 0 else 0.0


func get_brush_size() -> float:
    return brush_size.value


func get_brush_hardness() -> float:
    return brush_hardness.value


func get_brush_opacity() -> float:
    return brush_opacity.value


func get_resolution() -> int:
    return resolution_option.get_selected_id()


func set_status(text: String) -> void:
    status_label.text = text
