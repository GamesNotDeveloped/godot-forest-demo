@tool
class_name RainVolumeGizmoPlugin
extends EditorNode3DGizmoPlugin

const HANDLE_NAMES := [
    "-X",
    "+X",
    "-Y",
    "+Y",
    "-Z",
    "+Z",
]

const HANDLE_AXES := [
    Vector3.RIGHT,
    Vector3.RIGHT,
    Vector3.UP,
    Vector3.UP,
    Vector3.BACK,
    Vector3.BACK,
]

const HANDLE_SIGNS := [-1.0, 1.0, -1.0, 1.0, -1.0, 1.0]

const LINE_MATERIAL_NAME := "rain_volume_lines"
const HANDLE_MATERIAL_NAME := "rain_volume_handles"

var undo_redo: EditorUndoRedoManager


func _init() -> void:
    create_material(LINE_MATERIAL_NAME, Color(0.42, 0.76, 1.0, 0.85), false, true)
    create_handle_material(HANDLE_MATERIAL_NAME, false)


func _get_gizmo_name() -> String:
    return "RainVolume"


func _has_gizmo(for_node_3d: Node3D) -> bool:
    return for_node_3d is RainVolume


func _redraw(gizmo: EditorNode3DGizmo) -> void:
    gizmo.clear()

    var rain_volume := gizmo.get_node_3d() as RainVolume
    if rain_volume == null:
        return

    var half_size := rain_volume.size * 0.5
    var corners := [
        Vector3(-half_size.x, -half_size.y, -half_size.z),
        Vector3(half_size.x, -half_size.y, -half_size.z),
        Vector3(half_size.x, half_size.y, -half_size.z),
        Vector3(-half_size.x, half_size.y, -half_size.z),
        Vector3(-half_size.x, -half_size.y, half_size.z),
        Vector3(half_size.x, -half_size.y, half_size.z),
        Vector3(half_size.x, half_size.y, half_size.z),
        Vector3(-half_size.x, half_size.y, half_size.z),
    ]
    var edge_pairs := [
        [0, 1], [1, 2], [2, 3], [3, 0],
        [4, 5], [5, 6], [6, 7], [7, 4],
        [0, 4], [1, 5], [2, 6], [3, 7],
    ]

    var lines := PackedVector3Array()
    for pair in edge_pairs:
        lines.append(corners[pair[0]])
        lines.append(corners[pair[1]])

    var handles := PackedVector3Array([
        Vector3(-half_size.x, 0.0, 0.0),
        Vector3(half_size.x, 0.0, 0.0),
        Vector3(0.0, -half_size.y, 0.0),
        Vector3(0.0, half_size.y, 0.0),
        Vector3(0.0, 0.0, -half_size.z),
        Vector3(0.0, 0.0, half_size.z),
    ])
    var handle_ids := PackedInt32Array([0, 1, 2, 3, 4, 5])

    gizmo.add_lines(lines, get_material(LINE_MATERIAL_NAME, gizmo), false)
    gizmo.add_collision_segments(lines)
    gizmo.add_handles(handles, get_material(HANDLE_MATERIAL_NAME, gizmo), handle_ids, false)


func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
    if handle_id < 0 or handle_id >= HANDLE_NAMES.size():
        return ""
    return HANDLE_NAMES[handle_id]


func _get_handle_value(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> Variant:
    var rain_volume := gizmo.get_node_3d() as RainVolume
    if rain_volume == null:
        return {}
    return {
        "size": rain_volume.size,
        "position": rain_volume.position,
    }


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
    var rain_volume := gizmo.get_node_3d() as RainVolume
    if rain_volume == null or handle_id < 0 or handle_id >= HANDLE_AXES.size():
        return

    var axis_local: Vector3 = HANDLE_AXES[handle_id]
    var sign: float = HANDLE_SIGNS[handle_id]
    var axis_world: Vector3 = (rain_volume.global_transform.basis * axis_local).normalized()
    if axis_world.length_squared() <= 0.0001:
        return

    var center_world := rain_volume.global_transform.origin
    var axis_extent := maxf(rain_volume.size.length() * 4.0, 8.0)
    var ray_origin := camera.project_ray_origin(screen_pos)
    var ray_direction := camera.project_ray_normal(screen_pos)
    var closest_points := Geometry3D.get_closest_points_between_segments(
        center_world - axis_world * axis_extent,
        center_world + axis_world * axis_extent,
        ray_origin,
        ray_origin + ray_direction * 4096.0
    )
    if closest_points.size() < 2:
        return

    var local_point: Vector3 = rain_volume.global_transform.affine_inverse() * closest_points[0]
    var distance_along_axis: float = axis_local.dot(local_point)
    var target_half_extent: float = maxf(distance_along_axis * sign, 0.05)
    var new_size: Vector3 = rain_volume.size
    var axis_index: int = handle_id / 2
    var current_half_extent: float = rain_volume.size[axis_index] * 0.5
    var face_delta: float = target_half_extent - current_half_extent
    var min_full_extent := 0.1
    face_delta = maxf(face_delta, min_full_extent - rain_volume.size[axis_index])
    new_size[axis_index] = rain_volume.size[axis_index] + face_delta

    var local_center_offset: Vector3 = axis_local * (sign * face_delta * 0.5)
    var new_position: Vector3 = rain_volume.position + rain_volume.transform.basis * local_center_offset

    rain_volume.size = new_size
    rain_volume.position = new_position


func _commit_handle(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
    var rain_volume := gizmo.get_node_3d() as RainVolume
    if rain_volume == null or typeof(restore) != TYPE_DICTIONARY:
        return

    var restore_size: Vector3 = restore.get("size", rain_volume.size)
    var restore_position: Vector3 = restore.get("position", rain_volume.position)
    if cancel:
        rain_volume.size = restore_size
        rain_volume.position = restore_position
        return

    if undo_redo == null:
        return
    undo_redo.create_action("Resize RainVolume")
    undo_redo.add_do_property(rain_volume, "size", rain_volume.size)
    undo_redo.add_do_property(rain_volume, "position", rain_volume.position)
    undo_redo.add_undo_property(rain_volume, "size", restore_size)
    undo_redo.add_undo_property(rain_volume, "position", restore_position)
    undo_redo.commit_action()
