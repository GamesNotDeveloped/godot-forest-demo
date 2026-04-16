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
var _generated_chunk_render_lods: Array[Dictionary] = []

@export_group("Generator")
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
    var high_quality = RenderingServer.global_shader_parameter_get(&"gnd_high_quality_foliage")
    if high_quality != _last_high_quality_foliage:
        _last_high_quality_foliage = high_quality
        _update_all_shadow_casting()

    if Engine.is_editor_hint():
        if editor_auto_regenerate:
            var next_signature := _build_editor_state_signature()
            if next_signature != _editor_state_signature:
                _editor_state_signature = next_signature
                _queue_regenerate()

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
    _generated_chunk_render_lods.clear()
    var world := get_world_3d()
    if world == null:
        return

    var resolved_entries := _resolve_entries()
    if resolved_entries.is_empty():
        return

    var direction := ray_direction
    if direction.is_zero_approx():
        direction = Vector3.DOWN
    direction = direction.normalized()

    var half_area := area_size * 0.5
    var area_m2 := maxf(area_size.x * area_size.y, 0.0)
    if area_m2 <= 0.0:
        return

    var generation_min_x := -half_area.x
    var generation_max_x := half_area.x
    var generation_min_z := -half_area.y
    var generation_max_z := half_area.y
    var effective_area_m2 := area_m2
    if mask_enabled and mask_texture != null:
        var mask_image := _get_mask_image()
        if mask_image != null and not mask_image.is_empty():
            var mask_region := _analyze_mask_generation_region(mask_image)
            if not bool(mask_region["has_active"]):
                return
            generation_min_x = float(mask_region["min_x"])
            generation_max_x = float(mask_region["max_x"])
            generation_min_z = float(mask_region["min_z"])
            generation_max_z = float(mask_region["max_z"])
            effective_area_m2 = maxf(float(mask_region["weighted_area_m2"]), 0.0001)

    var spacing := maxf(average_spacing, 0.1)
    if max_instances > 0:
        spacing = maxf(spacing, sqrt(effective_area_m2 / float(max_instances)))

    var effective_density := 1.0 / (spacing * spacing)
    if effective_density <= 0.0:
        return

    var cell_size := 1.0 / sqrt(effective_density)
    var state := world.direct_space_state
    var chunk_transforms: Dictionary = {}
    var chunk_collision_buckets: Dictionary = {}

    var min_cell_x := int(floor(generation_min_x / cell_size))
    var max_cell_x := int(ceil(generation_max_x / cell_size))
    var min_cell_z := int(floor(generation_min_z / cell_size))
    var max_cell_z := int(ceil(generation_max_z / cell_size))

    for cell_x in range(min_cell_x, max_cell_x):
        for cell_z in range(min_cell_z, max_cell_z):
            var local_x := (float(cell_x) + _hash01(seed, cell_x, cell_z, 11)) * cell_size
            var local_z := (float(cell_z) + _hash01(seed, cell_x, cell_z, 17)) * cell_size
            if local_x < generation_min_x or local_x > generation_max_x or local_z < generation_min_z or local_z > generation_max_z:
                continue
            var mask_density := _sample_mask_density_weight_from_local_position(Vector3(local_x, 0.0, local_z))
            if mask_density <= 0.0:
                continue
            if _hash01(seed, cell_x, cell_z, 7) > mask_density:
                continue

            var resolved_entry: Dictionary = _pick_entry(resolved_entries, cell_x, cell_z)
            if resolved_entry.is_empty():
                continue

            var lod_priority := _hash01(seed, cell_x, cell_z, 53)
            var local_hit: Variant = _raycast_to_surface(state, Vector3(local_x, 0.0, local_z), direction)
            var hit_position := Vector3(local_x, 0.0, local_z)
            if local_hit != null:
                hit_position = local_hit as Vector3

            var scale_min_value: Vector3 = resolved_entry["scale_min"]
            var scale_max_value: Vector3 = resolved_entry["scale_max"]
            var instance_scale := Vector3(
                lerpf(minf(scale_min_value.x, scale_max_value.x), maxf(scale_min_value.x, scale_max_value.x), _hash01(seed, cell_x, cell_z, 23)),
                lerpf(minf(scale_min_value.y, scale_max_value.y), maxf(scale_min_value.y, scale_max_value.y), _hash01(seed, cell_x, cell_z, 29)),
                lerpf(minf(scale_min_value.z, scale_max_value.z), maxf(scale_min_value.z, scale_max_value.z), _hash01(seed, cell_x, cell_z, 31))
            )
            var yaw := TAU * _hash01(seed, cell_x, cell_z, 37)
            var basis := Basis.IDENTITY.rotated(Vector3.UP, yaw).scaled(instance_scale)
            var transform := Transform3D(basis, hit_position)
            var chunk_coords := Vector2i(
                int(floor(hit_position.x / chunk_size)),
                int(floor(hit_position.z / chunk_size))
            )
            var chunk_key := _chunk_key(chunk_coords, resolved_entry["index"])
            if not chunk_transforms.has(chunk_key):
                chunk_transforms[chunk_key] = {
                    "chunk_coords": chunk_coords,
                    "entry": resolved_entry,
                    "near": [],
                    "far": [],
                    "lod_priorities": []
                }
            var bucket: Dictionary = chunk_transforms[chunk_key]
            bucket["near"].append(transform)
            if not resolved_entry["billboard_parts"].is_empty():
                bucket["far"].append(transform)
            bucket["lod_priorities"].append(lod_priority)
            chunk_transforms[chunk_key] = bucket
            if generate_chunk_colliders and not resolved_entry["collision_parts"].is_empty():
                var collision_chunk_key := _chunk_coords_key(chunk_coords)
                if not chunk_collision_buckets.has(collision_chunk_key):
                    chunk_collision_buckets[collision_chunk_key] = {
                        "chunk_coords": chunk_coords,
                        "shapes": []
                    }
                var collision_bucket: Dictionary = chunk_collision_buckets[collision_chunk_key]
                for collision_part in resolved_entry["collision_parts"]:
                    collision_bucket["shapes"].append({
                        "shape": collision_part["shape"],
                        "transform": _sanitize_collision_transform(transform * collision_part["transform"])
                    })
                chunk_collision_buckets[collision_chunk_key] = collision_bucket

    _build_generated_nodes(chunk_transforms, chunk_collision_buckets)


func _build_generated_nodes(chunk_transforms: Dictionary, chunk_collision_buckets: Dictionary) -> void:
    if chunk_transforms.is_empty() and chunk_collision_buckets.is_empty():
        return

    var generated_root := _ensure_generated_root()
    var chunk_nodes: Dictionary = {}
    for bucket_value in chunk_transforms.values():
        var bucket: Dictionary = bucket_value
        var chunk_coords: Vector2i = bucket["chunk_coords"]
        var resolved_entry: Dictionary = bucket["entry"]
        var chunk_node := _ensure_chunk_node(generated_root, chunk_nodes, chunk_coords)
        var sorted_bucket := _sort_chunk_bucket_for_density_lod(bucket)

        var near_instances := _create_multimesh_instances(
            "near_%s" % resolved_entry["index"],
            resolved_entry["main_parts"],
            sorted_bucket["near"],
            chunk_node.position
        )
        for instance in near_instances:
            chunk_node.add_child(instance, false, INTERNAL_MODE_FRONT)

        if not resolved_entry["billboard_parts"].is_empty():
            var lod_distance: float = resolved_entry["billboard_lod_distance"]
            var far_instances := _create_multimesh_instances(
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

            _register_chunk_render_lod(chunk_node, near_instances, far_instances, sorted_bucket["near"].size())
        else:
            _register_chunk_render_lod(chunk_node, near_instances, [], sorted_bucket["near"].size())

    for collision_bucket_value in chunk_collision_buckets.values():
        var collision_bucket: Dictionary = collision_bucket_value
        var chunk_coords: Vector2i = collision_bucket["chunk_coords"]
        var chunk_node := _ensure_chunk_node(generated_root, chunk_nodes, chunk_coords)
        _build_chunk_collider(chunk_node, collision_bucket["shapes"])


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


func _register_chunk_render_lod(chunk_node: Node3D, near_instances: Array[MultiMeshInstance3D], far_instances: Array[MultiMeshInstance3D], full_count: int) -> void:
    if full_count <= 0:
        return

    var render_nodes: Array[GeometryInstance3D] = []
    for instance in near_instances:
        render_nodes.append(instance)
    for instance in far_instances:
        render_nodes.append(instance)

    if render_nodes.is_empty():
        return

    _generated_chunk_render_lods.append({
        "chunk_node": chunk_node,
        "full_count": full_count,
        "visible_count": full_count,
        "render_nodes": render_nodes
    })


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
    set_process(Engine.is_editor_hint() and editor_auto_regenerate)


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
    if _generated_chunk_render_lods.is_empty():
        return

    var camera := _get_density_lod_camera()
    if camera == null:
        _set_all_chunk_visible_counts_to_full()
        return

    for chunk_data in _generated_chunk_render_lods:
        var chunk_node: Node3D = chunk_data["chunk_node"]
        if not is_instance_valid(chunk_node):
            continue

        var full_count: int = chunk_data["full_count"]
        var visible_count := full_count
        if density_lod_enabled:
            var distance := camera.global_position.distance_to(chunk_node.global_position)
            var fraction := _compute_density_lod_fraction(distance)
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


func _set_all_chunk_visible_counts_to_full() -> void:
    for chunk_data in _generated_chunk_render_lods:
        var full_count: int = chunk_data["full_count"]
        if chunk_data["visible_count"] == full_count:
            continue

        chunk_data["visible_count"] = full_count
        var render_nodes: Array = chunk_data["render_nodes"]
        for render_node in render_nodes:
            if not is_instance_valid(render_node):
                continue
            var geometry := render_node as MultiMeshInstance3D
            if geometry == null or geometry.multimesh == null:
                continue
            geometry.multimesh.visible_instance_count = full_count


func _get_density_lod_camera() -> Camera3D:
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
