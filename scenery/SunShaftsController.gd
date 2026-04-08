@tool
class_name SunShaftsController
extends Node

const SUN_SHAFTS_EFFECT_SCRIPT := preload("res://scenery/SunShaftsCompositorEffect.gd")

var _world_environment_path: NodePath
var _directional_light_path: NodePath
var _distance := 10000.0
var _runtime_enabled := true

@export_group("Nodes")
@export var world_environment_path: NodePath:
	set(value):
		_world_environment_path = value
		_refresh_effect()
	get:
		return _world_environment_path

@export var directional_light_path: NodePath:
	set(value):
		_directional_light_path = value
		_refresh_effect()
	get:
		return _directional_light_path

@export_group("Shafts")
@export var distance: float = 10000.0:
	set(value):
		_distance = value
		_refresh_effect()
	get:
		return _distance

var effect: CompositorEffect


func _enter_tree() -> void:
	if _runtime_enabled:
		_ensure_effect_installed()


func _ready() -> void:
	if _runtime_enabled:
		_ensure_effect_installed()
	set_process(_runtime_enabled)


func _process(_delta: float) -> void:
	if not _runtime_enabled:
		return
	_update_effect()


func _ensure_effect_installed() -> void:
	if not _runtime_enabled:
		return
	var world_environment := get_node_or_null(_world_environment_path) as WorldEnvironment
	if world_environment == null:
		return
	var compositor := world_environment.compositor
	if compositor == null:
		compositor = Compositor.new()
		world_environment.compositor = compositor
	var effects: Array[CompositorEffect] = compositor.compositor_effects
	effects = effects.filter(func(item: CompositorEffect) -> bool: return item != null)
	var existing_effect: CompositorEffect = null
	for item in effects:
		if item != null and item.get_script() == SUN_SHAFTS_EFFECT_SCRIPT:
			existing_effect = item
			break
	if existing_effect != null:
		effect = existing_effect
		compositor.compositor_effects = effects
		return
	if effect == null or effect.get_script() != SUN_SHAFTS_EFFECT_SCRIPT:
		effect = SUN_SHAFTS_EFFECT_SCRIPT.new()
	if not effects.has(effect):
		effects.append(effect)
		compositor.compositor_effects = effects


func _update_effect() -> void:
	_ensure_effect_installed()
	if effect == null:
		return
	var light := get_node_or_null(_directional_light_path) as DirectionalLight3D
	if light == null:
		effect.set("sun_visible", false)
		return
	var camera := _get_active_camera()
	if camera == null:
		effect.set("sun_visible", false)
		return
	var viewport_size := _get_active_viewport_size()
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		effect.set("sun_visible", false)
		return

	var sun_dir := light.global_transform.basis.z.normalized()
	var sun_world_position := camera.global_position + (sun_dir * _distance)
	if camera.is_position_behind(sun_world_position):
		effect.set("sun_visible", false)
		return

	var screen_position := camera.unproject_position(sun_world_position)
	effect.set("sun_screen_uv", Vector2(
		screen_position.x / viewport_size.x,
		screen_position.y / viewport_size.y
	))
	effect.set("sun_visible", true)


func _refresh_effect() -> void:
	if not _runtime_enabled:
		return
	if not is_inside_tree():
		return
	_ensure_effect_installed()
	_update_effect()


func set_runtime_enabled(value: bool) -> void:
	_runtime_enabled = value
	set_process(value)
	if not value:
		if effect != null:
			effect.set("sun_visible", false)
		return
	_ensure_effect_installed()
	_update_effect()


func _get_active_camera() -> Camera3D:
	if Engine.is_editor_hint():
		var editor_interface := Engine.get_singleton(&"EditorInterface")
		if editor_interface != null:
			var editor_viewport: SubViewport = editor_interface.get_editor_viewport_3d(0)
			if editor_viewport != null:
				return editor_viewport.get_camera_3d()
	return get_viewport().get_camera_3d()


func _get_active_viewport_size() -> Vector2:
	if Engine.is_editor_hint():
		var editor_interface := Engine.get_singleton(&"EditorInterface")
		if editor_interface != null:
			var editor_viewport: SubViewport = editor_interface.get_editor_viewport_3d(0)
			if editor_viewport != null:
				return editor_viewport.get_visible_rect().size
	return get_viewport().get_visible_rect().size
