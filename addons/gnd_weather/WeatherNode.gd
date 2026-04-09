class_name WeatherNode
extends Node3D

signal thunder(strength: float)
signal rain_strength_changed(strength: float)
signal rain_local_strength_changed(strength: float)

const RAIN_STREAK_SHADER := preload("res://scenery/shaders/rain_streak.gdshader")
const NEAR_PARTICLES_NAME := "RainNear"
const MID_PARTICLES_NAME := "RainMid"

@export_group("Nodes")
@export_node_path("Skydome") var skydome_path: NodePath
@export_node_path("WorldEnvironment") var world_environment_path: NodePath:
	set(value):
		world_environment_path = value
		if is_inside_tree():
			_refresh_environment_cache()

@export_group("Weather")
@export_range(0.0, 1.0, 0.001) var precipitation_intensity: float = 0.0:
	set(value):
		precipitation_intensity = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_apply_weather_state()
@export_range(0.0, 1.0, 0.001) var storm_threshold: float = 0.82:
	set(value):
		storm_threshold = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_apply_weather_state()

@export_group("Wind")
@export var use_global_wind: bool = true
@export var wind_direction_project_setting: StringName = &"shader_globals/gnd_wind_direction/value"
@export var wind_speed_project_setting: StringName = &"shader_globals/gnd_wind_speed/value"
@export var wind_direction: Vector2 = Vector2(0.8, 0.3)
@export_range(0.0, 8.0, 0.01) var wind_speed: float = 1.0
@export_range(0.0, 1.0, 0.01) var wind_influence: float = 0.35

@export_group("Rain")
@export var follow_height: float = 7.5
@export var near_emission_extents: Vector3 = Vector3(4.6, 3.0, 4.6)
@export var mid_emission_extents: Vector3 = Vector3(4.2, 2.8, 4.2)
@export var near_particle_amount: int = 4200
@export var mid_particle_amount: int = 2200
@export_range(0.1, 6.0, 0.05) var density_multiplier: float = 1.2
@export_range(1.0, 80.0, 0.1) var base_fall_speed: float = 26.0
@export_range(0.1, 4.0, 0.01) var near_layer_speed_multiplier: float = 1.0
@export_range(0.1, 4.0, 0.01) var mid_layer_speed_multiplier: float = 0.78
@export var mid_layer_enabled: bool = true
@export var mid_layer_offset: Vector3 = Vector3(1.6, -0.9, 2.8)
@export_range(0.0, 24.0, 0.1) var sheltered_mid_layer_forward_offset: float = 6.0
@export_range(0.0, 1.0, 0.01) var sheltered_mid_layer_density_scale: float = 0.08
@export_range(0.0, 1.0, 0.01) var sheltered_mid_layer_alpha_scale: float = 0.12
@export_range(0.0, 1.0, 0.01) var sheltered_volumetric_emission_scale: float = 0.0
@export var near_rain_color: Color = Color(0.72, 0.74, 0.76, 0.08):
	set(value):
		near_rain_color = value
		_sync_rain_materials()
@export var mid_rain_color: Color = Color(0.66, 0.68, 0.72, 0.055):
	set(value):
		mid_rain_color = value
		_sync_rain_materials()

@export_group("Rain Visibility")
@export_range(1, 7, 1) var visible_rain_probe_columns: int = 3
@export_range(1, 7, 1) var visible_rain_probe_rows: int = 3
@export_range(1, 4, 1) var visible_rain_probe_depth_slices: int = 2
@export_range(0.1, 24.0, 0.1) var visible_rain_probe_near_depth: float = 0.8
@export_range(0.1, 48.0, 0.1) var visible_rain_probe_far_depth: float = 8.0
@export_range(0.1, 3.0, 0.01) var visible_rain_probe_field_scale: float = 1.0
@export_range(1, 32, 1) var visible_rain_probe_refresh_budget: int = 6

@export_group("Storm")
@export var lightning_enabled: bool = true
@export_range(0.1, 30.0, 0.1) var lightning_min_interval: float = 3.2
@export_range(0.1, 30.0, 0.1) var lightning_max_interval: float = 9.5
@export_range(0.1, 20.0, 0.01) var lightning_flash_decay: float = 4.8

var _rng := RandomNumberGenerator.new()
var _near_particles: GPUParticles3D
var _mid_particles: GPUParticles3D
var _near_process_material: ParticleProcessMaterial
var _mid_process_material: ParticleProcessMaterial
var _environment: Environment
var _current_shelter_factor: float = 0.0

var _current_lightning_flash: float = 0.0
var _pending_flash_pulses: int = 0
var _next_flash_delay: float = 0.0
var _next_lightning_burst: float = 0.0

var _last_applied_precipitation: float = -1.0
var _last_applied_storm_factor: float = -1.0
var _last_applied_lightning_flash: float = -1.0
var _last_applied_local_emission_scale: float = -1.0
var _last_emitted_rain_strength: float = -1.0
var _last_emitted_local_rain_strength: float = -1.0


func _ready() -> void:
	_rng.randomize()
	_refresh_environment_cache()
	_ensure_particle_nodes()
	_reset_lightning_schedule(get_storm_factor())
	_apply_weather_state(true)
	set_process(true)


func _exit_tree() -> void:
	WeatherServer.clear_visible_rain_participation_cache(get_world_3d(), get_instance_id())
	var skydome := _get_skydome()
	if skydome != null:
		skydome.clear_weather_overrides()


func _process(delta: float) -> void:
	_update_follow_position()
	_update_lightning(delta)
	_update_particles()
	_push_weather_state()


func set_precipitation_intensity(value: float) -> void:
	precipitation_intensity = value


func apply_now() -> void:
	_apply_weather_state(true)


func get_effective_precipitation_intensity() -> float:
	var follow_target := _get_follow_target()
	if follow_target == null:
		return clampf(precipitation_intensity, 0.0, 1.0)
	return get_precipitation_strength_at_position(follow_target.global_position)


func get_precipitation_strength_at_position(world_position: Vector3) -> float:
	return WeatherServer.get_rain_participation_strength(
		get_world_3d(),
		world_position,
		precipitation_intensity
	)


func get_storm_factor(precipitation_override: float = -1.0) -> float:
	var intensity := precipitation_override
	if intensity < 0.0:
		intensity = precipitation_intensity

	if intensity <= storm_threshold:
		return 0.0

	var denominator := maxf(1.0 - storm_threshold, 0.0001)
	var t := clampf((intensity - storm_threshold) / denominator, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _apply_weather_state(force: bool = false) -> void:
	_ensure_particle_nodes()
	_update_follow_position()
	if get_storm_factor() > 0.02 and _pending_flash_pulses == 0 and _next_lightning_burst <= 0.0:
		_reset_lightning_schedule(get_storm_factor())
	_update_particles()
	_push_weather_state(force)


func _get_skydome() -> Skydome:
	if not skydome_path.is_empty():
		return get_node_or_null(skydome_path) as Skydome

	var root := get_tree().current_scene
	if root != null:
		return root.find_child("Skydome", true, false) as Skydome
	return null


func _get_world_environment() -> WorldEnvironment:
	if not world_environment_path.is_empty():
		return get_node_or_null(world_environment_path) as WorldEnvironment

	return null


func _get_environment() -> Environment:
	return _environment


func _refresh_environment_cache() -> void:
	var env_node := _get_world_environment()
	if env_node != null:
		_environment = env_node.environment
		return

	var world_3d := get_world_3d()
	_environment = world_3d.environment if world_3d != null else null


func _get_follow_target() -> Node3D:
	var viewport := get_viewport()
	if viewport != null:
		var camera := viewport.get_camera_3d()
		if camera != null:
			return camera
	return null


func _ensure_particle_nodes() -> void:
	if _near_particles == null:
		_near_particles = get_node_or_null(NEAR_PARTICLES_NAME) as GPUParticles3D
	if _near_particles == null:
		_near_particles = _build_rain_particles(NEAR_PARTICLES_NAME, near_emission_extents, near_rain_color, Vector2(0.01, 0.42), 0.72)
		add_child(_near_particles)
	_near_process_material = _near_particles.process_material as ParticleProcessMaterial

	if _mid_particles == null:
		_mid_particles = get_node_or_null(MID_PARTICLES_NAME) as GPUParticles3D
	if _mid_particles == null:
		_mid_particles = _build_rain_particles(MID_PARTICLES_NAME, mid_emission_extents, mid_rain_color, Vector2(0.009, 0.38), 0.86)
		add_child(_mid_particles)
	_mid_process_material = _mid_particles.process_material as ParticleProcessMaterial
	_sync_rain_materials()


func _build_rain_particles(name: String, extents: Vector3, tint: Color, mesh_size: Vector2, lifetime: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = name
	particles.local_coords = false
	particles.amount = 32
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.explosiveness = 0.0
	particles.randomness = 0.15
	particles.fixed_fps = 30
	particles.draw_passes = 1
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(-extents - Vector3(8.0, 10.0, 8.0), extents * 2.0 + Vector3(16.0, 20.0, 16.0))

	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = extents
	process_material.spread = 3.0
	process_material.gravity = Vector3.ZERO
	process_material.initial_velocity_min = base_fall_speed * 0.85
	process_material.initial_velocity_max = base_fall_speed * 1.15
	process_material.scale_min = 0.85
	process_material.scale_max = 1.25
	process_material.color = Color.WHITE
	particles.process_material = process_material

	var quad := QuadMesh.new()
	quad.size = mesh_size

	var material := ShaderMaterial.new()
	material.shader = RAIN_STREAK_SHADER
	material.set_shader_parameter("tint", tint)
	quad.material = material

	particles.draw_pass_1 = quad
	particles.emitting = false
	return particles


func _sync_rain_materials() -> void:
	_set_rain_particle_tint(_near_particles, near_rain_color)
	_set_rain_particle_tint(_mid_particles, mid_rain_color)


func _set_rain_particle_tint(particles: GPUParticles3D, tint: Color) -> void:
	if particles == null:
		return
	var mesh := particles.draw_pass_1 as QuadMesh
	if mesh == null:
		return
	var material := mesh.material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("tint", tint)


func _update_follow_position() -> void:
	var follow_target := _get_follow_target()
	if follow_target == null:
		return

	global_position = follow_target.global_position + Vector3(0.0, follow_height, 0.0)
func _update_particles() -> void:
	var follow_target := _get_follow_target()
	var global_intensity := clampf(precipitation_intensity, 0.0, 1.0)
	var local_intensity := get_effective_precipitation_intensity()
	_emit_rain_strength_changed(global_intensity)
	_emit_local_rain_strength_changed(local_intensity)
	_current_shelter_factor = 0.0
	if global_intensity > 0.001:
		_current_shelter_factor = clampf((global_intensity - local_intensity) / global_intensity, 0.0, 1.0)
	var visible_rain_state: Dictionary = _get_visible_mid_layer_state(follow_target, global_intensity, local_intensity)
	var mid_intensity: float = float(visible_rain_state.get("intensity", local_intensity))
	var visible_rain_intensity: float = float(visible_rain_state.get("visible_strength", 0.0))
	var mid_nearest_visible_depth: float = float(visible_rain_state.get("nearest_depth", 0.0))
	var mid_has_visible_rain: bool = bool(visible_rain_state.get("has_visible_rain", false))
	var near_intensity := _get_visible_near_layer_intensity(
		local_intensity,
		visible_rain_intensity,
		mid_has_visible_rain,
		mid_nearest_visible_depth
	)
	var near_storm_factor := get_storm_factor(near_intensity)
	var mid_storm_factor := get_storm_factor(mid_intensity)
	var mid_shelter_factor := 0.0
	if global_intensity > 0.001:
		mid_shelter_factor = clampf((global_intensity - mid_intensity) / global_intensity, 0.0, 1.0)
	var mid_density_scale := lerpf(1.0, sheltered_mid_layer_density_scale, mid_shelter_factor)
	var mid_alpha_scale := lerpf(1.0, sheltered_mid_layer_alpha_scale, mid_shelter_factor)
	var wind_speed_value := _get_wind_speed()
	var rain_direction := _get_rain_direction(wind_speed_value)
	_update_near_layer_offset(follow_target, mid_has_visible_rain, mid_nearest_visible_depth)
	_update_mid_layer_offset(follow_target, mid_has_visible_rain, mid_nearest_visible_depth)
	_orient_rain_layers(rain_direction)

	_update_rain_layer(
		_near_particles,
		_near_process_material,
		near_particle_amount,
		near_emission_extents,
		near_intensity,
		near_storm_factor,
		rain_direction,
		wind_speed_value,
		near_layer_speed_multiplier,
		near_intensity > 0.01,
		false,
		1.0,
		1.0
	)
	_update_rain_layer(
		_mid_particles,
		_mid_process_material,
		mid_particle_amount,
		mid_emission_extents,
		mid_intensity,
		mid_storm_factor,
		rain_direction,
		wind_speed_value,
		mid_layer_speed_multiplier,
		mid_layer_enabled and mid_intensity > 0.01,
		true,
		mid_density_scale,
		mid_alpha_scale
	)


func _update_rain_layer(
	particles: GPUParticles3D,
	process_material: ParticleProcessMaterial,
	base_amount: int,
	extents: Vector3,
	intensity: float,
	storm_factor: float,
	rain_direction: Vector3,
	wind_speed_value: float,
	speed_multiplier: float,
	rain_active: bool,
	is_mid_layer: bool,
	density_scale: float,
	alpha_scale: float
) -> void:
	if particles == null or process_material == null:
		return

	var was_emitting := particles.emitting
	var layer_intensity := _get_layer_intensity(intensity, is_mid_layer)
	var layer_active := rain_active and layer_intensity > 0.001

	particles.emitting = layer_active
	if not layer_active:
		if was_emitting:
			particles.restart()
		if is_mid_layer:
			particles.amount = 1
		return

	var safe_extents := Vector3(absf(extents.x), absf(extents.y), absf(extents.z))
	var density := clampf((0.04 + layer_intensity * 1.08 + storm_factor * 0.08) * density_multiplier, 0.0, 6.0)
	particles.amount = max(6 if not is_mid_layer else 4, int(round(base_amount * density * maxf(density_scale, 0.0))))

	process_material.emission_box_extents = safe_extents
	# Particle nodes are already oriented so their local +Y axis matches the rain fall axis.
	# Feeding world-space rain_direction here flips the actual travel direction.
	process_material.direction = Vector3.UP
	process_material.spread = lerpf(8.0, 2.0, clampf(layer_intensity + storm_factor * 0.12, 0.0, 1.0))
	particles.visibility_aabb = AABB(-safe_extents - Vector3(12.0, 14.0, 12.0), safe_extents * 2.0 + Vector3(24.0, 28.0, 24.0))

	var speed := base_fall_speed * speed_multiplier
	speed *= lerpf(0.64, 1.24, layer_intensity)
	speed *= 1.0 + minf(wind_speed_value, 6.0) * 0.08

	process_material.initial_velocity_min = speed * 0.85
	process_material.initial_velocity_max = speed * 1.15
	process_material.gravity = Vector3.UP * speed * 0.18
	process_material.scale_min = lerpf(0.28, 0.95, layer_intensity)
	process_material.scale_max = lerpf(0.42, 1.28, layer_intensity)

	_update_rain_visuals(particles, layer_intensity, is_mid_layer, alpha_scale)


func _get_rain_direction(wind_speed_value: float) -> Vector3:
	var wind_dir := _get_wind_direction()
	var lateral_strength := clampf(wind_speed_value * wind_influence * 0.22, 0.0, 0.82)
	return Vector3(wind_dir.x * lateral_strength, -1.0, wind_dir.y * lateral_strength).normalized()


func _get_layer_intensity(intensity: float, is_mid_layer: bool) -> float:
	if is_mid_layer:
		return _smooth_factor(intensity, 0.32, 0.92)
	return _smooth_factor(intensity, 0.04, 0.75)


func _get_visible_mid_layer_state(
	follow_target: Node3D,
	global_intensity: float,
	local_intensity: float
) -> Dictionary:
	if not mid_layer_enabled or global_intensity <= 0.001 or local_intensity >= global_intensity:
		return {
			"intensity": local_intensity,
			"nearest_depth": 0.0,
			"has_visible_rain": false,
		}

	var camera := follow_target as Camera3D
	var visible_state: Dictionary = WeatherServer.get_visible_rain_probe_field_state(
		get_world_3d(),
		get_instance_id(),
		follow_target.global_transform if follow_target != null else global_transform,
		camera,
		global_intensity,
		visible_rain_probe_columns,
		visible_rain_probe_rows,
		visible_rain_probe_depth_slices,
		visible_rain_probe_near_depth,
		visible_rain_probe_far_depth,
		visible_rain_probe_field_scale,
		visible_rain_probe_refresh_budget
	)
	var visible_intensity: float = float(visible_state.get("strength", 0.0))
	return {
		"intensity": clampf(maxf(local_intensity, visible_intensity), 0.0, 1.0),
		"visible_strength": visible_intensity,
		"nearest_depth": float(visible_state.get("nearest_depth", 0.0)),
		"has_visible_rain": bool(visible_state.get("has_visible_rain", false)),
	}


func _get_visible_near_layer_intensity(
	local_intensity: float,
	visible_intensity: float,
	has_visible_rain: bool,
	nearest_visible_depth: float
) -> float:
	var depth_blend := _get_sheltered_near_layer_visibility_blend(has_visible_rain, nearest_visible_depth)
	if depth_blend <= 0.001:
		return local_intensity
	return clampf(maxf(local_intensity, visible_intensity * depth_blend), 0.0, 1.0)


func _get_sheltered_near_layer_visibility_blend(has_visible_rain: bool, nearest_visible_depth: float) -> float:
	if _current_shelter_factor <= 0.001 or not has_visible_rain:
		return 0.0

	var start_depth: float = maxf(visible_rain_probe_near_depth, 0.1)
	var end_depth: float = start_depth + maxf(absf(near_emission_extents.z) * 0.35, 0.75)
	var depth_t: float = 1.0 - clampf(
		(nearest_visible_depth - start_depth) / maxf(end_depth - start_depth, 0.001),
		0.0,
		1.0
	)
	return depth_t * depth_t * (3.0 - 2.0 * depth_t)


func _emit_rain_strength_changed(strength: float) -> void:
	var clamped_strength := clampf(strength, 0.0, 1.0)
	if absf(_last_emitted_rain_strength - clamped_strength) <= 0.0001:
		return
	_last_emitted_rain_strength = clamped_strength
	rain_strength_changed.emit(clamped_strength)


func _emit_local_rain_strength_changed(strength: float) -> void:
	var clamped_strength := clampf(strength, 0.0, 1.0)
	if absf(_last_emitted_local_rain_strength - clamped_strength) <= 0.0001:
		return
	_last_emitted_local_rain_strength = clamped_strength
	rain_local_strength_changed.emit(clamped_strength)


func _smooth_factor(value: float, start: float, end: float) -> float:
	var t := clampf((value - start) / maxf(end - start, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _update_rain_visuals(particles: GPUParticles3D, layer_intensity: float, is_mid_layer: bool, alpha_multiplier: float = 1.0) -> void:
	if particles == null:
		return
	var mesh := particles.draw_pass_1 as QuadMesh
	if mesh == null:
		return
	var material := mesh.material as ShaderMaterial
	if material == null:
		return

	var base_color := mid_rain_color if is_mid_layer else near_rain_color
	var target_width := lerpf(0.0055, 0.009, layer_intensity) if not is_mid_layer else lerpf(0.0045, 0.0085, layer_intensity)
	var target_length := lerpf(0.08, 0.42, layer_intensity) if not is_mid_layer else lerpf(0.06, 0.36, layer_intensity)
	mesh.size = Vector2(target_width, target_length)

	var base_alpha_scale := lerpf(0.32, 1.0, layer_intensity)
	var effective_alpha := base_alpha_scale * maxf(alpha_multiplier, 0.0)
	var effective_color := Color(base_color.r, base_color.g, base_color.b, base_color.a * effective_alpha)
	material.set_shader_parameter("tint", effective_color)
	material.set_shader_parameter("width_softness", lerpf(0.12, 0.22, layer_intensity))
	material.set_shader_parameter("tail_softness", lerpf(0.18, 0.55, layer_intensity))
	material.set_shader_parameter("center_bias", lerpf(0.34, 0.62, layer_intensity))


func _orient_rain_layers(rain_direction: Vector3) -> void:
	var down_axis := rain_direction.normalized()
	var reference_up := Vector3.UP
	if absf(down_axis.dot(reference_up)) > 0.98:
		reference_up = Vector3.FORWARD
	var right_axis := reference_up.cross(down_axis).normalized()
	if right_axis.length_squared() <= 0.0001:
		right_axis = Vector3.RIGHT
	var normal_axis := down_axis.cross(right_axis).normalized()
	var basis := Basis(right_axis, down_axis, normal_axis).orthonormalized()

	if _near_particles != null:
		_near_particles.global_basis = basis
	if _mid_particles != null:
		_mid_particles.global_basis = basis


func _update_near_layer_offset(
	follow_target: Node3D,
	has_visible_rain: bool,
	nearest_visible_depth: float
) -> void:
	if _near_particles == null or follow_target == null:
		return

	var near_visibility_blend: float = _get_sheltered_near_layer_visibility_blend(
		has_visible_rain,
		nearest_visible_depth
	)
	if near_visibility_blend <= 0.001:
		_near_particles.position = Vector3.ZERO
		return

	var forward := -follow_target.global_basis.z
	var depth_extent: float = maxf(absf(near_emission_extents.z), 0.1)
	var placement_margin: float = clampf(depth_extent * 0.06, 0.1, 0.5)
	var forward_offset: float = maxf(nearest_visible_depth, 0.0) + depth_extent + placement_margin
	_near_particles.position = forward * forward_offset


func _update_mid_layer_offset(
	follow_target: Node3D,
	has_visible_rain: bool,
	nearest_visible_depth: float
) -> void:
	if _mid_particles == null or follow_target == null:
		return
	if not mid_layer_enabled:
		_mid_particles.position = Vector3.ZERO
		return

	var forward := -follow_target.global_basis.z
	var right := follow_target.global_basis.x
	var up := follow_target.global_basis.y
	var forward_offset := mid_layer_offset.z
	if _current_shelter_factor > 0.001:
		if has_visible_rain:
			var depth_extent: float = maxf(absf(mid_emission_extents.z), 0.1)
			var placement_margin: float = clampf(depth_extent * 0.08, 0.15, 0.75)
			forward_offset = maxf(
				mid_layer_offset.z,
				maxf(nearest_visible_depth, 0.0) + depth_extent + placement_margin
			)
		else:
			forward_offset += sheltered_mid_layer_forward_offset * _current_shelter_factor
	_mid_particles.position = (
		right * mid_layer_offset.x
		+ up * mid_layer_offset.y
		+ forward * forward_offset
	)


func _get_wind_direction() -> Vector2:
	var direction := wind_direction
	if use_global_wind and _has_project_setting(wind_direction_project_setting):
		direction = ProjectSettings.get_setting(String(wind_direction_project_setting), direction)

	if direction.length_squared() <= 0.0001:
		return Vector2(0.8, 0.3)
	return direction.normalized()


func _get_wind_speed() -> float:
	var speed := wind_speed
	if use_global_wind and _has_project_setting(wind_speed_project_setting):
		speed = float(ProjectSettings.get_setting(String(wind_speed_project_setting), speed))
	return maxf(speed, 0.0)


func _has_project_setting(setting_name: StringName) -> bool:
	return setting_name != &"" and ProjectSettings.has_setting(String(setting_name))


func _update_lightning(delta: float) -> void:
	_current_lightning_flash = move_toward(_current_lightning_flash, 0.0, delta * lightning_flash_decay)

	var storm_factor := get_storm_factor()
	if not lightning_enabled or storm_factor <= 0.02:
		_pending_flash_pulses = 0
		_next_flash_delay = 0.0
		_next_lightning_burst = 0.0
		return

	if _pending_flash_pulses > 0:
		_next_flash_delay -= delta
		if _next_flash_delay <= 0.0:
			_trigger_lightning_pulse(storm_factor)
		return

	_next_lightning_burst -= delta
	if _next_lightning_burst <= 0.0:
		_pending_flash_pulses = _rng.randi_range(1, 3)
		_next_flash_delay = _rng.randf_range(0.02, 0.18)
		_reset_lightning_schedule(storm_factor)


func _trigger_lightning_pulse(storm_factor: float) -> void:
	var flash_strength := _rng.randf_range(0.62, 1.0) * (0.52 + storm_factor * 0.48)
	_current_lightning_flash = maxf(_current_lightning_flash, flash_strength)
	thunder.emit(clampf(flash_strength, 0.0, 1.0))
	_pending_flash_pulses -= 1

	if _pending_flash_pulses > 0:
		_next_flash_delay = _rng.randf_range(0.05, 0.22)


func _reset_lightning_schedule(storm_factor: float) -> void:
	var min_interval := lerpf(lightning_max_interval * 0.45, lightning_min_interval, clampf(storm_factor, 0.0, 1.0))
	var max_interval := lerpf(lightning_max_interval * 1.15, lightning_max_interval * 0.55, clampf(storm_factor, 0.0, 1.0))
	min_interval = maxf(0.35, min_interval)
	max_interval = maxf(min_interval + 0.1, max_interval)
	_next_lightning_burst = _rng.randf_range(min_interval, max_interval)


func _push_weather_state(force: bool = false) -> void:
	var skydome := _get_skydome()
	if skydome == null:
		return

	var global_precipitation := clampf(precipitation_intensity, 0.0, 1.0)
	var storm_factor := get_storm_factor(global_precipitation)
	var local_emission_scale := lerpf(1.0, sheltered_volumetric_emission_scale, _current_shelter_factor)
	if not force:
		var unchanged := (
			absf(_last_applied_precipitation - global_precipitation) <= 0.0001
			and absf(_last_applied_storm_factor - storm_factor) <= 0.0001
			and absf(_last_applied_lightning_flash - _current_lightning_flash) <= 0.0001
			and absf(_last_applied_local_emission_scale - local_emission_scale) <= 0.0001
		)
		if unchanged:
			return

	skydome.set_weather_overrides(global_precipitation, storm_factor, _current_lightning_flash, local_emission_scale)
	_last_applied_precipitation = global_precipitation
	_last_applied_storm_factor = storm_factor
	_last_applied_lightning_flash = _current_lightning_flash
	_last_applied_local_emission_scale = local_emission_scale
