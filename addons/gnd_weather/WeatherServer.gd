class_name WeatherServer
extends RefCounted

static var _rain_volumes_by_world: Dictionary = {}
static var _visible_rain_probe_fields_by_world: Dictionary = {}


static func add_rain_volume(world_3d: World3D, volume_rid: RID, volume: RainVolume) -> void:
	if world_3d == null or not volume_rid.is_valid() or volume == null:
		return

	var world_id := world_3d.get_instance_id()
	var world_bucket: Dictionary = _rain_volumes_by_world.get(world_id, {})
	world_bucket[volume_rid.get_id()] = volume
	_rain_volumes_by_world[world_id] = world_bucket


static func remove_rain_volume(world_3d: World3D, volume_rid: RID) -> void:
	if world_3d == null or not volume_rid.is_valid():
		return

	var world_id := world_3d.get_instance_id()
	var world_bucket: Dictionary = _rain_volumes_by_world.get(world_id, {})
	if world_bucket.is_empty():
		return

	world_bucket.erase(volume_rid.get_id())
	if world_bucket.is_empty():
		_rain_volumes_by_world.erase(world_id)
	else:
		_rain_volumes_by_world[world_id] = world_bucket


static func get_rain_participation_strength(
	world_3d: World3D,
	world_position: Vector3,
	base_strength: float
) -> float:
	return get_rain_participation_strength_for_volumes(
		_collect_rain_volumes_at_position(world_3d, world_position),
		world_position,
		base_strength
	)


static func get_rain_participation_strength_for_volumes(
	volumes: Array,
	world_position: Vector3,
	base_strength: float
) -> float:
	var intensity: float = clampf(base_strength, 0.0, 1.0)
	for volume in _sort_rain_volumes(volumes):
		var blend: float = volume.get_precipitation_blend(world_position)
		if blend <= 0.0:
			continue

		var precipitation_delta: float = volume.get_precipitation_delta() * blend
		var precipitation_multiplier: float = lerpf(1.0, volume.get_precipitation_multiplier(), blend)
		intensity = clampf((intensity + precipitation_delta) * precipitation_multiplier, 0.0, 1.0)
	return intensity


static func get_visible_rain_participation_strength(
	world_3d: World3D,
	cache_key: int,
	view_transform: Transform3D,
	camera: Camera3D,
	base_strength: float,
	probe_columns: int,
	probe_rows: int,
	probe_depth_slices: int,
	near_depth: float,
	far_depth: float,
	field_scale: float,
	refresh_budget: int
) -> float:
	var state: Dictionary = get_visible_rain_probe_field_state(
		world_3d,
		cache_key,
		view_transform,
		camera,
		base_strength,
		probe_columns,
		probe_rows,
		probe_depth_slices,
		near_depth,
		far_depth,
		field_scale,
		refresh_budget
	)
	return float(state.get("strength", 0.0))


static func get_visible_rain_probe_field_state(
	world_3d: World3D,
	cache_key: int,
	view_transform: Transform3D,
	camera: Camera3D,
	base_strength: float,
	probe_columns: int,
	probe_rows: int,
	probe_depth_slices: int,
	near_depth: float,
	far_depth: float,
	field_scale: float,
	refresh_budget: int
) -> Dictionary:
	if world_3d == null or cache_key < 0:
		return {
			"strength": 0.0,
			"nearest_depth": 0.0,
			"has_visible_rain": false,
		}

	var clamped_strength: float = clampf(base_strength, 0.0, 1.0)
	if clamped_strength <= 0.001:
		clear_visible_rain_participation_cache(world_3d, cache_key)
		return {
			"strength": 0.0,
			"nearest_depth": 0.0,
			"has_visible_rain": false,
		}

	var columns: int = maxi(probe_columns, 1)
	var rows: int = maxi(probe_rows, 1)
	var depth_slices: int = maxi(probe_depth_slices, 1)
	var probe_count: int = columns * rows * depth_slices
	var budget: int = clampi(refresh_budget, 1, probe_count)
	var cache: Dictionary = _ensure_visible_rain_probe_field_cache(world_3d, cache_key, probe_count)
	var values: PackedFloat32Array = cache.get("values", PackedFloat32Array())
	var cursor: int = int(cache.get("cursor", 0))
	var ready: bool = bool(cache.get("ready", false))

	if not ready:
		budget = probe_count

	for offset in range(budget):
		var probe_index: int = (cursor + offset) % probe_count
		var probe_position: Vector3 = _get_visible_rain_probe_world_position(
			view_transform,
			camera,
			columns,
			rows,
			depth_slices,
			near_depth,
			far_depth,
			field_scale,
			probe_index
		)
		values[probe_index] = get_rain_participation_strength(world_3d, probe_position, clamped_strength)

	cache["values"] = values
	cache["cursor"] = (cursor + budget) % probe_count
	cache["ready"] = true
	_store_visible_rain_probe_field_cache(world_3d, cache_key, cache)
	return _get_visible_rain_probe_field_state(
		values,
		columns * rows,
		depth_slices,
		near_depth,
		far_depth
	)


static func get_visible_rain_probe_positions(
	view_transform: Transform3D,
	camera: Camera3D,
	probe_columns: int,
	probe_rows: int,
	probe_depth_slices: int,
	near_depth: float,
	far_depth: float,
	field_scale: float
) -> PackedVector3Array:
	var columns: int = maxi(probe_columns, 1)
	var rows: int = maxi(probe_rows, 1)
	var depth_slices: int = maxi(probe_depth_slices, 1)
	var probe_count: int = columns * rows * depth_slices
	var positions := PackedVector3Array()
	positions.resize(probe_count)

	for probe_index in range(probe_count):
		positions[probe_index] = _get_visible_rain_probe_world_position(
			view_transform,
			camera,
			columns,
			rows,
			depth_slices,
			near_depth,
			far_depth,
			field_scale,
			probe_index
		)

	return positions


static func clear_visible_rain_participation_cache(world_3d: World3D, cache_key: int) -> void:
	if world_3d == null or cache_key < 0:
		return

	var world_id: int = world_3d.get_instance_id()
	var world_fields: Dictionary = _visible_rain_probe_fields_by_world.get(world_id, {})
	if world_fields.is_empty():
		return

	world_fields.erase(cache_key)
	if world_fields.is_empty():
		_visible_rain_probe_fields_by_world.erase(world_id)
	else:
		_visible_rain_probe_fields_by_world[world_id] = world_fields


static func _collect_rain_volumes_at_position(world_3d: World3D, world_position: Vector3) -> Array:
	if world_3d == null:
		return []

	var world_bucket: Dictionary = _rain_volumes_by_world.get(world_3d.get_instance_id(), {})
	if world_bucket.is_empty():
		return []

	var stale_ids: Array[int] = []
	var volumes: Array = []
	for volume_id in world_bucket.keys():
		var volume := world_bucket[volume_id] as RainVolume
		if not is_instance_valid(volume):
			stale_ids.append(volume_id)
			continue
		if not volume.is_inside_tree() or volume.get_world_3d() != world_3d:
			stale_ids.append(volume_id)
			continue
		if not volume.is_rain_volume_enabled():
			continue
		if volume.get_precipitation_blend(world_position) > 0.0:
			volumes.append(volume)

	if not stale_ids.is_empty():
		for volume_id in stale_ids:
			world_bucket.erase(volume_id)
		if world_bucket.is_empty():
			_rain_volumes_by_world.erase(world_3d.get_instance_id())
		else:
			_rain_volumes_by_world[world_3d.get_instance_id()] = world_bucket

	return _sort_rain_volumes(volumes)


static func _sort_rain_volumes(volumes: Array) -> Array:
	var sorted_volumes: Array = []
	for volume in volumes:
		var rain_volume := volume as RainVolume
		if rain_volume == null:
			continue
		if not is_instance_valid(rain_volume):
			continue
		if not rain_volume.is_rain_volume_enabled():
			continue
		sorted_volumes.append(rain_volume)

	sorted_volumes.sort_custom(func(a: RainVolume, b: RainVolume) -> bool:
		if a.volume_priority == b.volume_priority:
			return a.get_instance_id() < b.get_instance_id()
		return a.volume_priority < b.volume_priority
	)
	return sorted_volumes


static func _ensure_visible_rain_probe_field_cache(world_3d: World3D, cache_key: int, probe_count: int) -> Dictionary:
	var world_id: int = world_3d.get_instance_id()
	var world_fields: Dictionary = _visible_rain_probe_fields_by_world.get(world_id, {})
	var cache: Dictionary = world_fields.get(cache_key, {})
	var current_count: int = int(cache.get("count", -1))
	var values: PackedFloat32Array = cache.get("values", PackedFloat32Array())

	if current_count != probe_count or values.size() != probe_count:
		values = PackedFloat32Array()
		values.resize(probe_count)
		cache = {
			"count": probe_count,
			"cursor": 0,
			"ready": false,
			"values": values,
		}
		world_fields[cache_key] = cache
		_visible_rain_probe_fields_by_world[world_id] = world_fields

	return cache


static func _store_visible_rain_probe_field_cache(world_3d: World3D, cache_key: int, cache: Dictionary) -> void:
	var world_id: int = world_3d.get_instance_id()
	var world_fields: Dictionary = _visible_rain_probe_fields_by_world.get(world_id, {})
	world_fields[cache_key] = cache
	_visible_rain_probe_fields_by_world[world_id] = world_fields


static func _get_visible_rain_probe_world_position(
	view_transform: Transform3D,
	camera: Camera3D,
	probe_columns: int,
	probe_rows: int,
	probe_depth_slices: int,
	near_depth: float,
	far_depth: float,
	field_scale: float,
	probe_index: int
) -> Vector3:
	var slice_index: int = probe_index / (probe_columns * probe_rows)
	var plane_index: int = probe_index % (probe_columns * probe_rows)
	var row_index: int = plane_index / probe_columns
	var column_index: int = plane_index % probe_columns

	var depth_t: float = 0.0 if probe_depth_slices <= 1 else float(slice_index) / float(probe_depth_slices - 1)
	var depth: float = lerpf(maxf(near_depth, 0.1), maxf(far_depth, near_depth), depth_t)
	var u: float = 0.0 if probe_columns <= 1 else lerpf(-1.0, 1.0, float(column_index) / float(probe_columns - 1))
	var v: float = 0.0 if probe_rows <= 1 else lerpf(1.0, -1.0, float(row_index) / float(probe_rows - 1))

	var half_extents: Vector2 = _get_visible_rain_probe_half_extents(camera, depth, field_scale)
	var forward: Vector3 = -view_transform.basis.z
	var right: Vector3 = view_transform.basis.x
	var up: Vector3 = view_transform.basis.y
	return (
		view_transform.origin
		+ forward * depth
		+ right * (u * half_extents.x)
		+ up * (v * half_extents.y)
	)


static func _get_visible_rain_probe_half_extents(camera: Camera3D, depth: float, field_scale: float) -> Vector2:
	var aspect: float = 16.0 / 9.0
	if camera != null:
		var viewport := camera.get_viewport()
		if viewport != null:
			var visible_rect: Rect2 = viewport.get_visible_rect()
			if visible_rect.size.y > 0.0:
				aspect = visible_rect.size.x / visible_rect.size.y

	var half_height: float
	if camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		half_height = camera.size * 0.5
	else:
		var vertical_fov: float = 70.0 if camera == null else camera.fov
		half_height = tan(deg_to_rad(vertical_fov) * 0.5) * depth

	half_height *= maxf(field_scale, 0.01)
	var half_width: float = half_height * aspect
	return Vector2(half_width, half_height)


static func _get_visible_rain_probe_field_max(values: PackedFloat32Array) -> float:
	var visible_intensity: float = 0.0
	for value in values:
		visible_intensity = maxf(visible_intensity, value)
	return visible_intensity


static func _get_visible_rain_probe_field_state(
	values: PackedFloat32Array,
	plane_probe_count: int,
	probe_depth_slices: int,
	near_depth: float,
	far_depth: float
) -> Dictionary:
	var visible_intensity: float = 0.0
	var nearest_visible_depth: float = 0.0
	var has_visible_rain: bool = false

	for probe_index in range(values.size()):
		var value: float = values[probe_index]
		if value <= 0.001:
			continue

		visible_intensity = maxf(visible_intensity, value)
		var depth: float = _get_visible_rain_probe_depth(
			plane_probe_count,
			probe_depth_slices,
			near_depth,
			far_depth,
			probe_index
		)
		if not has_visible_rain or depth < nearest_visible_depth:
			nearest_visible_depth = depth
			has_visible_rain = true

	return {
		"strength": visible_intensity,
		"nearest_depth": nearest_visible_depth,
		"has_visible_rain": has_visible_rain,
	}


static func _get_visible_rain_probe_depth(
	plane_probe_count: int,
	probe_depth_slices: int,
	near_depth: float,
	far_depth: float,
	probe_index: int
) -> float:
	var safe_plane_probe_count: int = maxi(plane_probe_count, 1)
	var safe_depth_slices: int = maxi(probe_depth_slices, 1)
	var slice_index: int = 0 if safe_depth_slices <= 1 else probe_index / safe_plane_probe_count
	slice_index = clampi(slice_index, 0, safe_depth_slices - 1)
	var depth_t: float = 0.0 if safe_depth_slices <= 1 else float(slice_index) / float(safe_depth_slices - 1)
	return lerpf(maxf(near_depth, 0.1), maxf(far_depth, near_depth), depth_t)
