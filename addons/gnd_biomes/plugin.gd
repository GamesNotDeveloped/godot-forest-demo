@tool
extends EditorPlugin

const BIOMES_SCRIPT := preload("res://addons/gnd_biomes/Biomes.gd")
const ENTRY_SCRIPT := preload("res://addons/gnd_biomes/BiomeScatterEntry.gd")
const AUTO_FOG_SCRIPT := preload("res://addons/gnd_biomes/AutoBiomesFog.gd")
const MASK_PAINTER_PANEL_SCRIPT := preload("res://addons/gnd_biomes/MaskPainterPanel.gd")
const TERRAIN_PATCH_SCRIPT := preload("res://scenery/TerrainPatch3D.gd")
const BIOMES_ICON := preload("res://icon.svg")
const PANEL_TITLE := "Biomes"
const BILLBOARD_PADDING := 1.15
const OVERWRITE_SKIP := 0
const OVERWRITE_OVERWRITE := 1
const RESOLUTION_PRESETS := [256, 512, 1024]

var _current_biomes: Biomes
var _current_paint_target: Node3D
var _panel: VBoxContainer
var _mask_panel: Control
var _billboard_separator: HSeparator
var _billboard_section: Label
var _billboard_row: HBoxContainer
var _billboard_resolution_option: OptionButton
var _billboard_output_dir_edit: LineEdit
var _billboard_output_dir_button: Button
var _generate_billboards_button: Button
var _status_label: Label
var _save_dialog: FileDialog
var _billboard_dir_dialog: FileDialog
var _overwrite_dialog: ConfirmationDialog
var _overwrite_mode_option: OptionButton
var _stroke_active := false
var _stroke_before_image: Image
var _stroke_working_image: Image
var _last_painted_pixel := Vector2i(-1, -1)
var _pending_mask_path := ""
var _hover_screen_position := Vector2.ZERO
var _hover_world_position: Variant = null
var _billboard_generation_running := false


func _enter_tree() -> void:
    add_custom_type("Biomes", "Node3D", BIOMES_SCRIPT, BIOMES_ICON)
    add_custom_type("BiomeScatterEntry", "Resource", ENTRY_SCRIPT, BIOMES_ICON)
    add_custom_type("AutoBiomesFog", "Node", AUTO_FOG_SCRIPT, BIOMES_ICON)
    _build_panel()
    _build_file_dialog()
    _build_overwrite_dialog()
    set_input_event_forwarding_always_enabled()
    set_force_draw_over_forwarding_enabled()


func _exit_tree() -> void:
    remove_custom_type("AutoBiomesFog")
    remove_custom_type("BiomeScatterEntry")
    remove_custom_type("Biomes")
    if _panel != null:
        remove_control_from_bottom_panel(_panel)
        _panel.queue_free()
    if _save_dialog != null:
        _save_dialog.queue_free()
    if _billboard_dir_dialog != null:
        _billboard_dir_dialog.queue_free()
    if _overwrite_dialog != null:
        _overwrite_dialog.queue_free()


func _handles(object: Object) -> bool:
    return object is Biomes or object.get_script() == TERRAIN_PATCH_SCRIPT


func _edit(object: Object) -> void:
    _current_biomes = object as Biomes
    _current_paint_target = object as Node3D
    _refresh_panel_state()


func _make_visible(visible: bool) -> void:
    if _panel != null:
        _panel.visible = visible and _current_paint_target != null


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
    if event is InputEventMouse:
        _hover_screen_position = event.position
        _hover_world_position = _intersect_mask_plane(camera, event.position) if _can_paint() else null
        update_overlays()

    if not _can_paint():
        return AFTER_GUI_INPUT_PASS

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            if _begin_stroke():
                _paint_at_screen_position(camera, event.position)
                return AFTER_GUI_INPUT_STOP
            return AFTER_GUI_INPUT_PASS

        if _stroke_active:
            _end_stroke()
            return AFTER_GUI_INPUT_STOP

    if event is InputEventMouseMotion and _stroke_active:
        _paint_at_screen_position(camera, event.position)
        return AFTER_GUI_INPUT_STOP

    return AFTER_GUI_INPUT_PASS


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
    if not _can_paint():
        return
    if _hover_world_position == null:
        return

    var local_position := _current_paint_target.to_local(_hover_world_position as Vector3)
    var uv := _current_paint_target.call("local_to_mask_uv", local_position) as Vector2
    if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
        return

    var color := Color(0.2, 1.0, 0.3, 0.9) if _mask_panel.mode_option.selected == 0 else Color(1.0, 0.25, 0.25, 0.9)
    var radius_px := maxf(_mask_panel.get_brush_size() * 8.0, 6.0)
    overlay.draw_arc(_hover_screen_position, radius_px, 0.0, TAU, 48, color, 2.0, true)
    overlay.draw_circle(_hover_screen_position, 2.5, color)


func _build_panel() -> void:
    _panel = VBoxContainer.new()
    _panel.name = PANEL_TITLE

    _mask_panel = MASK_PAINTER_PANEL_SCRIPT.new()
    _mask_panel.paint_toggled.connect(_on_paint_toggled)
    _mask_panel.create_mask_requested.connect(_on_create_mask_pressed)
    _panel.add_child(_mask_panel)

    _billboard_separator = HSeparator.new()
    _panel.add_child(_billboard_separator)

    _billboard_section = Label.new()
    _billboard_section.text = "Billboards"
    _panel.add_child(_billboard_section)

    _billboard_row = HBoxContainer.new()
    _panel.add_child(_billboard_row)

    _billboard_resolution_option = OptionButton.new()
    for resolution in RESOLUTION_PRESETS:
        _billboard_resolution_option.add_item("%sx%s" % [resolution, resolution], resolution)
    _billboard_resolution_option.selected = 1
    _billboard_row.add_child(_billboard_resolution_option)

    _billboard_output_dir_edit = LineEdit.new()
    _billboard_output_dir_edit.placeholder_text = "res://generated/biomes_billboards"
    _billboard_output_dir_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _billboard_output_dir_edit.text_submitted.connect(_on_billboard_output_dir_text_submitted)
    _billboard_output_dir_edit.focus_exited.connect(_on_billboard_output_dir_focus_exited)
    _billboard_row.add_child(_billboard_output_dir_edit)

    _billboard_output_dir_button = Button.new()
    _billboard_output_dir_button.text = "Choose Output Dir"
    _billboard_output_dir_button.pressed.connect(_on_choose_billboard_output_dir_pressed)
    _billboard_row.add_child(_billboard_output_dir_button)

    _generate_billboards_button = Button.new()
    _generate_billboards_button.text = "Generate Billboards"
    _generate_billboards_button.pressed.connect(_on_generate_billboards_pressed)
    _billboard_row.add_child(_generate_billboards_button)

    _status_label = _mask_panel.get("status_label")

    add_control_to_bottom_panel(_panel, PANEL_TITLE)
    _panel.visible = false


func _build_file_dialog() -> void:
    _save_dialog = FileDialog.new()
    _save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
    _save_dialog.access = FileDialog.ACCESS_RESOURCES
    _save_dialog.filters = PackedStringArray(["*.png ; PNG texture"])
    _save_dialog.file_selected.connect(_on_mask_file_selected)
    get_editor_interface().get_base_control().add_child(_save_dialog)

    _billboard_dir_dialog = FileDialog.new()
    _billboard_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
    _billboard_dir_dialog.access = FileDialog.ACCESS_RESOURCES
    _billboard_dir_dialog.dir_selected.connect(_on_billboard_output_dir_selected)
    get_editor_interface().get_base_control().add_child(_billboard_dir_dialog)


func _build_overwrite_dialog() -> void:
    _overwrite_dialog = ConfirmationDialog.new()
    _overwrite_dialog.title = "Generate Billboards"
    _overwrite_dialog.ok_button_text = "Generate"
    _overwrite_dialog.min_size = Vector2i(360, 0)
    _overwrite_dialog.confirmed.connect(_on_overwrite_dialog_confirmed)

    var container := VBoxContainer.new()
    container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _overwrite_dialog.add_child(container)

    var label := Label.new()
    label.text = "Choose what to do with entries that already have billboard output."
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.custom_minimum_size = Vector2(320.0, 0.0)
    container.add_child(label)

    _overwrite_mode_option = OptionButton.new()
    _overwrite_mode_option.fit_to_longest_item = false
    _overwrite_mode_option.add_item("Skip Existing", OVERWRITE_SKIP)
    _overwrite_mode_option.add_item("Overwrite Existing", OVERWRITE_OVERWRITE)
    _overwrite_mode_option.selected = 0
    container.add_child(_overwrite_mode_option)

    get_editor_interface().get_base_control().add_child(_overwrite_dialog)


func _refresh_panel_state() -> void:
    if _panel == null:
        return

    var has_target := _current_paint_target != null
    var has_biomes := _current_biomes != null
    _panel.visible = has_target
    if _mask_panel != null:
        _mask_panel.set_controls_enabled(has_target, _billboard_generation_running)
        _mask_panel.set_mask_label("Mask" if has_biomes else "Grass Mask")
    if _billboard_resolution_option != null:
        _billboard_resolution_option.disabled = not has_biomes or _billboard_generation_running
    if _billboard_output_dir_edit != null:
        _billboard_output_dir_edit.editable = has_biomes and not _billboard_generation_running
    if _billboard_output_dir_button != null:
        _billboard_output_dir_button.disabled = not has_biomes or _billboard_generation_running
    if _generate_billboards_button != null:
        _generate_billboards_button.disabled = not has_biomes or _billboard_generation_running

    if not has_target:
        _mask_panel.set_status("Select a Biomes or TerrainPatch3D node to edit its mask.")
        if _mask_panel != null:
            _mask_panel.clear_target_state()
        if _billboard_output_dir_edit != null:
            _billboard_output_dir_edit.text = ""
        _hover_world_position = null
        update_overlays()
        return

    if _billboard_separator != null:
        _billboard_separator.visible = has_biomes
    if _billboard_section != null:
        _billboard_section.visible = has_biomes
    if _billboard_row != null:
        _billboard_row.visible = has_biomes

    if _billboard_generation_running:
        return

    var path := _current_paint_target.call("get_mask_texture_path") as String
    if has_biomes:
        _billboard_output_dir_edit.text = _current_biomes.billboard_output_dir
    if path.is_empty():
        _mask_panel.set_status("No mask asset yet. Create one to enable 3D painting.")
    else:
        var channel: int = _current_biomes.mask_channel if has_biomes else int(_current_paint_target.get("grass_mask_channel"))
        _mask_panel.set_status("Painting %s on %s" % [_channel_name(channel), path])


func _can_paint() -> bool:
    if _current_paint_target == null:
        return false
    if _billboard_generation_running:
        return false
    if not _mask_panel.is_paint_enabled():
        return false
    if (_current_paint_target.call("get_mask_texture_path") as String).is_empty():
        return false
    return true


func _on_paint_toggled(enabled: bool) -> void:
    if not enabled:
        _hover_world_position = null
        if _stroke_active:
            _end_stroke()
    update_overlays()


func _begin_stroke() -> bool:
    if not _can_paint():
        return false

    _stroke_before_image = _current_paint_target.call("get_mask_image_copy")
    _stroke_working_image = _stroke_before_image.duplicate()
    _stroke_active = true
    _last_painted_pixel = Vector2i(-1, -1)
    return true


func _end_stroke() -> void:
    if not _stroke_active:
        return

    _stroke_active = false
    if _stroke_before_image == null or _stroke_working_image == null:
        return
    if _stroke_before_image.get_data() == _stroke_working_image.get_data():
        _current_paint_target.call("preview_mask_image", _stroke_before_image)
        return

    var undo_redo := get_undo_redo()
    undo_redo.create_action("Paint Biomes Mask")
    undo_redo.add_do_method(_current_paint_target, "set_mask_image", _stroke_working_image, true)
    undo_redo.add_undo_method(_current_paint_target, "set_mask_image", _stroke_before_image, true)
    undo_redo.commit_action()


func _paint_at_screen_position(camera: Camera3D, screen_position: Vector2) -> void:
    if _current_paint_target == null or _stroke_working_image == null:
        return

    var world_position: Variant = _intersect_mask_plane(camera, screen_position)
    if world_position == null:
        return

    var local_position := _current_paint_target.to_local(world_position as Vector3)
    var uv := _current_paint_target.call("local_to_mask_uv", local_position) as Vector2
    if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
        return

    var pixel := Vector2i(
        int(round(uv.x * float(_stroke_working_image.get_width() - 1))),
        int(round(uv.y * float(_stroke_working_image.get_height() - 1)))
    )
    if pixel == _last_painted_pixel:
        return

    _last_painted_pixel = pixel
    var value: float = _mask_panel.get_paint_value()
    if _current_paint_target.call(
        "paint_mask_circle_on_image",
        _stroke_working_image,
        local_position,
        _mask_panel.get_brush_size(),
        value,
        _mask_panel.get_brush_hardness(),
        _mask_panel.get_brush_opacity()
    ):
        _current_paint_target.call("preview_mask_image", _stroke_working_image)


func _intersect_mask_plane(camera: Camera3D, screen_position: Vector2) -> Variant:
    if _current_paint_target == null:
        return null

    var ray_origin := camera.project_ray_origin(screen_position)
    var ray_direction := camera.project_ray_normal(screen_position)
    var plane_origin := _current_paint_target.global_transform.origin
    var plane_normal := (_current_paint_target.global_transform.basis.orthonormalized() * Vector3.UP).normalized()
    var denominator := plane_normal.dot(ray_direction)
    if absf(denominator) < 0.0001:
        return null

    var distance := plane_normal.dot(plane_origin - ray_origin) / denominator
    if distance < 0.0:
        return null

    return ray_origin + ray_direction * distance


func _on_create_mask_pressed() -> void:
    if _current_paint_target == null:
        return
    _save_dialog.current_dir = "res://"
    _save_dialog.current_file = "biomes_mask.png"
    _save_dialog.popup_centered_ratio(0.6)


func _on_mask_file_selected(path: String) -> void:
    if _current_paint_target == null:
        return

    var resolution: int = _mask_panel.get_resolution()
    if _current_paint_target.call("create_mask_texture_file", path, resolution):
        _pending_mask_path = path
        _mask_panel.set_status("Importing mask %s" % path)
        _import_and_assign_mask.call_deferred(path)
    else:
        _mask_panel.set_status("Failed to create mask at %s" % path)


func _import_and_assign_mask(path: String) -> void:
    if _current_paint_target == null:
        return

    await _rescan_filesystem()

    var texture := ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
    if texture == null:
        _mask_panel.set_status("Mask saved, but import failed for %s" % path)
        return

    _current_paint_target.call("assign_mask_texture", texture, true)
    _pending_mask_path = ""
    _mask_panel.set_status("Created mask %s" % path)
    _refresh_panel_state()


func _on_generate_billboards_pressed() -> void:
    if _current_biomes == null or _billboard_generation_running:
        return
    _apply_billboard_output_dir_from_ui()
    _overwrite_mode_option.selected = 0
    _overwrite_dialog.popup_centered_clamped(Vector2i(360, 120))


func _on_choose_billboard_output_dir_pressed() -> void:
    if _current_biomes == null or _billboard_dir_dialog == null:
        return
    _billboard_dir_dialog.current_dir = _current_biomes.billboard_output_dir if not _current_biomes.billboard_output_dir.is_empty() else "res://"
    _billboard_dir_dialog.popup_centered_ratio(0.7)


func _on_billboard_output_dir_selected(path: String) -> void:
    if _current_biomes == null:
        return
    _set_billboard_output_dir(path)


func _on_billboard_output_dir_text_submitted(_text: String) -> void:
    _apply_billboard_output_dir_from_ui()


func _on_billboard_output_dir_focus_exited() -> void:
    _apply_billboard_output_dir_from_ui()


func _apply_billboard_output_dir_from_ui() -> void:
    if _current_biomes == null or _billboard_output_dir_edit == null:
        return
    _set_billboard_output_dir(_billboard_output_dir_edit.text)


func _set_billboard_output_dir(path: String) -> void:
    if _current_biomes == null:
        return
    var normalized := path.strip_edges()
    if normalized.is_empty():
        normalized = "res://generated/biomes_billboards"
    if not normalized.begins_with("res://"):
        normalized = "res://%s" % normalized.trim_prefix("/")
    normalized = normalized.rstrip("/")
    _current_biomes.billboard_output_dir = normalized
    if _billboard_output_dir_edit != null:
        _billboard_output_dir_edit.text = normalized


func _on_overwrite_dialog_confirmed() -> void:
    if _current_biomes == null or _billboard_generation_running:
        return
    var overwrite_mode := _overwrite_mode_option.get_selected_id()
    _generate_billboards_for_current_biomes.call_deferred(overwrite_mode)


func _generate_billboards_for_current_biomes(overwrite_mode: int) -> void:
    if _current_biomes == null:
        return

    var biomes := _current_biomes
    _billboard_generation_running = true
    _refresh_panel_state()
    _status_label.text = "Generating billboard assets for %s..." % biomes.name

    var generated := 0
    var skipped := 0
    var failed := 0
    var resolution := _billboard_resolution_option.get_selected_id()

    for index in range(biomes.entries.size()):
        var entry := biomes.entries[index]
        var result: Dictionary = await _generate_billboard_for_entry(biomes, entry, index, resolution, overwrite_mode)
        match String(result.get("status", "failed")):
            "generated":
                generated += 1
            "skipped":
                skipped += 1
            _:
                failed += 1

    await _rescan_filesystem()
    if is_instance_valid(biomes):
        biomes.regenerate()
    _billboard_generation_running = false
    _refresh_panel_state()
    _status_label.text = "Billboards: %s generated, %s skipped, %s failed." % [generated, skipped, failed]


func _generate_billboard_for_entry(biomes: Biomes, entry: BiomeScatterEntry, entry_index: int, resolution: int, overwrite_mode: int) -> Dictionary:
    if biomes == null or entry == null:
        return {"status": "failed"}

    var source := _instantiate_billboard_source(entry, entry_index)
    if source.is_empty():
        return {"status": "skipped"}

    var base_dir := "%s/%s/%s" % [
        _get_billboard_output_root(biomes),
        _sanitize_asset_name(biomes.name),
        "%02d_%s" % [entry_index, source["name"]]
    ]
    var png_path := "%s/billboard.png" % base_dir
    var material_path := "%s/billboard_material.tres" % base_dir
    var scene_path := "%s/billboard.tscn" % base_dir
    if _should_skip_billboard_generation(entry, png_path, material_path, scene_path, overwrite_mode):
        source["root"].free()
        return {"status": "skipped"}

    if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir)) != OK:
        source["root"].free()
        return {"status": "failed"}

    var render_result: Dictionary = await _render_billboard_image(source["root"], resolution)
    source["root"].free()
    if render_result.is_empty():
        return {"status": "failed"}

    var image := render_result["image"] as Image
    var quad_size := render_result["quad_size"] as Vector2
    if image == null or image.is_empty() or quad_size == Vector2.ZERO:
        return {"status": "failed"}

    if image.save_png(png_path) != OK:
        return {"status": "failed"}

    var texture := ImageTexture.create_from_image(image)
    if texture == null:
        return {"status": "failed"}

    var material := StandardMaterial3D.new()
    material.resource_name = "%s_billboard_material" % source["name"]
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.albedo_texture = texture
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    if ResourceSaver.save(material, material_path) != OK:
        return {"status": "failed"}
    var saved_material := ResourceLoader.load(material_path, "Material", ResourceLoader.CACHE_MODE_REPLACE) as Material
    if saved_material == null:
        return {"status": "failed"}

    var quad_mesh := QuadMesh.new()
    quad_mesh.size = quad_size
    quad_mesh.material = saved_material

    var root := Node3D.new()
    root.name = "%sBillboard" % source["name"].capitalize()

    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = "Billboard"
    mesh_instance.mesh = quad_mesh
    mesh_instance.position = Vector3(0.0, quad_size.y * 0.5, 0.0)
    root.add_child(mesh_instance)
    mesh_instance.owner = root

    var packed_scene := PackedScene.new()
    if packed_scene.pack(root) != OK:
        root.free()
        return {"status": "failed"}
    root.free()

    if ResourceSaver.save(packed_scene, scene_path) != OK:
        return {"status": "failed"}

    var saved_scene := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
    if saved_scene == null:
        return {"status": "failed"}

    entry.billboard_scene = saved_scene
    if entry.billboard_lod_distance <= 0.0:
        entry.billboard_lod_distance = 60.0
    return {"status": "generated"}


func _instantiate_billboard_source(entry: BiomeScatterEntry, entry_index: int) -> Dictionary:
    if entry.mesh_scene != null:
        var instance := entry.mesh_scene.instantiate()
        if instance != null:
            return {
                "root": instance,
                "name": _source_name_from_resource(entry.mesh_scene, "entry_%s" % entry_index)
            }

    if entry.mesh != null:
        var root := Node3D.new()
        var mesh_instance := MeshInstance3D.new()
        mesh_instance.mesh = entry.mesh
        root.add_child(mesh_instance)
        return {
            "root": root,
            "name": _source_name_from_resource(entry.mesh, "entry_%s_mesh" % entry_index)
        }

    return {}


func _should_skip_billboard_generation(entry: BiomeScatterEntry, png_path: String, material_path: String, scene_path: String, overwrite_mode: int) -> bool:
    if overwrite_mode == OVERWRITE_OVERWRITE:
        return false
    if entry.billboard_scene != null and _scene_has_mesh_instances(entry.billboard_scene):
        return true
    return FileAccess.file_exists(png_path) or FileAccess.file_exists(material_path) or FileAccess.file_exists(scene_path)


func _scene_has_mesh_instances(scene: PackedScene) -> bool:
    if scene == null:
        return false
    var instance := scene.instantiate()
    if instance == null:
        return false
    var has_mesh_instances := _node_has_mesh_instances(instance)
    instance.free()
    return has_mesh_instances


func _node_has_mesh_instances(node: Node) -> bool:
    if node is MeshInstance3D:
        return true
    for child in node.get_children():
        var child_node := child as Node
        if child_node == null:
            continue
        if _node_has_mesh_instances(child_node):
            return true
    return false


func _render_billboard_image(source_root: Node, resolution: int) -> Dictionary:
    var bounds := _compute_scene_bounds(source_root)
    if not bool(bounds.get("has_bounds", false)):
        return {}

    var aabb := bounds["aabb"] as AABB
    if aabb.size == Vector3.ZERO:
        return {}

    var quad_size := Vector2(maxf(aabb.size.x, 0.01), maxf(aabb.size.y, 0.01))
    var depth := maxf(aabb.size.z, 0.01)
    var focus := Vector3(0.0, quad_size.y * 0.5, 0.0)
    var offset := Vector3(
        -(aabb.position.x + aabb.size.x * 0.5),
        -aabb.position.y,
        -(aabb.position.z + aabb.size.z * 0.5)
    )

    var viewport := SubViewport.new()
    viewport.name = "__billboard_viewport"
    viewport.size = Vector2i(resolution, resolution)
    viewport.transparent_bg = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
    viewport.msaa_3d = Viewport.MSAA_4X
    viewport.use_hdr_2d = false
    viewport.own_world_3d = true
    add_child(viewport)

    var scene_root := Node3D.new()
    viewport.add_child(scene_root)

    var holder := Node3D.new()
    holder.position = offset
    scene_root.add_child(holder)
    holder.add_child(source_root)

    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(1.0, 1.0, 1.0, 1.0)
    environment.ambient_light_energy = 0.85

    var world_environment := WorldEnvironment.new()
    world_environment.environment = environment
    scene_root.add_child(world_environment)

    var key_light := DirectionalLight3D.new()
    key_light.light_energy = 1.35
    key_light.rotation_degrees = Vector3(-42.0, -25.0, 0.0)
    scene_root.add_child(key_light)

    var fill_light := DirectionalLight3D.new()
    fill_light.light_energy = 0.6
    fill_light.rotation_degrees = Vector3(-20.0, 150.0, 0.0)
    scene_root.add_child(fill_light)

    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.keep_aspect = Camera3D.KEEP_HEIGHT
    camera.size = maxf(quad_size.x, quad_size.y) * BILLBOARD_PADDING
    camera.near = 0.05
    camera.far = maxf(depth + quad_size.y + 20.0, 100.0)
    camera.position = Vector3(0.0, focus.y, depth + maxf(quad_size.x, quad_size.y) * 2.0 + 2.0)
    scene_root.add_child(camera)
    camera.current = true
    camera.look_at_from_position(camera.position, focus, Vector3.UP)

    await get_tree().process_frame
    await RenderingServer.frame_post_draw

    var image := viewport.get_texture().get_image()
    viewport.queue_free()
    if image == null or image.is_empty():
        return {}
    if image.is_compressed():
        image.decompress()
    if image.get_format() != Image.FORMAT_RGBA8:
        image.convert(Image.FORMAT_RGBA8)
    image.fix_alpha_edges()

    var alpha_rect := _find_image_alpha_rect(image)
    if alpha_rect.size.x <= 0 or alpha_rect.size.y <= 0:
        return {}
    var world_per_pixel := camera.size / float(resolution)
    var cropped_size := alpha_rect.size
    image = image.get_region(alpha_rect)
    return {
        "image": image,
        "quad_size": Vector2(
            maxf(float(cropped_size.x) * world_per_pixel, 0.01),
            maxf(float(cropped_size.y) * world_per_pixel, 0.01)
        )
    }


func _compute_scene_bounds(root: Node) -> Dictionary:
    var state := {
        "has_bounds": false,
        "min": Vector3.ZERO,
        "max": Vector3.ZERO
    }
    _append_scene_bounds(root, Transform3D.IDENTITY, state)
    if not state["has_bounds"]:
        return {"has_bounds": false}

    var min_point: Vector3 = state["min"]
    var max_point: Vector3 = state["max"]
    return {
        "has_bounds": true,
        "aabb": AABB(min_point, max_point - min_point)
    }


func _append_scene_bounds(node: Node, parent_transform: Transform3D, state: Dictionary) -> void:
    var local_transform := parent_transform
    var node_3d := node as Node3D
    if node_3d != null:
        local_transform = parent_transform * node_3d.transform

    var mesh_instance := node as MeshInstance3D
    if mesh_instance != null and mesh_instance.mesh != null:
        var mesh_aabb := mesh_instance.mesh.get_aabb()
        for corner in _aabb_corners(mesh_aabb):
            var point := local_transform * corner
            if not state["has_bounds"]:
                state["has_bounds"] = true
                state["min"] = point
                state["max"] = point
            else:
                state["min"] = Vector3(
                    minf(state["min"].x, point.x),
                    minf(state["min"].y, point.y),
                    minf(state["min"].z, point.z)
                )
                state["max"] = Vector3(
                    maxf(state["max"].x, point.x),
                    maxf(state["max"].y, point.y),
                    maxf(state["max"].z, point.z)
                )

    for child in node.get_children():
        var child_node := child as Node
        if child_node == null:
            continue
        _append_scene_bounds(child_node, local_transform, state)


func _aabb_corners(aabb: AABB) -> Array[Vector3]:
    var position := aabb.position
    var size := aabb.size
    return [
        position,
        position + Vector3(size.x, 0.0, 0.0),
        position + Vector3(0.0, size.y, 0.0),
        position + Vector3(0.0, 0.0, size.z),
        position + Vector3(size.x, size.y, 0.0),
        position + Vector3(size.x, 0.0, size.z),
        position + Vector3(0.0, size.y, size.z),
        position + size
    ]


func _find_image_alpha_rect(image: Image, alpha_threshold: float = 0.01) -> Rect2i:
    var width := image.get_width()
    var height := image.get_height()
    var min_x := width
    var min_y := height
    var max_x := -1
    var max_y := -1

    for y in range(height):
        for x in range(width):
            if image.get_pixel(x, y).a <= alpha_threshold:
                continue
            min_x = mini(min_x, x)
            min_y = mini(min_y, y)
            max_x = maxi(max_x, x)
            max_y = maxi(max_y, y)

    if max_x < min_x or max_y < min_y:
        return Rect2i()
    return Rect2i(min_x, min_y, (max_x - min_x) + 1, (max_y - min_y) + 1)


func _source_name_from_resource(resource: Resource, fallback: String) -> String:
    if resource == null:
        return _sanitize_asset_name(fallback)
    if not resource.resource_path.is_empty():
        return _sanitize_asset_name(resource.resource_path.get_file().get_basename())
    if not resource.resource_name.is_empty():
        return _sanitize_asset_name(resource.resource_name)
    return _sanitize_asset_name(fallback)


func _sanitize_asset_name(value: String) -> String:
    var result := ""
    for character in value.to_lower():
        var code := character.unicode_at(0)
        var is_lower := code >= 97 and code <= 122
        var is_digit := code >= 48 and code <= 57
        if is_lower or is_digit:
            result += character
        elif character == "_" or character == "-":
            result += character
        else:
            result += "_"

    result = result.strip_edges()
    while result.contains("__"):
        result = result.replace("__", "_")
    result = result.trim_prefix("_").trim_suffix("_")
    if result.is_empty():
        return "billboard"
    return result


func _get_billboard_output_root(biomes: Biomes) -> String:
    if biomes == null:
        return "res://generated/biomes_billboards"
    var root := biomes.billboard_output_dir.strip_edges()
    if root.is_empty():
        return "res://generated/biomes_billboards"
    return root.rstrip("/")


func _rescan_filesystem() -> void:
    var filesystem := get_editor_interface().get_resource_filesystem()
    filesystem.scan()
    await filesystem.filesystem_changed


func _channel_name(channel: int) -> String:
    match channel:
        Biomes.MaskChannel.RED:
            return "Red"
        Biomes.MaskChannel.GREEN:
            return "Green"
        Biomes.MaskChannel.BLUE:
            return "Blue"
        Biomes.MaskChannel.ALPHA:
            return "Alpha"
        Biomes.MaskChannel.LUMINANCE:
            return "Luminance"
    return "Unknown"
