extends Node3D

const PROFILE_ID_FILMIC := &"filmic"
const PROFILE_ID_HIGH := &"high"
const PROFILE_ID_MID := &"mid"
const PROFILE_ID_LOW := &"low"
const RAIN_BUS_NAME := &"Rain"
const RAIN_LP_OPEN_CUTOFF_HZ := 20500.0
const RAIN_LP_OCCLUDED_CUTOFF_HZ := 3000.0
const RAIN_LP_TWEEN_DURATION := 0.12
const STORM_RAIN_START_RATIO := 0.4
const SKYDOME_FOG_RAIN_START_RATIO := 0.6
const SKYDOME_FOG_DENSITY_MAX := 0.4
const DEFAULT_WORLD_TIME_SCALE := 50.0
const DEFAULT_RAIN_INTENSITY := 0.35
const DEFAULT_CLOUD_DENSITY := 0.15
const THUNDER_HEAVY_THRESHOLD_CALM := 0.9
const THUNDER_HEAVY_THRESHOLD_STORM := 0.72
const THUNDER_VOLUME_DB_MIN := -5.0
const THUNDER_VOLUME_DB_MAX := 1.5

@onready var _quality_profiles_manager: QualityProfilesManager = $QualityProfilesManager
@onready var _directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var _terrain: TerrainPatch3D = $Terrain
@onready var _sun_shafts_controller: Skydome = $Skydome
@onready var _weather: WeatherNode = $Weather
@onready var _thunder_light_player: AudioStreamPlayer = $Thunder1
@onready var _thunder_heavy_player: AudioStreamPlayer = $Thunder2

var _rain_low_pass_filter: AudioEffectLowPassFilter
var _rain_low_pass_tween: Tween
var _world_time_scale: float = DEFAULT_WORLD_TIME_SCALE


func _ready() -> void:
    _on_mouse_capture_toggled(true)
    var rain_bus_index := AudioServer.get_bus_index(RAIN_BUS_NAME)
    if rain_bus_index >= 0 and AudioServer.get_bus_effect_count(rain_bus_index) > 0:
        _rain_low_pass_filter = AudioServer.get_bus_effect(rain_bus_index, 0) as AudioEffectLowPassFilter
    _apply_rain_low_pass_cutoff(RAIN_LP_OPEN_CUTOFF_HZ)
    _apply_default_weather_controls()


func _input(event):
    if event.is_action_pressed("toggle_flashlight"):
        var flashlight_state = $UP_FPSController_Prefab/RotationHelper/Flashlight.visible
        $UP_FPSController_Prefab/RotationHelper/Flashlight.visible = not flashlight_state
        var sound = $FlashlightOn if flashlight_state else $FlashlightOff
        sound.play()



func _on_quality_profiles_manager_profile_changed() -> void:
    var profile := _quality_profiles_manager.get_selected_profile()

    var settings := _build_project_quality_settings(profile.id)
    var light_settings: Dictionary = settings["light"]
    var terrain_settings: Dictionary = settings["terrain"]
    _apply_sun_shafts_profile(settings["sun_shafts_enabled"])
    _apply_light_profile(light_settings)
    _apply_terrain_profile(terrain_settings)
    if _sun_shafts_controller != null:
        _sun_shafts_controller.apply_now()
    if _weather != null:
        _weather.apply_now()
    _refresh_debug_menu()


func get_world_time_scale() -> float:
    return _world_time_scale


func _apply_default_weather_controls() -> void:
    if _weather == null:
        return

    _weather.set_precipitation_intensity(DEFAULT_RAIN_INTENSITY)
    _weather.set_cloud_density(DEFAULT_CLOUD_DENSITY)
    _weather.set_cloud_overcast_intensity(DEFAULT_RAIN_INTENSITY)
    _weather.set_storm_intensity(clampf(inverse_lerp(STORM_RAIN_START_RATIO, 1.0, DEFAULT_RAIN_INTENSITY), 0.0, 1.0))
    _weather.set_storm_fog_intensity(_get_skydome_fog_density_from_rain(DEFAULT_RAIN_INTENSITY))


func _get_skydome_fog_density_from_rain(rain_ratio: float) -> float:
    var clamped_rain := clampf(rain_ratio, 0.0, 1.0)
    return clampf(
        inverse_lerp(SKYDOME_FOG_RAIN_START_RATIO, 1.0, clamped_rain) * SKYDOME_FOG_DENSITY_MAX,
        0.0,
        SKYDOME_FOG_DENSITY_MAX
    )


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
    $Skydome.time_of_day = wrapf($Skydome.time_of_day + ((_world_time_scale * $WorldTimer.wait_time) / 3600.0), 0, 23.999)


func _on_weather_controls_canvas_world_time_scale_changed(scale: float) -> void:
    _world_time_scale = maxf(scale, 0.0)


func _on_weather_thunder(strength: float) -> void:
    var thunder_strength := clampf(strength, 0.0, 1.0)
    var storm_factor := 0.0
    if _weather != null:
        storm_factor = clampf(_weather.get_storm_factor(), 0.0, 1.0)

    var heavy_threshold := lerpf(THUNDER_HEAVY_THRESHOLD_CALM, THUNDER_HEAVY_THRESHOLD_STORM, storm_factor)
    var player := _thunder_heavy_player if thunder_strength >= heavy_threshold else _thunder_light_player
    player.volume_db = lerpf(THUNDER_VOLUME_DB_MIN, THUNDER_VOLUME_DB_MAX, thunder_strength)
    player.play()


func _on_weather_rain_strength_changed(strength):
    print("weather rain str chg ", strength)
    if strength > 0.4:
        if $Rain2.playing:
            $Rain2.stop()
        if not $Rain1.playing:
            $Rain1.play()
        $Rain1.volume_db = 2 * (strength-0.4)
    elif strength > 0.0001:
        if $Rain1.playing:
            $Rain1.stop()
        if not $Rain2.playing:
            $Rain2.play()
        $Rain2.volume_db = ((strength * 3)-1)*2 -1
    else:
        print("Stopping rain")
        if $Rain1.playing:
            $Rain1.stop()
        if $Rain2.playing:
            $Rain2.stop()
        if $Thunder1.playing:
            $Thunder1.stop()
        if $Thunder2.playing:
            $Thunder2.stop()



func _on_weather_rain_local_strength_changed(strength: float) -> void:
    if _rain_low_pass_filter == null or _weather == null:
        return

    var global_strength := clampf(_weather.precipitation_intensity, 0.0, 1.0)
    var shelter_factor := 0.0
    if global_strength > 0.0001:
        shelter_factor = clampf((global_strength - strength) / global_strength, 0.0, 1.0)

    var target_cutoff := lerpf(RAIN_LP_OPEN_CUTOFF_HZ, RAIN_LP_OCCLUDED_CUTOFF_HZ, shelter_factor)
    _tween_rain_low_pass_cutoff(target_cutoff)


func _tween_rain_low_pass_cutoff(target_cutoff_hz: float) -> void:
    if _rain_low_pass_filter == null:
        return

    if _rain_low_pass_tween != null:
        _rain_low_pass_tween.kill()

    _rain_low_pass_tween = create_tween()
    _rain_low_pass_tween.tween_property(
        _rain_low_pass_filter,
        "cutoff_hz",
        clampf(target_cutoff_hz, RAIN_LP_OCCLUDED_CUTOFF_HZ, RAIN_LP_OPEN_CUTOFF_HZ),
        RAIN_LP_TWEEN_DURATION
    ).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _apply_rain_low_pass_cutoff(cutoff_hz: float) -> void:
    if _rain_low_pass_filter == null:
        return
    _rain_low_pass_filter.cutoff_hz = clampf(cutoff_hz, RAIN_LP_OCCLUDED_CUTOFF_HZ, RAIN_LP_OPEN_CUTOFF_HZ)


func _on_mouse_capture_toggled(captured):
    $QualityProfilesCanvas.visible = not captured
    $WeatherControlsCanvas.visible = not captured


func _on_up_fps_controller_prefab_footstep(leg):
    var snd = $Footstep1 if leg == 0 else $Footstep2
    snd.play()
