extends Node3D

const PROFILE_ID_FILMIC := &"filmic"
const PROFILE_ID_HIGH := &"high"
const PROFILE_ID_MID := &"mid"
const PROFILE_ID_LOW := &"low"

@onready var _quality_profiles_manager: QualityProfilesManager = $QualityProfilesManager
@onready var _directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var _terrain: TerrainPatch3D = $Terrain
@onready var _auto_biomes_fog: AutoBiomesFog = $AutoBiomesFog
@onready var _sun_shafts_controller: Skydome = $Skydome


func _on_quality_profiles_manager_profile_changed() -> void:
    var profile := _quality_profiles_manager.get_selected_profile()

    var settings := _build_project_quality_settings(profile.id)
    var light_settings: Dictionary = settings["light"]
    var terrain_settings: Dictionary = settings["terrain"]
    _apply_sun_shafts_profile(settings["sun_shafts_enabled"])
    _apply_fog_profile(settings["fog_controller_max_density"])
    _apply_light_profile(light_settings)
    _apply_terrain_profile(terrain_settings)
    if _sun_shafts_controller != null:
        _sun_shafts_controller.apply_now()
    _refresh_debug_menu()


func _build_project_quality_settings(profile_id: StringName) -> Dictionary:
    match profile_id:
        PROFILE_ID_FILMIC:
            return {
                "sun_shafts_enabled": true,
                "fog_controller_max_density": 0.02,
                "light": {
                    "light_energy": 1.409,
                    "light_indirect_energy": 1.3,
                    "light_volumetric_fog_energy": 6.2,
                    "light_angular_distance": 3.6,
                    "directional_shadow_max_distance": 200.0,
                },
                "terrain": {
                    "grass_radius": 20.0,
                    "grass_max_instances": 12000,
                },
            }
        PROFILE_ID_HIGH:
            return {
                "sun_shafts_enabled": true,
                "fog_controller_max_density": 0.015,
                "light": {
                    "light_energy": 1.409,
                    "light_indirect_energy": 0.925,
                    "light_volumetric_fog_energy": 6.176,
                    "light_angular_distance": 0.0,
                    "directional_shadow_max_distance": 200.0,
                },
                "terrain": {
                    "grass_radius": 15.0,
                    "grass_max_instances": 10000,
                },
            }
        PROFILE_ID_MID:
            return {
                "sun_shafts_enabled": true,
                "fog_controller_max_density": 0.011,
                "light": {
                    "light_energy": 1.34,
                    "light_indirect_energy": 1.02,
                    "light_volumetric_fog_energy": 4.2,
                    "light_angular_distance": 2.8,
                    "directional_shadow_max_distance": 150.0,
                },
                "terrain": {
                    "grass_radius": 11.0,
                    "grass_max_instances": 7000,
                },
            }
        PROFILE_ID_LOW:
            return {
                "sun_shafts_enabled": false,
                "fog_controller_max_density": 0.0,
                "light": {
                    "light_energy": 1.32,
                    "light_indirect_energy": 1.0,
                    "light_volumetric_fog_energy": 0.0,
                    "light_angular_distance": 2.8,
                    "directional_shadow_max_distance": 110.0,
                },
                "terrain": {
                    "grass_radius": 8.0,
                    "grass_max_instances": 4500,
                },
            }
    return _build_project_quality_settings(PROFILE_ID_HIGH)


func _apply_sun_shafts_profile(enabled: bool) -> void:
    if _sun_shafts_controller != null:
        _sun_shafts_controller.sunshafts_enabled = enabled


func _apply_fog_profile(max_density: float) -> void:
    if _auto_biomes_fog != null:
        _auto_biomes_fog.max_density = max_density


func _apply_light_profile(settings: Dictionary) -> void:
    if _directional_light == null:
        return

    _directional_light.light_energy = settings["light_energy"]
    _directional_light.light_indirect_energy = settings["light_indirect_energy"]
    _directional_light.light_volumetric_fog_energy = settings["light_volumetric_fog_energy"]
    _directional_light.light_angular_distance = settings["light_angular_distance"]
    _directional_light.directional_shadow_max_distance = settings["directional_shadow_max_distance"]


func _apply_terrain_profile(settings: Dictionary) -> void:
    if _terrain == null:
        return

    _terrain.grass_radius = settings["grass_radius"]
    _terrain.grass_max_instances = settings["grass_max_instances"]


func _refresh_debug_menu() -> void:
    var debug_menu := get_node_or_null("/root/DebugMenu")
    if debug_menu != null and debug_menu.has_method("update_settings_label"):
        debug_menu.call_deferred("update_settings_label")


func _on_world_timer_timeout():
    $Skydome.time_of_day = wrapf($Skydome.time_of_day + 0.01, 0, 23.999)
