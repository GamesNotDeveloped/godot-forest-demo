extends Node
class_name QualityProfilesManager

signal profile_changed

@export var profiles: Array[QualityProfile] = []
@export var initial_profile_id: StringName = &""
@export_node_path("WorldEnvironment") var world_environment_path: NodePath

var selected_profile: QualityProfile = null
var _apply_serial: int = 0


func _ready() -> void:
    call_deferred("_apply_initial_profile_async")


func get_profiles() -> Array[QualityProfile]:
    return profiles


func get_selected_profile() -> QualityProfile:
    return selected_profile


func get_profile_by_id(profile_id: StringName) -> QualityProfile:
    for profile in profiles:
        if profile != null and profile.id == profile_id:
            return profile
    return null


func select_profile_by_id(profile_id: StringName) -> bool:
    return select_profile(get_profile_by_id(profile_id))


func select_profile(profile: QualityProfile) -> bool:
    if profile == null:
        return false

    selected_profile = profile
    _apply_serial += 1
    _apply_profile_settings(profile)
    profile_changed.emit()
    _reapply_profile_next_frame(profile, _apply_serial)
    return true


func _apply_initial_profile_async() -> void:
    await get_tree().process_frame
    _apply_initial_profile()


func _apply_initial_profile() -> void:
    if profiles.is_empty():
        return

    if initial_profile_id != &"" and select_profile_by_id(initial_profile_id):
        return

    select_profile(profiles[0])


func _reapply_profile_next_frame(profile: QualityProfile, serial: int) -> void:
    await get_tree().process_frame
    if serial != _apply_serial or selected_profile != profile:
        return

    _apply_profile_settings(profile)


func _apply_profile_settings(profile: QualityProfile) -> void:
    _apply_viewport_profile(profile)
    _apply_world_environment_profile(profile)
    _apply_global_shader_parameters(profile)


func _apply_global_shader_parameters(profile: QualityProfile) -> void:
    RenderingServer.global_shader_parameter_set(&"gnd_high_quality_sky", profile.high_quality_sky)
    RenderingServer.global_shader_parameter_set(&"gnd_high_quality_foliage", profile.high_quality_foliage)


func _apply_viewport_profile(profile: QualityProfile) -> void:
    var viewport := get_viewport()
    if viewport == null:
        return

    viewport.scaling_3d_mode = profile.scaling_3d_mode
    viewport.scaling_3d_scale = profile.scaling_3d_scale
    viewport.fsr_sharpness = profile.fsr_sharpness
    viewport.use_taa = profile.use_taa
    viewport.msaa_3d = profile.msaa_3d
    viewport.screen_space_aa = profile.screen_space_aa


func _apply_world_environment_profile(profile: QualityProfile) -> void:
    var world_environment := _get_world_environment()
    if world_environment == null:
        return

    _apply_environment_profile(world_environment.environment, profile)
    _apply_camera_attributes_profile(world_environment.camera_attributes, profile)


func _apply_environment_profile(environment: Environment, profile: QualityProfile) -> void:
    if environment == null:
        return

    environment.background_energy_multiplier = profile.background_energy_multiplier
    environment.tonemap_exposure = profile.tonemap_exposure
    environment.tonemap_white = profile.tonemap_white
    environment.tonemap_agx_contrast = profile.tonemap_agx_contrast
    environment.ssao_enabled = profile.ssao_enabled
    environment.ssao_light_affect = profile.ssao_light_affect
    environment.ssil_enabled = profile.ssil_enabled
    environment.sdfgi_enabled = profile.sdfgi_enabled
    environment.glow_enabled = profile.glow_enabled
    environment.glow_intensity = profile.glow_intensity
    environment.glow_bloom = profile.glow_bloom
    environment.volumetric_fog_enabled = profile.volumetric_fog_enabled
    environment.adjustment_enabled = true
    environment.adjustment_saturation = profile.adjustment_saturation
    environment.adjustment_color_correction = profile.adjustment_color_correction


func _apply_camera_attributes_profile(camera_attributes: CameraAttributes, profile: QualityProfile) -> void:
    var practical_attributes := camera_attributes as CameraAttributesPractical
    if practical_attributes == null:
        return

    practical_attributes.auto_exposure_enabled = profile.auto_exposure_enabled
    practical_attributes.auto_exposure_scale = profile.auto_exposure_scale
    practical_attributes.auto_exposure_speed = profile.auto_exposure_speed
    practical_attributes.auto_exposure_min_sensitivity = profile.auto_exposure_min_sensitivity
    practical_attributes.auto_exposure_max_sensitivity = profile.auto_exposure_max_sensitivity


func _get_world_environment() -> WorldEnvironment:
    if world_environment_path.is_empty():
        return null
    return get_node_or_null(world_environment_path) as WorldEnvironment
