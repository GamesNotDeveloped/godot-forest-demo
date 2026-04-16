@tool
class_name Biomes
extends Node3D

enum MaskChannel {
    RED,
    GREEN,
    BLUE,
    ALPHA,
    LUMINANCE,
}

const GENERATED_ROOT_NAME := "__biomes_generated"
const HASH_MASK := 0xFFFFFFFF
const MASK_SAMPLE_OFFSETS: Array[Vector2] = [
    Vector2(1.0, 0.0),
    Vector2(-1.0, 0.0),
    Vector2(0.0, 1.0),
    Vector2(0.0, -1.0),
    Vector2(0.70710677, 0.70710677),
    Vector2(-0.70710677, 0.70710677),
    Vector2(0.70710677, -0.70710677),
    Vector2(-0.70710677, -0.70710677),
]

var _regenerate_queued := false
var _connected_entries: Array[BiomeScatterEntry] = []
var _billboard_mesh_cache: Dictionary = {}
var _entry_changed_callable := Callable(self, "_on_entry_changed")
var _editor_state_signature := ""
var _mask_image_cache: Image
var _mask_cache_key := ""
var _generated_chunk_render_lods: Array[Dictionary] = [] # DEPRECATED, will be replaced by _chunk_render_lods

var _chunk_data: Dictionary = {}
var _chunk_collision_data: Dictionary = {}
var _active_chunks: Dictionary = {}
var _chunk_render_lods: Dictionary = {}
var _resolved_entries_cache: Array[Dictionary] = []
var _active_tasks: Dictionary = {} # coords -> task_id

@export_group("Generator")
@export var streaming_enabled := true:
    set(value):
        streaming_enabled = value
        _queue_regenerate()

@export_range(10.0, 2000.0, 1.0, "or_greater") var max_generation_distance: float = 120.0:
    set(value):
        max_generation_distance = maxf(value, 10.0)

@export_range(1, 64, 1, "or_greater") var chunks_per_frame: int = 4:
    set(value):
        chunks_per_frame = maxi(value, 1)

@export var entries: Array[BiomeScatterEntry] = []:
    set(value):
        entries = value
        _refresh_entry_connections()
        _queue_regenerate()

@export var seed: int = 1:
    set(value):
        seed = value
        _queue_regenerate()

@export var area_size: Vector2 = Vector2(40.0, 40.0):
    set(value):
        area_size = Vector2(maxf(value.x, 0.0), maxf(value.y, 0.0))
        _queue_regenerate()

@export_range(0.1, 1024.0, 0.1, "or_greater") var average_spacing: float = 3.0:
    set(value):
        average_spacing = maxf(value, 0.1)
        _queue_regenerate()

@export_range(1, 1000000, 1, "or_greater") var max_instances: int = 5000:
    set(value):
        max_instances = maxi(value, 1)
        _queue_regenerate()

@export_enum("Off:0", "On:1", "Double-Sided:2", "Shadows Only:3") var shadow_casting: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
    set(value):
        shadow_casting = clampi(value, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
        _queue_regenerate()

@export_enum("Disabled:0", "Static:1", "Dynamic:2") var gi_mode: int = GeometryInstance3D.GI_MODE_DYNAMIC:
    set(value):
        gi_mode = clampi(value, GeometryInstance3D.GI_MODE_DISABLED, GeometryInstance3D.GI_MODE_DYNAMIC)
        _queue_regenerate()

@export_subgroup("Density LOD")
@export var density_lod_enabled := false:
    set(value):
        density_lod_enabled = value
        _apply_density_lod()

@export_range(0.0, 100000.0, 0.1, "or_greater") var density_lod_start_distance: float = 40.0:
    set(value):
        density_lod_start_distance = maxf(value, 0.0)
        _apply_density_lod()

@export_range(0.0, 100000.0, 0.1, "or_greater") var density_lod_end_distance: float = 120.0:
    set(value):
        density_lod_end_distance = maxf(value, 0.0)
        _apply_density_lod()

@export_range(0.0, 1.0, 0.01) var density_lod_min_fraction: float = 0.2:
    set(value):
        density_lod_min_fraction = clampf(value, 0.0, 1.0)
        _apply_density_lod()

@export_subgroup("")

@export_group("Collision")
@export var generate_chunk_colliders := true:
    set(value):
        generate_chunk_colliders = value
        _queue_regenerate()

@export_flags_3d_physics var chunk_collision_layer: int = 1:
    set(value):
        chunk_collision_layer = value
        _queue_regenerate()

@export_flags_3d_physics var chunk_collision_mask: int = 1:
    set(value):
        chunk_collision_mask = value
        _queue_regenerate()

@export_range(0.1, 1024.0, 0.1, "or_greater") var chunk_size: float = 16.0:
    set(value):
        chunk_size = maxf(value, 0.1)
        _queue_regenerate()

@export_flags_3d_physics var collision_mask: int = 1:
    set(value):
        collision_mask = value
        _queue_regenerate()

@export var ray_direction: Vector3 = Vector3.DOWN:
    set(value):
        ray_direction = value
        _queue_regenerate()

@export_range(0.0, 100000.0, 0.1, "or_greater") var ray_start_offset: float = 200.0:
    set(value):
        ray_start_offset = maxf(value, 0.0)
        _queue_regenerate()

@export_range(0.01, 100000.0, 0.1, "or_greater") var ray_length: float = 400.0:
    set(value):
        ray_length = maxf(value, 0.01)
        _queue_regenerate()

@export_group("Mask")
@export var mask_enabled := false:
    set(value):
        mask_enabled = value
        _queue_regenerate()

@export var mask_texture: Texture2D:
    set(value):
        mask_texture = value
        _invalidate_mask_cache()
        _queue_regenerate()

@export_enum("Red", "Green", "Blue", "Alpha", "Luminance") var mask_channel: int = MaskChannel.RED:
    set(value):
        mask_channel = clampi(value, MaskChannel.RED, MaskChannel.LUMINANCE)
        _queue_regenerate()

@export_range(0.0, 1.0, 0.01) var mask_threshold: float = 0.5:
    set(value):
        mask_threshold = clampf(value, 0.0, 1.0)
        _queue_regenerate()

@export var mask_inverse := false:
    set(value):
        mask_inverse = value
        _queue_regenerate()

@export var mask_affects_density := true:
    set(value):
        mask_affects_density = value
        _queue_regenerate()

@export_group("Editor")
@export_dir var billboard_output_dir: String = "res://generated/biomes_billboards"

@export var editor_auto_regenerate := true:
    set(value):
        editor_auto_regenerate = value
        _update_editor_processing()
        if value:
            _queue_regenerate()

@export_tool_button("Regenerate")
var regenerate_button := regenerate


func _ready() -> void:
    _refresh_entry_connections()
    _update_editor_processing()
    _queue_regenerate()
    if not Engine.is_editor_hint():
        _runtime_regenerate_after_settle.call_deferred()


func _exit_tree() -> void:
    set_process(false)
    _disconnect_entry_connections()


var _last_high_quality_foliage := true

func _process(_delta: float) -> void:
    if Engine.is_editor_hint():
        var high_quality_val = RenderingServer.global_shader_parameter_get(&"gnd_high_quality_foliage")
        var high_quality: bool = bool(high_quality_val) if high_quality_val != null else true

        if high_quality != _last_high_quality_foliage:
            _last_high_quality_foliage = high_quality
            _update_all_shadow_casting()

        if editor_auto_regenerate:
            var next_signature := _build_editor_state_signature()
            if next_signature != _editor_state_signature:
                _editor_state_signature = next_signature
                _queue_regenerate()

    if streaming_enabled and not _regenerate_queued:
        _update_streaming()

    _apply_density_lod()


func regenerate() -> void:
    _regenerate_queued = false
    _refresh_entry_connections()
    _editor_state_signature = _build_editor_state_signature()
    _generate()


func get_mask_texture_path() -> String:
    if mask_texture == null:
        return ""
    return mask_texture.resource_path


func get_mask_image_copy() -> Image:
    var image := _get_mask_image()
    if image == null or image.is_empty():
        return Image.create(1, 1, false, Image.FORMAT_RGBA8)
    return image.duplicate()


func world_to_mask_uv(world_position: Vector3) -> Vector2:
    return local_to_mask_uv(to_local(world_position))


func local_to_mask_uv(local_position: Vector3) -> Vector2:
    if area_size.x <= 0.0 or area_size.y <= 0.0:
        return Vector2(-1.0, -1.0)

    return Vector2(
        (local_position.x / area_size.x) + 0.5,
        (local_position.z / area_size.y) + 0.5
    )


func sample_mask_value_at_world_position(world_position: Vector3, radius: float = 0.0) -> float:
    if not mask_enabled or mask_texture == null:
        return 1.0
    if radius > 0.0:
        return _sample_mask_average_value_at_world_position(world_position, radius)
    return _sample_single_mask_value_at_world_position(world_position)


func _sample_mask_average_value_at_world_position(world_position: Vector3, radius: float) -> float:
    var total := _sample_single_mask_value_at_world_position(world_position)
    var sample_count := 1.0
    for offset in MASK_SAMPLE_OFFSETS:
        total += _sample_single_mask_value_at_world_position(
            world_position + Vector3(offset.x * radius, 0.0, offset.y * radius)
        )
        sample_count += 1.0
    return total / sample_count


func _sample_single_mask_value_at_world_position(world_position: Vector3) -> float:
    var sample := _sample_mask_value_from_local_position(to_local(world_position), -1.0)
    if sample < 0.0:
        return 0.0
    return 1.0 - sample if mask_inverse else sample


func preview_mask_image(image: Image) -> void:
    _set_mask_cache_from_image(image)
    regenerate()


func set_mask_image(image: Image, save_to_disk := true) -> void:
    _set_mask_cache_from_image(image)
    if save_to_disk:
        _save_mask_image_to_disk(image)
        _mask_cache_key = _build_mask_cache_key()
    regenerate()


func create_mask_texture_file(path: String, resolution: int) -> bool:
    if path.is_empty() or resolution <= 0:
        return false

    var image := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.0, 0.0, 0.0, 1.0))
    if image.save_png(path) != OK:
        return false

    _set_mask_cache_from_image(image)
    _mask_cache_key = _build_mask_cache_key()
    mask_enabled = true
    return true


func assign_mask_texture(texture: Texture2D, enable_mask := true) -> void:
    mask_texture = texture
    mask_enabled = enable_mask
    notify_property_list_changed()
    regenerate()


func paint_mask_circle_on_image(image: Image, local_position: Vector3, radius_world: float, value: float, hardness: float = 0.35, opacity: float = 1.0) -> bool:
    if image == null or image.is_empty():
        return false

    var uv := local_to_mask_uv(local_position)
    if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
        return false

    var width := image.get_width()
    var height := image.get_height()
    if width <= 0 or height <= 0:
        return false

    var center_x := int(round(uv.x * float(width - 1)))
    var center_y := int(round(uv.y * float(height - 1)))
    var radius_px := _world_radius_to_pixel_radius(radius_world, width, height)
    var radius_sq := radius_px * radius_px
    var clamped_hardness := clampf(hardness, 0.0, 1.0)
    var clamped_opacity := clampf(opacity, 0.0, 1.0)
    var inner_radius := float(radius_px) * clamped_hardness
    var changed := false

    for y in range(maxi(0, center_y - radius_px), mini(height, center_y + radius_px + 1)):
        for x in range(maxi(0, center_x - radius_px), mini(width, center_x + radius_px + 1)):
            var dx := x - center_x
            var dy := y - center_y
            var distance_sq := (dx * dx) + (dy * dy)
            if distance_sq > radius_sq:
                continue
            var distance := sqrt(float(distance_sq))
            var influence := 1.0
            if radius_px > 0 and distance > inner_radius:
                var outer_range := maxf(float(radius_px) - inner_radius, 0.0001)
                var falloff_t := clampf((distance - inner_radius) / outer_range, 0.0, 1.0)
                influence = 1.0 - _smoothstep(0.0, 1.0, falloff_t)
            influence *= clamped_opacity
            if influence <= 0.0:
                continue
            var color := image.get_pixel(x, y)
            var next_color := _apply_mask_paint(color, value, influence)
            if next_color != color:
                image.set_pixel(x, y, next_color)
                changed = true
    return changed


func _queue_regenerate() -> void:
    if not is_inside_tree():
        return
    if Engine.is_editor_hint() and not editor_auto_regenerate:
        return
    if _regenerate_queued:
        return
    _regenerate_queued = true
    call_deferred("_deferred_regenerate")


func _deferred_regenerate() -> void:
    _regenerate_queued = false
    if not is_inside_tree():
        return
    _generate()


func _runtime_regenerate_after_settle() -> void:
    await get_tree().process_frame
    if not is_inside_tree():
        return
    regenerate()


func _generate() -> void:
    _clear_generated()
    _resolved_entries_cache = _resolve_entries()

    if not streaming_enabled:
        _build_all_chunks_immediately()


func _async_generate_chunk_data(coords: Vector2i) -> void:
    if _active_tasks.has(coords):
        return

    var task_id := WorkerThreadPool.add_task(func(): _generate_chunk_data(coords))
    _active_tasks[coords] = task_id


func _is_chunk_data_ready(coords: Vector2i) -> bool:
    if not _active_tasks.has(coords):
        return false

    var task_id: int = _active_tasks[coords]
    if WorkerThreadPool.is_task_completed(task_id):
        _active_tasks.erase(coords)
        return true
    return false


func _generate_chunk_data(chunk_coords: Vector2i) -> void:
    # To jest wywoływane W TLE (oddzielny wątek)
    if _resolved_entries_cache.is_empty():
        return

    # UWAGA: Na wątku nie możemy używać physics state bez blokowania,
    # więc najpierw zbieramy wszystkie dane, a raycasty (rzutowania)
    # zostaną wykonane dopiero w momencie finalizacji na wątku głównym.
    var chunk_min_x := float(chunk_coords.x) * chunk_size
    var chunk_min_z := float(chunk_coords.y) * chunk_size
    var chunk_max_x := chunk_min_x + chunk_size
    var chunk_max_z := chunk_min_z + chunk_size

    var half_area := area_size * 0.5
    var generation_min_x := -half_area.x
    var generation_max_x := half_area.x
    var generation_min_z := -half_area.y
    var generation_max_z := half_area.y

    var effective_area_m2 := maxf(area_size.x * area_size.y, 0.0001)
    var spacing := maxf(average_spacing, 0.1)
    if max_instances > 0:
        spacing = maxf(spacing, sqrt(effective_area_m2 / float(max_instances)))

    var cell_size := spacing
    var min_cell_x := int(floor(chunk_min_x / cell_size))
    var max_cell_x := int(ceil(chunk_max_x / cell_size))
    var min_cell_z := int(floor(chunk_min_z / cell_size))
    var max_cell_z := int(ceil(chunk_max_z / cell_size))

    # Wypełniamy listę punktów do sprawdzenia
    var points: Array[Dictionary] = []

    for cell_x in range(min_cell_x, max_cell_x):
        for cell_z in range(min_cell_z, max_cell_z):
            var local_x := (float(cell_x) + _hash01(seed, cell_x, cell_z, 11)) * cell_size
            var local_z := (float(cell_z) + _hash01(seed, cell_x, cell_z, 17)) * cell_size

            if local_x < chunk_min_x or local_x >= chunk_max_x or local_z < chunk_min_z or local_z >= chunk_max_z:
                continue
            if local_x < generation_min_x or local_x > generation_max_x or local_z < generation_min_z or local_z > generation_max_z:
                continue

            var mask_density := _sample_mask_density_weight_from_local_position(Vector3(local_x, 0.0, local_z))
            if mask_density <= 0.0 or _hash01(seed, cell_x, cell_z, 7) > mask_density:
                continue

            var resolved_entry: Dictionary = _pick_entry(_resolved_entries_cache, cell_x, cell_z)
            if resolved_entry.is_empty():
                continue

            # Obliczamy tylko matematykę na wątku pobocznym
            var scale_min_value: Vector3 = resolved_entry["scale_min"]
            var scale_max_value: Vector3 = resolved_entry["scale_max"]
            var instance_scale := Vector3(
                lerpf(minf(scale_min_value.x, scale_max_value.x), maxf(scale_min_value.x, scale_max_value.x), _hash01(seed, cell_x, cell_z, 23)),
                lerpf(minf(scale_min_value.y, scale_max_value.y), maxf(scale_min_value.y, scale_max_value.y), _hash01(seed, cell_x, cell_z, 29)),
                lerpf(minf(scale_min_value.z, scale_max_value.z), maxf(scale_min_value.z, scale_max_value.z), _hash01(seed, cell_x, cell_z, 31))
            )
            var yaw := TAU * _hash01(seed, cell_x, cell_z, 37)

            points.append({
                "pos": Vector3(local_x, 0.0, local_z),
                "scale": instance_scale,
                "yaw": yaw,
                "entry": resolved_entry,
                "priority": _hash01(seed, cell_x, cell_z, 53)
            })

    # Składamy wynik w paczkę, którą wątek główny przetworzy (zrobi raycasty)
    _finalize_chunk_generation_from_points(chunk_coords, points)


func _finalize_chunk_generation_from_points(chunk_coords: Vector2i, points: Array[Dictionary]) -> void:
    # To wywołujemy, aby złożyć dane (nadal na wątku zadania, ale po zebraniu danych)
    # Rzutowania promieni wykonamy jednak w safe-context zaraz po zakończeniu zadania.
    # Aby to było bezpieczne, zapisujemy listę punktów do tymczasowego cache.
    var key := _chunk_coords_key(chunk_coords)
    _pending_chunk_points[key] = points


var _pending_chunk_points: Dictionary = {} # coords_key -> Array[points]


func _generate_raycasts_and_finalize_chunk(chunk_coords: Vector2i) -> void:
    # TO JEST NA WĄTKU GŁÓWNYM zaraz przed budowaniem
    var key := _chunk_coords_key(chunk_coords)
    if not _pending_chunk_points.has(key):
        return

    var points: Array = _pending_chunk_points[key]
    var world := get_world_3d()
    if world == null:
        return
    var state := world.direct_space_state
    var direction := ray_direction.normalized() if not ray_direction.is_zero_approx() else Vector3.DOWN

    for p in points:
        var entry: Dictionary = p["entry"]
        var local_hit: Variant = _raycast_to_surface(state, p["pos"], direction)
        var hit_position: Vector3 = local_hit if local_hit != null else p["pos"]

        var transform := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, p["yaw"]).scaled(p["scale"]), hit_position)

        # Render Data
        var chunk_key := _chunk_key(chunk_coords, entry["index"])
        if not _chunk_data.has(chunk_key):
            _chunk_data[chunk_key] = {"chunk_coords": chunk_coords, "entry": entry, "near": [], "far": [], "lod_priorities": []}

        var bucket: Dictionary = _chunk_data[chunk_key]
        bucket["near"].append(transform)
        if not entry["billboard_parts"].is_empty():
            bucket["far"].append(transform)
        bucket["lod_priorities"].append(p["priority"])

        # Collision Data
        if generate_chunk_colliders and not entry["collision_parts"].is_empty():
            var collision_chunk_key := _chunk_coords_key(chunk_coords)
            if not _chunk_collision_data.has(collision_chunk_key):
                _chunk_collision_data[collision_chunk_key] = {"chunk_coords": chunk_coords, "shapes": []}

            var col_bucket: Dictionary = _chunk_collision_data[collision_chunk_key]
            for collision_part in entry["collision_parts"]:
                col_bucket["shapes"].append({
                    "shape": collision_part["shape"],
                    "transform": _sanitize_collision_transform(transform * collision_part["transform"])
                })

    _pending_chunk_points.erase(key)



func _build_all_chunks_immediately() -> void:
    var half_area := area_size * 0.5
    var min_chunk_x := int(floor(-half_area.x / chunk_size))
    var max_chunk_x := int(ceil(half_area.x / chunk_size))
    var min_chunk_z := int(floor(-half_area.y / chunk_size))
    var max_chunk_z := int(ceil(half_area.y / chunk_size))

    for x in range(min_chunk_x, max_chunk_x):
        for z in range(min_chunk_z, max_chunk_z):
            var coords := Vector2i(x, z)
            _generate_chunk_data(coords)
            _build_chunk_nodes(coords)



func _build_generated_nodes(_a: Dictionary, _b: Dictionary) -> void:
    pass


func _create_multimesh_instances(name: String, parts: Array, transforms: Array, chunk_center: Vector3) -> Array[MultiMeshInstance3D]:
    var instances: Array[MultiMeshInstance3D] = []
    if parts.is_empty() or transforms.is_empty():
        return instances

    for part_index in range(parts.size()):
        var part: Dictionary = parts[part_index]
        var mesh: Mesh = part["mesh"]
        if mesh == null:
            continue

        var multimesh := MultiMesh.new()
        multimesh.transform_format = MultiMesh.TRANSFORM_3D
        multimesh.mesh = mesh
        multimesh.instance_count = transforms.size()
        multimesh.visible_instance_count = transforms.size()

        var part_transform: Transform3D = part["transform"]
        for transform_index in range(transforms.size()):
            var transform: Transform3D = transforms[transform_index]
            transform = transform * part_transform
            transform.origin -= chunk_center
            multimesh.set_instance_transform(transform_index, transform)

        var target_shadows = shadow_casting as GeometryInstance3D.ShadowCastingSetting
        if not _last_high_quality_foliage:
            target_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

        var instance := MultiMeshInstance3D.new()
        instance.name = "%s_%s" % [name, part_index]
        instance.multimesh = multimesh
        instance.cast_shadow = target_shadows
        instance.gi_mode = gi_mode as GeometryInstance3D.GIMode
        instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
        instances.append(instance)

    return instances


func _sort_chunk_bucket_for_density_lod(bucket: Dictionary) -> Dictionary:
    var near_transforms: Array = bucket["near"]
    var far_transforms: Array = bucket["far"]
    var lod_priorities: Array = bucket["lod_priorities"]
    if near_transforms.size() <= 1:
        return bucket

    var order: Array = []
    for index in range(near_transforms.size()):
        order.append({
            "index": index,
            "priority": lod_priorities[index]
        })
    order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return a["priority"] < b["priority"]
    )

    var sorted_near: Array = []
    var sorted_far: Array = []
    var sorted_priorities: Array = []
    for item in order:
        var source_index: int = item["index"]
        sorted_near.append(near_transforms[source_index])
        if source_index < far_transforms.size():
            sorted_far.append(far_transforms[source_index])
        sorted_priorities.append(lod_priorities[source_index])

    return {
        "chunk_coords": bucket["chunk_coords"],
        "entry": bucket["entry"],
        "near": sorted_near,
        "far": sorted_far,
        "lod_priorities": sorted_priorities
    }


func _register_chunk_render_lod(_chunk_node: Node3D, _near_instances: Array[MultiMeshInstance3D], _far_instances: Array[MultiMeshInstance3D], _full_count: int) -> void:
    pass # Obsolete with new chunk management


func _update_streaming() -> void:
    var camera := _get_density_lod_camera()
    if camera == null:
        return

    # Używamy pozycji LOKALNEJ kamery względem węzła Biomes
    var camera_pos_local := to_local(camera.global_position)
    var current_chunk_coords := Vector2i(
        int(floor(camera_pos_local.x / chunk_size)),
        int(floor(camera_pos_local.z / chunk_size))
    )

    var max_dist_sq := max_generation_distance * max_generation_distance
    var chunk_radius := int(ceil(max_generation_distance / chunk_size))

    # Identify chunks that should be active
    var needed_chunks: Array[Vector2i] = []
    for x in range(current_chunk_coords.x - chunk_radius, current_chunk_coords.x + chunk_radius + 1):
        for z in range(current_chunk_coords.y - chunk_radius, current_chunk_coords.y + chunk_radius + 1):
            var coords := Vector2i(x, z)
            var chunk_center := _chunk_center(coords)
            if camera_pos_local.distance_squared_to(chunk_center) <= max_dist_sq:
                needed_chunks.append(coords)

    # Remove chunks that are no longer needed
    var to_remove: Array[Vector2i] = []
    for coords in _active_chunks.keys():
        if not coords in needed_chunks:
            to_remove.append(coords)

    for coords in to_remove:
        var chunk_node: Node3D = _active_chunks[coords]
        if is_instance_valid(chunk_node):
            chunk_node.queue_free()
        _active_chunks.erase(coords)
        _chunk_render_lods.erase(coords)

    # Add chunks that are needed but not active (limited per frame)
    var build_count := 0
    for coords in needed_chunks:
        if not _active_chunks.has(coords):
            # SPRAWDZAMY CZY MAMY DANE DLA TEGO CHUNKA
            var data_exists = false
            for entry_index in range(_resolved_entries_cache.size()):
                if _chunk_data.has(_chunk_key(coords, entry_index)):
                    data_exists = true
                    break

            if not data_exists and _chunk_collision_data.has(_chunk_coords_key(coords)):
                data_exists = true

            # JEŚLI NIE MA DANYCH - ZLECAMY GENEROWANIE W TLE
            if not data_exists:
                if not _active_tasks.has(coords):
                    _async_generate_chunk_data(coords)
                elif _is_chunk_data_ready(coords):
                    # Dane matematyczne gotowe, robimy raycasty i budujemy
                    _generate_raycasts_and_finalize_chunk(coords)
                    _build_chunk_nodes(coords)
                    build_count += 1
                continue # Czekamy aż dane będą gotowe w następnej klatce

            _build_chunk_nodes(coords)
            build_count += 1
            if build_count >= chunks_per_frame:
                break


func _build_chunk_nodes(chunk_coords: Vector2i) -> void:
    var generated_root := _ensure_generated_root()
    var chunk_node := Node3D.new()
    chunk_node.name = "chunk_%s_%s" % [chunk_coords.x, chunk_coords.y]
    chunk_node.position = _chunk_center(chunk_coords)
    generated_root.add_child(chunk_node, false, INTERNAL_MODE_FRONT)
    _active_chunks[chunk_coords] = chunk_node

    var chunk_lod_data: Array[Dictionary] = []

    # Build meshes
    for entry_index in range(entries.size()):
        var chunk_key := _chunk_key(chunk_coords, entry_index)
        if not _chunk_data.has(chunk_key):
            continue

        var bucket: Dictionary = _chunk_data[chunk_key]
        var resolved_entry: Dictionary = bucket["entry"]
        var sorted_bucket := _sort_chunk_bucket_for_density_lod(bucket)

        var near_instances := _create_multimesh_instances(
            "near_%s" % resolved_entry["index"],
            resolved_entry["main_parts"],
            sorted_bucket["near"],
            chunk_node.position
        )
        for instance in near_instances:
            chunk_node.add_child(instance, false, INTERNAL_MODE_FRONT)

        var far_instances: Array[MultiMeshInstance3D] = []
        if not resolved_entry["billboard_parts"].is_empty():
            var lod_distance: float = resolved_entry["billboard_lod_distance"]
            far_instances = _create_multimesh_instances(
                "far_%s" % resolved_entry["index"],
                resolved_entry["billboard_parts"],
                sorted_bucket["far"],
                chunk_node.position
            )
            for far_instance in far_instances:
                if lod_distance > 0.0:
                    for instance in near_instances:
                        instance.visibility_range_end = lod_distance
                    far_instance.visibility_range_begin = lod_distance
                chunk_node.add_child(far_instance, false, INTERNAL_MODE_FRONT)

        var full_count: int = sorted_bucket["near"].size()
        var render_nodes: Array[GeometryInstance3D] = []
        for instance in near_instances: render_nodes.append(instance)
        for instance in far_instances: render_nodes.append(instance)

        chunk_lod_data.append({
            "full_count": full_count,
            "visible_count": full_count,
            "render_nodes": render_nodes
        })

    if not chunk_lod_data.is_empty():
        _chunk_render_lods[chunk_coords] = chunk_lod_data

    # Build collisions
    var collision_key := _chunk_coords_key(chunk_coords)
    if _chunk_collision_data.has(collision_key):
        var collision_bucket: Dictionary = _chunk_collision_data[collision_key]
        _build_chunk_collider(chunk_node, collision_bucket["shapes"])



func _resolve_entries() -> Array[Dictionary]:
    var resolved: Array[Dictionary] = []
    _billboard_mesh_cache.clear()

    for index in range(entries.size()):
        var entry := entries[index]
        if entry == null:
            continue

        var main_parts := _resolve_mesh_parts(entry.mesh_scene, entry.mesh, false)
        if main_parts.is_empty() or entry.probability <= 0.0:
            continue

        var billboard_parts := _resolve_mesh_parts(entry.billboard_scene, entry.billboard_mesh, true)
        var collision_parts := _resolve_collision_parts(entry.mesh_scene)
        resolved.append({
            "index": index,
            "entry": entry,
            "main_parts": main_parts,
            "billboard_parts": billboard_parts,
            "collision_parts": collision_parts,
            "probability": entry.probability,
            "billboard_lod_distance": maxf(entry.billboard_lod_distance, 0.0),
            "scale_min": entry.scale_min,
            "scale_max": entry.scale_max
        })

    return resolved


func _resolve_mesh_parts(scene: PackedScene, fallback_mesh: Mesh, billboard: bool) -> Array[Dictionary]:
    if scene == null:
        return _fallback_mesh_parts(fallback_mesh, billboard)

    var instance := scene.instantiate()
    if instance == null:
        return _fallback_mesh_parts(fallback_mesh, billboard)

    var parts: Array[Dictionary] = []
    _collect_mesh_parts(instance, Transform3D.IDENTITY, billboard, parts)
    instance.free()
    if parts.is_empty():
        return _fallback_mesh_parts(fallback_mesh, billboard)
    return parts


func _resolve_collision_parts(scene: PackedScene) -> Array[Dictionary]:
    var parts: Array[Dictionary] = []
    if scene == null:
        return parts

    var instance := scene.instantiate()
    if instance == null:
        return parts

    _collect_collision_parts(instance, Transform3D.IDENTITY, parts)
    instance.free()
    return parts


func _fallback_mesh_parts(fallback_mesh: Mesh, billboard: bool) -> Array[Dictionary]:
    var parts: Array[Dictionary] = []
    if fallback_mesh == null:
        return parts

    var mesh := _make_billboard_mesh(fallback_mesh) if billboard else fallback_mesh
    parts.append({
        "mesh": mesh,
        "transform": Transform3D.IDENTITY
    })
    return parts


func _collect_mesh_parts(node: Node, parent_transform: Transform3D, billboard: bool, parts: Array[Dictionary]) -> void:
    var local_transform := parent_transform
    var node_3d := node as Node3D
    if node_3d != null:
        local_transform = parent_transform * node_3d.transform

    var mesh_instance := node as MeshInstance3D
    if mesh_instance != null and mesh_instance.mesh != null:
        var mesh := _mesh_with_instance_materials(mesh_instance, billboard)
        parts.append({
            "mesh": mesh,
            "transform": local_transform
        })

    for child in node.get_children():
        var child_node := child as Node
        if child_node == null:
            continue
        _collect_mesh_parts(child_node, local_transform, billboard, parts)


func _collect_collision_parts(node: Node, parent_transform: Transform3D, parts: Array[Dictionary]) -> void:
    var local_transform := parent_transform
    var node_3d := node as Node3D
    if node_3d != null:
        local_transform = parent_transform * node_3d.transform

    var collision_shape := node as CollisionShape3D
    if collision_shape != null and collision_shape.shape != null and not collision_shape.disabled:
        parts.append({
            "shape": collision_shape.shape,
            "transform": local_transform
        })

    for child in node.get_children():
        var child_node := child as Node
        if child_node == null:
            continue
        _collect_collision_parts(child_node, local_transform, parts)


func _mesh_with_instance_materials(mesh_instance: MeshInstance3D, billboard: bool) -> Mesh:
    var source_mesh := mesh_instance.mesh
    if source_mesh == null:
        return null

    var mesh := source_mesh.duplicate(true) as Mesh
    if mesh == null:
        mesh = source_mesh

    for surface_index in range(mesh.get_surface_count()):
        var active_material := mesh_instance.get_active_material(surface_index)
        if active_material == null:
            continue
        var material := active_material
        if billboard and material is BaseMaterial3D:
            var duplicated_material := material.duplicate(true) as BaseMaterial3D
            if duplicated_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
                duplicated_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
            duplicated_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
            duplicated_material.alpha_scissor_threshold = 0.5
            duplicated_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
            duplicated_material.roughness = 1.0
            duplicated_material.metallic_specular = 0.0
            material = duplicated_material
        mesh.surface_set_material(surface_index, material)

    if billboard:
        mesh = _make_billboard_mesh(mesh)
    return mesh


func _make_billboard_mesh(source_mesh: Mesh) -> Mesh:
    if source_mesh == null:
        return null

    var cache_key := source_mesh.get_instance_id()
    if _billboard_mesh_cache.has(cache_key):
        return _billboard_mesh_cache[cache_key]

    var duplicated := source_mesh.duplicate(true) as Mesh
    if duplicated == null:
        return source_mesh

    for surface_index in range(duplicated.get_surface_count()):
        var surface_material := duplicated.surface_get_material(surface_index)
        if surface_material == null:
            var created_material := StandardMaterial3D.new()
            created_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
            created_material.roughness = 1.0
            created_material.metallic_specular = 0.0
            duplicated.surface_set_material(surface_index, created_material)
            continue
        if surface_material is BaseMaterial3D:
            var duplicated_material := surface_material.duplicate(true) as BaseMaterial3D
            if duplicated_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
                duplicated_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
            duplicated_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
            duplicated_material.alpha_scissor_threshold = 0.5
            duplicated_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
            duplicated_material.roughness = 1.0
            duplicated_material.metallic_specular = 0.0
            duplicated.surface_set_material(surface_index, duplicated_material)

    _billboard_mesh_cache[cache_key] = duplicated
    return duplicated


func _pick_entry(resolved_entries: Array[Dictionary], cell_x: int, cell_z: int) -> Dictionary:
    var total_weight := 0.0
    for resolved_entry in resolved_entries:
        total_weight += float(resolved_entry["probability"])
    if total_weight <= 0.0:
        return {}

    var pick := _hash01(seed, cell_x, cell_z, 41) * total_weight
    var cumulative := 0.0
    for resolved_entry in resolved_entries:
        cumulative += float(resolved_entry["probability"])
        if pick <= cumulative:
            return resolved_entry
    return resolved_entries.back()


func _raycast_to_surface(state: PhysicsDirectSpaceState3D, local_origin: Vector3, direction: Vector3) -> Variant:
    var start := to_global(local_origin - direction * ray_start_offset)
    var target := start + direction * ray_length
    var query := PhysicsRayQueryParameters3D.create(start, target, collision_mask)
    query.collide_with_areas = false
    query.collide_with_bodies = true
    var hit := state.intersect_ray(query)
    if hit.is_empty():
        return null
    return to_local(hit["position"])


func _passes_mask_filter(local_x: float, local_z: float) -> bool:
    return _sample_mask_density_weight_from_local_position(Vector3(local_x, 0.0, local_z)) > 0.0


func _sample_mask_density_weight_from_local_position(local_position: Vector3) -> float:
    if not mask_enabled or mask_texture == null:
        return 1.0

    var sample := _sample_mask_value_from_local_position(local_position, -1.0)
    if sample < 0.0:
        return 0.0
    var adjusted := 1.0 - sample if mask_inverse else sample
    adjusted = clampf(adjusted, 0.0, 1.0)
    if not mask_affects_density:
        return 1.0 if adjusted >= mask_threshold else 0.0
    if adjusted <= mask_threshold:
        return 0.0
    return inverse_lerp(mask_threshold, 1.0, adjusted)


func _analyze_mask_generation_region(image: Image) -> Dictionary:
    var width := image.get_width()
    var height := image.get_height()
    if width <= 0 or height <= 0:
        return {
            "has_active": false,
            "min_x": 0.0,
            "max_x": 0.0,
            "min_z": 0.0,
            "max_z": 0.0,
            "weighted_area_m2": 0.0,
        }

    var min_px := width
    var max_px := -1
    var min_py := height
    var max_py := -1
    var weighted_sum := 0.0

    for py in range(height):
        for px in range(width):
            var raw_sample := _sample_mask_channel(image.get_pixel(px, py))
            var adjusted := 1.0 - raw_sample if mask_inverse else raw_sample
            adjusted = clampf(adjusted, 0.0, 1.0)
            var density_weight := 0.0
            if not mask_affects_density:
                density_weight = 1.0 if adjusted >= mask_threshold else 0.0
            elif adjusted > mask_threshold:
                density_weight = inverse_lerp(mask_threshold, 1.0, adjusted)
            if density_weight <= 0.0:
                continue

            min_px = mini(min_px, px)
            max_px = maxi(max_px, px)
            min_py = mini(min_py, py)
            max_py = maxi(max_py, py)
            weighted_sum += density_weight

    if max_px < min_px or max_py < min_py or weighted_sum <= 0.0:
        return {
            "has_active": false,
            "min_x": 0.0,
            "max_x": 0.0,
            "min_z": 0.0,
            "max_z": 0.0,
            "weighted_area_m2": 0.0,
        }

    var min_uv_x := float(min_px) / float(width)
    var max_uv_x := float(max_px + 1) / float(width)
    var min_uv_y := float(min_py) / float(height)
    var max_uv_y := float(max_py + 1) / float(height)
    var weighted_fraction := weighted_sum / float(width * height)

    return {
        "has_active": true,
        "min_x": (min_uv_x - 0.5) * area_size.x,
        "max_x": (max_uv_x - 0.5) * area_size.x,
        "min_z": (min_uv_y - 0.5) * area_size.y,
        "max_z": (max_uv_y - 0.5) * area_size.y,
        "weighted_area_m2": area_size.x * area_size.y * weighted_fraction,
    }


func _sample_mask_value_from_local_position(local_position: Vector3, outside_value: float) -> float:
    var uv := local_to_mask_uv(local_position)
    return _sample_mask_value_from_uv(uv, outside_value)


func _sample_mask_value_from_uv(uv: Vector2, outside_value: float) -> float:
    var image := _get_mask_image()
    if image == null or image.is_empty():
        return 1.0
    if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
        return outside_value

    var width := image.get_width()
    var height := image.get_height()
    if width <= 0 or height <= 0:
        return 1.0

    var pixel_x := clampi(int(floor(uv.x * float(width))), 0, width - 1)
    var pixel_y := clampi(int(floor(uv.y * float(height))), 0, height - 1)
    return _sample_mask_channel(image.get_pixel(pixel_x, pixel_y))


func _sample_mask_channel(color: Color) -> float:
    match mask_channel:
        MaskChannel.RED:
            return color.r
        MaskChannel.GREEN:
            return color.g
        MaskChannel.BLUE:
            return color.b
        MaskChannel.ALPHA:
            return color.a
        MaskChannel.LUMINANCE:
            return color.get_luminance()
    return color.r


func _apply_mask_paint(color: Color, value: float, influence: float) -> Color:
    var clamped_value := clampf(value, 0.0, 1.0)
    var clamped_influence := clampf(influence, 0.0, 1.0)
    match mask_channel:
        MaskChannel.RED:
            color.r = lerpf(color.r, clamped_value, clamped_influence)
        MaskChannel.GREEN:
            color.g = lerpf(color.g, clamped_value, clamped_influence)
        MaskChannel.BLUE:
            color.b = lerpf(color.b, clamped_value, clamped_influence)
        MaskChannel.ALPHA:
            color.a = lerpf(color.a, clamped_value, clamped_influence)
        MaskChannel.LUMINANCE:
            color.r = lerpf(color.r, clamped_value, clamped_influence)
            color.g = lerpf(color.g, clamped_value, clamped_influence)
            color.b = lerpf(color.b, clamped_value, clamped_influence)
    return color


func _smoothstep(edge0: float, edge1: float, x: float) -> float:
    var t := clampf(inverse_lerp(edge0, edge1, x), 0.0, 1.0)
    return t * t * (3.0 - (2.0 * t))


func _world_radius_to_pixel_radius(radius_world: float, width: int, height: int) -> int:
    var world_per_pixel_x := area_size.x / maxf(float(width), 1.0)
    var world_per_pixel_y := area_size.y / maxf(float(height), 1.0)
    var world_per_pixel := maxf(minf(world_per_pixel_x, world_per_pixel_y), 0.0001)
    return maxi(1, int(ceil(radius_world / world_per_pixel)))


func _get_mask_image() -> Image:
    if mask_texture == null:
        return null

    var cache_key := _build_mask_cache_key()
    if _mask_image_cache != null and _mask_cache_key == cache_key and not _mask_image_cache.is_empty():
        return _mask_image_cache

    var image := mask_texture.get_image()
    if image == null or image.is_empty():
        return null
    if image.is_compressed():
        var decompress_error := image.decompress()
        if decompress_error != OK:
            push_warning("Biomes mask could not be decompressed for sampling: %s" % cache_key)
            return null
    if image.get_format() != Image.FORMAT_RGBA8:
        image.convert(Image.FORMAT_RGBA8)

    _mask_image_cache = image
    _mask_cache_key = cache_key
    return _mask_image_cache


func _set_mask_cache_from_image(image: Image) -> void:
    if image == null or image.is_empty():
        _mask_image_cache = null
        _mask_cache_key = ""
        return

    _mask_image_cache = image.duplicate()
    if _mask_image_cache.is_compressed():
        _mask_image_cache.decompress()
    if _mask_image_cache.get_format() != Image.FORMAT_RGBA8:
        _mask_image_cache.convert(Image.FORMAT_RGBA8)
    _mask_cache_key = _build_mask_cache_key()


func _save_mask_image_to_disk(image: Image) -> void:
    var path := get_mask_texture_path()
    if path.is_empty():
        return
    image.save_png(path)


func _load_mask_texture_from_path(path: String) -> void:
    var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
    if loaded is Texture2D:
        mask_texture = loaded
    else:
        mask_texture = ImageTexture.create_from_image(_mask_image_cache)


func _reload_mask_texture_from_disk() -> void:
    var path := get_mask_texture_path()
    if path.is_empty():
        return
    _load_mask_texture_from_path(path)


func _invalidate_mask_cache() -> void:
    _mask_image_cache = null
    _mask_cache_key = ""


func _build_mask_cache_key() -> String:
    var path := get_mask_texture_path()
    var modified := ""
    if not path.is_empty() and FileAccess.file_exists(path):
        modified = str(FileAccess.get_modified_time(path))
    return "%s|%s" % [_resource_id(mask_texture), modified]


func _chunk_key(chunk_coords: Vector2i, entry_index: int) -> String:
    return "%s:%s:%s" % [chunk_coords.x, chunk_coords.y, entry_index]


func _chunk_coords_key(chunk_coords: Vector2i) -> String:
    return "%s:%s" % [chunk_coords.x, chunk_coords.y]


func _chunk_center(chunk_coords: Vector2i) -> Vector3:
    return Vector3(
        (float(chunk_coords.x) + 0.5) * chunk_size,
        0.0,
        (float(chunk_coords.y) + 0.5) * chunk_size
    )


func _ensure_generated_root() -> Node3D:
    var generated_root := get_node_or_null(GENERATED_ROOT_NAME) as Node3D
    if generated_root != null:
        return generated_root

    generated_root = Node3D.new()
    generated_root.name = GENERATED_ROOT_NAME
    add_child(generated_root, false, INTERNAL_MODE_FRONT)
    return generated_root


func _ensure_chunk_node(generated_root: Node3D, chunk_nodes: Dictionary, chunk_coords: Vector2i) -> Node3D:
    var key := _chunk_coords_key(chunk_coords)
    if chunk_nodes.has(key):
        return chunk_nodes[key]

    var chunk_node := Node3D.new()
    chunk_node.name = "chunk_%s_%s" % [chunk_coords.x, chunk_coords.y]
    chunk_node.position = _chunk_center(chunk_coords)
    generated_root.add_child(chunk_node, false, INTERNAL_MODE_FRONT)
    chunk_nodes[key] = chunk_node
    return chunk_node


func _build_chunk_collider(chunk_node: Node3D, shapes: Array) -> void:
    if shapes.is_empty():
        return

    var body := StaticBody3D.new()
    body.name = "ChunkCollider"
    body.collision_layer = chunk_collision_layer
    body.collision_mask = chunk_collision_mask
    chunk_node.add_child(body, false, INTERNAL_MODE_FRONT)

    for shape_index in range(shapes.size()):
        var shape_data: Dictionary = shapes[shape_index]
        var shape: Shape3D = shape_data["shape"]
        if shape == null:
            continue

        var collision_shape := CollisionShape3D.new()
        collision_shape.name = "Shape_%s" % shape_index
        collision_shape.shape = shape
        collision_shape.transform = shape_data["transform"]
        collision_shape.position -= chunk_node.position
        body.add_child(collision_shape, false, INTERNAL_MODE_FRONT)


func _sanitize_collision_transform(source_transform: Transform3D) -> Transform3D:
    var basis := source_transform.basis
    var scale := basis.get_scale()
    var horizontal_scale := (absf(scale.x) + absf(scale.z)) * 0.5
    horizontal_scale = maxf(horizontal_scale, 0.0001)
    var vertical_scale := maxf(absf(scale.y), 0.0001)
    var sanitized_basis := basis.orthonormalized().scaled(Vector3(horizontal_scale, vertical_scale, horizontal_scale))
    return Transform3D(sanitized_basis, source_transform.origin)


func _clear_generated() -> void:
    _chunk_data.clear()
    _chunk_collision_data.clear()
    _active_chunks.clear()
    _chunk_render_lods.clear()
    _generated_chunk_render_lods.clear()
    var generated_root := get_node_or_null(GENERATED_ROOT_NAME) as Node3D
    if generated_root != null:
        remove_child(generated_root)
        generated_root.free()


func _refresh_entry_connections() -> void:
    _disconnect_entry_connections()
    for entry in entries:
        if entry == null:
            continue
        if not entry.changed.is_connected(_entry_changed_callable):
            entry.changed.connect(_entry_changed_callable)
        _connected_entries.append(entry)


func _disconnect_entry_connections() -> void:
    for entry in _connected_entries:
        if is_instance_valid(entry) and entry.changed.is_connected(_entry_changed_callable):
            entry.changed.disconnect(_entry_changed_callable)
    _connected_entries.clear()


func _on_entry_changed() -> void:
    _queue_regenerate()


func _update_editor_processing() -> void:
    if not Engine.is_editor_hint():
        set_process(true) # W grze streaming jest zawsze aktywny
        return

    set_process(editor_auto_regenerate)


func _build_editor_state_signature() -> String:
    var parts: PackedStringArray = [
        str(seed),
        str(area_size),
        str(average_spacing),
        str(max_instances),
        str(density_lod_enabled),
        str(density_lod_start_distance),
        str(density_lod_end_distance),
        str(density_lod_min_fraction),
        str(generate_chunk_colliders),
        str(chunk_collision_layer),
        str(chunk_collision_mask),
        str(chunk_size),
        str(collision_mask),
        str(ray_direction),
        str(ray_start_offset),
        str(ray_length),
        str(mask_enabled),
        _resource_id(mask_texture),
        str(mask_channel),
        str(mask_threshold),
        str(mask_inverse),
        _build_mask_cache_key(),
        str(editor_auto_regenerate),
        str(entries.size())
    ]

    for entry in entries:
        if entry == null:
            parts.append("<null>")
            continue

        parts.append_array(PackedStringArray([
            entry.resource_path,
            str(entry.get_instance_id()),
            _resource_id(entry.mesh),
            _resource_id(entry.mesh_scene),
            _resource_id(entry.billboard_mesh),
            _resource_id(entry.billboard_scene),
            str(entry.probability),
            str(entry.billboard_lod_distance),
            str(entry.scale_min),
            str(entry.scale_max)
        ]))

    return "|".join(parts)


func _resource_id(resource: Resource) -> String:
    if resource == null:
        return ""
    return "%s#%s" % [resource.resource_path, resource.get_instance_id()]


func _apply_density_lod() -> void:
    if _chunk_render_lods.is_empty():
        return

    var camera := _get_density_lod_camera()
    if camera == null:
        return

    var camera_pos_local := to_local(camera.global_position)

    for chunk_coords in _chunk_render_lods.keys():
        var chunk_node: Node3D = _active_chunks.get(chunk_coords)
        if not is_instance_valid(chunk_node):
            continue

        var chunk_lod_list: Array = _chunk_render_lods[chunk_coords]
        var distance := camera_pos_local.distance_to(chunk_node.global_position)
        var fraction := _compute_density_lod_fraction(distance)

        for chunk_data in chunk_lod_list:
            var full_count: int = chunk_data["full_count"]
            var visible_count := full_count
            if density_lod_enabled:
                visible_count = clampi(int(round(float(full_count) * fraction)), 0, full_count)

            if visible_count == chunk_data["visible_count"]:
                continue

            chunk_data["visible_count"] = visible_count
            var render_nodes: Array = chunk_data["render_nodes"]
            for render_node in render_nodes:
                if not is_instance_valid(render_node):
                    continue
                var geometry := render_node as MultiMeshInstance3D
                if geometry == null or geometry.multimesh == null:
                    continue
                geometry.multimesh.visible_instance_count = visible_count


func _update_all_shadow_casting() -> void:
    var target_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    if _last_high_quality_foliage:
        target_shadows = shadow_casting as GeometryInstance3D.ShadowCastingSetting

    var generated_root = get_node_or_null(GENERATED_ROOT_NAME)
    if generated_root == null:
        return

    for chunk in generated_root.get_children():
        for child in chunk.get_children():
            if child is MultiMeshInstance3D:
                child.cast_shadow = target_shadows


func _compute_density_lod_fraction(distance: float) -> float:
    var min_fraction := clampf(density_lod_min_fraction, 0.0, 1.0)
    var start_distance := density_lod_start_distance
    var end_distance := density_lod_end_distance
    if end_distance <= start_distance:
        return min_fraction if distance > start_distance else 1.0
    if distance <= start_distance:
        return 1.0
    if distance >= end_distance:
        return min_fraction

    var t := inverse_lerp(start_distance, end_distance, distance)
    var smooth_t := t * t * (3.0 - 2.0 * t)
    return lerpf(1.0, min_fraction, smooth_t)


func _get_density_lod_camera() -> Camera3D:
    if Engine.is_editor_hint():
        # W edytorze próbujemy dobrać się do kamery 3D aktywnego viewportu
        var editor_viewport := EditorInterface.get_editor_viewport_3d(0)
        if editor_viewport != null:
            return editor_viewport.get_camera_3d()

    var viewport := get_viewport()
    if viewport == null:
        return null
    return viewport.get_camera_3d()


func _hash01(a: int, b: int, c: int, salt: int) -> float:
    var value := (int(a) ^ (int(b) * 374761393) ^ (int(c) * 668265263) ^ (int(salt) * 2246822519)) & HASH_MASK
    value = (value ^ (value >> 13)) & HASH_MASK
    value = (value * 1274126177) & HASH_MASK
    value = (value ^ (value >> 16)) & HASH_MASK
    return float(value) / float(HASH_MASK)
