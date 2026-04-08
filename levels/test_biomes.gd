extends Node3D

const QUALITY_PROFILE_FILMIC := "Filmic"
const QUALITY_PROFILE_HIGH := "High"
const QUALITY_PROFILE_MID := "Mid"
const QUALITY_PROFILE_LOW := "Low"
const QUALITY_PROFILES := [
    QUALITY_PROFILE_FILMIC,
    QUALITY_PROFILE_HIGH,
    QUALITY_PROFILE_MID,
    QUALITY_PROFILE_LOW,
]

@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var _terrain: TerrainPatch3D = $Terrain
@onready var _auto_biomes_fog: AutoBiomesFog = $AutoBiomesFog
@onready var _sun_shafts_controller: SunShaftsController = $SunShaftsController

var _active_quality_profile := QUALITY_PROFILE_FILMIC

var _environment_resources: Dictionary = {}
var _camera_attribute_resources: Dictionary = {}
var _compositor_resources: Dictionary = {}
var _terrain_material: StandardMaterial3D
var _grass_material: ShaderMaterial
var _tree_leaf_materials: Array[ShaderMaterial] = []
var _profile_apply_serial := 0


func _ready() -> void:
    _cache_material_references()
    apply_quality_profile(_active_quality_profile)


func get_active_quality_profile() -> String:
    return _active_quality_profile


func apply_quality_profile(profile_name: String) -> void:
    if not QUALITY_PROFILES.has(profile_name):
        return

    _active_quality_profile = profile_name
    _profile_apply_serial += 1

    var profile: Dictionary = _build_quality_profile(profile_name)
    _apply_profile_settings(profile)
    _refresh_debug_menu()
    _reapply_profile_next_frame(_profile_apply_serial)


func _reapply_profile_next_frame(serial: int) -> void:
    await get_tree().process_frame
    if serial != _profile_apply_serial:
        return

    var profile: Dictionary = _build_quality_profile(_active_quality_profile)
    _apply_profile_settings(profile)
    _refresh_debug_menu()


func _apply_profile_settings(profile: Dictionary) -> void:
    _apply_viewport_profile(profile["viewport"] as Dictionary)
    _apply_environment_resources(
        profile["environment_resource"] as String,
        profile["camera_resource"] as String,
        profile["compositor_resource"] as String
    )
    _apply_sun_shafts_profile(profile["sun_shafts_enabled"])
    _apply_fog_profile(profile["fog_controller_max_density"])
    _apply_light_profile(profile["light"] as Dictionary)
    _apply_terrain_profile(profile["terrain"] as Dictionary)
    _apply_material_profile(profile["materials"] as String)


func _cache_material_references() -> void:
    _environment_resources = {
        QUALITY_PROFILE_FILMIC: load("res://materials/environment_filmic.tres"),
        QUALITY_PROFILE_HIGH: load("res://materials/environment_high.tres"),
        QUALITY_PROFILE_MID: load("res://materials/environment_mid.tres"),
        QUALITY_PROFILE_LOW: load("res://materials/environment_low.tres"),
    }
    _camera_attribute_resources = {
        QUALITY_PROFILE_FILMIC: load("res://materials/camera_attributes_filmic.tres"),
        QUALITY_PROFILE_HIGH: load("res://materials/camera_attributes_high.tres"),
        QUALITY_PROFILE_MID: load("res://materials/camera_attributes_mid.tres"),
        QUALITY_PROFILE_LOW: load("res://materials/camera_attributes_low.tres"),
    }
    _compositor_resources = {
        QUALITY_PROFILE_FILMIC: load("res://materials/filmic_compositor.tres"),
        QUALITY_PROFILE_HIGH: load("res://materials/default_compositor.tres"),
        QUALITY_PROFILE_MID: load("res://materials/default_compositor.tres"),
        QUALITY_PROFILE_LOW: null,
    }
    _terrain_material = _terrain.terrain_material as StandardMaterial3D
    _grass_material = _terrain.grass_material as ShaderMaterial
    _tree_leaf_materials = [
        load("res://objects/pine-tree-1/textures/Tree_1Mat.tres") as ShaderMaterial,
        load("res://objects/pine-tree-2/textures/Pine_s_1_Material.tres") as ShaderMaterial,
        load("res://objects/pine-tree-3/textures/Tree_tex.tres") as ShaderMaterial,
        load("res://objects/pine-tree-4/textures/Tree_Pine.tres") as ShaderMaterial,
        load("res://objects/birch-tree-1/textures/Leaves.tres") as ShaderMaterial,
        load("res://objects/plants/Plant_148_Leaves_Mat.tres") as ShaderMaterial,
    ]


func _build_quality_profile(profile_name: String) -> Dictionary:
    match profile_name:
        QUALITY_PROFILE_FILMIC:
            return {
                "viewport": {
                    "scaling_mode": Viewport.SCALING_3D_MODE_FSR2,
                    "scaling_scale": 0.85,
                    "fsr_sharpness": 0.0,
                    "use_taa": false,
                    "msaa_3d": Viewport.MSAA_DISABLED,
                    "screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED,
                },
                "environment_resource": QUALITY_PROFILE_FILMIC,
                "camera_resource": QUALITY_PROFILE_FILMIC,
                "compositor_resource": QUALITY_PROFILE_FILMIC,
                "sun_shafts_enabled": true,
                "fog_controller_max_density": 0.02,
                "light": {
                    "light_energy": 1.26,
                    "light_indirect_energy": 1.3,
                    "light_volumetric_fog_energy": 6.2,
                    "light_angular_distance": 3.6,
                    "directional_shadow_max_distance": 200.0,
                },
                "terrain": {
                    "grass_radius": 15.0,
                    "grass_max_instances": 10000,
                },
                "materials": QUALITY_PROFILE_FILMIC,
            }
        QUALITY_PROFILE_HIGH:
            return {
                "viewport": {
                    "scaling_mode": Viewport.SCALING_3D_MODE_BILINEAR,
                    "scaling_scale": 1.0,
                    "fsr_sharpness": 0.0,
                    "use_taa": false,
                    "msaa_3d": Viewport.MSAA_DISABLED,
                    "screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA,
                },
                "environment_resource": QUALITY_PROFILE_HIGH,
                "camera_resource": QUALITY_PROFILE_HIGH,
                "compositor_resource": QUALITY_PROFILE_HIGH,
                "sun_shafts_enabled": true,
                "fog_controller_max_density": 0.015,
                "light": {
                    "light_energy": 1.409,
                    "light_indirect_energy": 0.925,
                    "light_volumetric_fog_energy": 6.176,
                    "light_angular_distance": 2.5,
                    "directional_shadow_max_distance": 200.0,
                },
                "terrain": {
                    "grass_radius": 15.0,
                    "grass_max_instances": 10000,
                },
                "materials": QUALITY_PROFILE_HIGH,
            }
        QUALITY_PROFILE_MID:
            return {
                "viewport": {
                    "scaling_mode": Viewport.SCALING_3D_MODE_FSR,
                    "scaling_scale": 0.77,
                    "fsr_sharpness": 0.08,
                    "use_taa": false,
                    "msaa_3d": Viewport.MSAA_DISABLED,
                    "screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA,
                },
                "environment_resource": QUALITY_PROFILE_MID,
                "camera_resource": QUALITY_PROFILE_MID,
                "compositor_resource": QUALITY_PROFILE_MID,
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
                "materials": QUALITY_PROFILE_HIGH,
            }
        QUALITY_PROFILE_LOW:
            return {
                "viewport": {
                    "scaling_mode": Viewport.SCALING_3D_MODE_FSR,
                    "scaling_scale": 0.67,
                    "fsr_sharpness": 0.12,
                    "use_taa": false,
                    "msaa_3d": Viewport.MSAA_DISABLED,
                    "screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA,
                },
                "environment_resource": QUALITY_PROFILE_LOW,
                "camera_resource": QUALITY_PROFILE_LOW,
                "compositor_resource": QUALITY_PROFILE_LOW,
                "sun_shafts_enabled": false,
                "fog_controller_max_density": -1.0,
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
                "materials": QUALITY_PROFILE_HIGH,
            }
    return _build_quality_profile(QUALITY_PROFILE_HIGH)


func _apply_viewport_profile(settings: Dictionary) -> void:
    var viewport := get_viewport()
    if viewport == null:
        return

    viewport.scaling_3d_mode = settings["scaling_mode"]
    viewport.scaling_3d_scale = settings["scaling_scale"]
    viewport.fsr_sharpness = settings["fsr_sharpness"]
    viewport.use_taa = settings["use_taa"]
    viewport.msaa_3d = settings["msaa_3d"]
    viewport.screen_space_aa = settings["screen_space_aa"]


func _apply_environment_resources(environment_profile: String, camera_profile: String, compositor_profile: String) -> void:
    if _world_environment == null:
        return

    var environment_resource := _environment_resources.get(environment_profile) as Environment
    var camera_resource := _camera_attribute_resources.get(camera_profile) as CameraAttributesPractical
    var compositor_resource := _compositor_resources.get(compositor_profile) as Compositor
    if environment_resource != null:
        _world_environment.environment = environment_resource
    if camera_resource != null:
        _world_environment.camera_attributes = camera_resource
    _world_environment.compositor = compositor_resource


func _apply_sun_shafts_profile(enabled: bool) -> void:
    if _sun_shafts_controller != null:
        _sun_shafts_controller.set_runtime_enabled(enabled)


func _apply_fog_profile(max_density: float) -> void:
    if _auto_biomes_fog != null:
        _auto_biomes_fog.apply_profile_override(max_density)


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


func _apply_material_profile(material_profile: String) -> void:
    if material_profile == QUALITY_PROFILE_FILMIC:
        _apply_terrain_material_values(1.15, false, 4, 12)
        _apply_grass_material_values(0.54, 0.65, Color(0.56, 0.58, 0.54, 1.0))
        _apply_tree_material_values([
            {"normal_scale": 0.55, "roughness": 0.86, "metallic_specular": 0.08, "alpha_scissor_threshold": 0.12, "backlight_color": Color(0.46, 0.48, 0.44, 1.0), "sss_strength": 0.35},
            {"normal_scale": 1.0, "roughness": 0.96, "metallic_specular": 0.0, "alpha_scissor_threshold": 0.54, "backlight_color": Color(0.34, 0.36, 0.33, 1.0), "sss_strength": 0.2},
            {"normal_scale": 1.0, "roughness": 0.95, "metallic_specular": 0.0, "alpha_scissor_threshold": 0.42, "backlight_color": Color(0.48, 0.5, 0.46, 1.0), "sss_strength": 0.24},
            {"normal_scale": 1.0, "roughness": 1.0, "metallic_specular": 0.05, "alpha_scissor_threshold": 0.33, "backlight_color": Color(0.5, 0.52, 0.48, 1.0), "sss_strength": 0.42},
            {"normal_scale": 1.0, "roughness": 0.94, "metallic_specular": 0.16, "alpha_scissor_threshold": 0.42, "backlight_color": Color(0.62, 0.66, 0.58, 1.0), "sss_strength": 0.58},
            {"normal_scale": 1.0, "roughness": 0.97, "metallic_specular": 0.12, "alpha_scissor_threshold": 0.46, "backlight_color": Color(0.34, 0.42, 0.34, 1.0), "sss_strength": 0.45},
        ])
        return

    _apply_terrain_material_values(2.19, false, 8, 32)
    _apply_grass_material_values(0.672, 1.0, Color(0.70703125, 0.70703125, 0.70703125, 1.0))
    _apply_tree_material_values([
        {"normal_scale": 1.0, "roughness": 0.72, "metallic_specular": 0.14800000703, "alpha_scissor_threshold": 0.1530000072675, "backlight_color": Color(0.53125, 0.53125, 0.53125, 1.0), "sss_strength": 0.298000014155},
        {"normal_scale": 1.0, "roughness": 0.91316754, "metallic_specular": 0.0, "alpha_scissor_threshold": 0.652, "backlight_color": Color(0.25390625, 0.25390625, 0.25390625, 1.0), "sss_strength": 0.13},
        {"normal_scale": 1.0, "roughness": 0.9, "metallic_specular": 0.0, "alpha_scissor_threshold": 0.496, "backlight_color": Color(0.4140625, 0.4140625, 0.4140625, 1.0), "sss_strength": 0.19},
        {"normal_scale": 1.0, "roughness": 1.005, "metallic_specular": 0.106000005035, "alpha_scissor_threshold": 0.390000018525, "backlight_color": Color(0.41015625, 0.41015625, 0.41015625, 1.0), "sss_strength": 0.3750000178125},
        {"normal_scale": 1.0, "roughness": 0.82, "metallic_specular": 0.5, "alpha_scissor_threshold": 0.514000024415, "backlight_color": Color(0.7421875, 0.7421875, 0.7421875, 1.0), "sss_strength": 0.5230000248425},
        {"normal_scale": 1.0, "roughness": 0.92, "metallic_specular": 0.226000010735, "alpha_scissor_threshold": 0.5490000260775, "backlight_color": Color(0.278431, 0.341176, 0.282353, 1.0), "sss_strength": 0.38400001824},
    ])


func _apply_terrain_material_values(normal_scale: float, deep_parallax: bool, min_layers: int, max_layers: int) -> void:
    if _terrain_material == null:
        return

    _terrain_material.normal_scale = normal_scale
    _terrain_material.heightmap_deep_parallax = deep_parallax
    _terrain_material.heightmap_min_layers = min_layers
    _terrain_material.heightmap_max_layers = max_layers


func _apply_grass_material_values(alpha_scissor_threshold: float, normal_scale: float, backlight: Color) -> void:
    if _grass_material == null:
        return

    _grass_material.set_shader_parameter("alpha_scissor_threshold", alpha_scissor_threshold)
    _grass_material.set_shader_parameter("normal_scale", normal_scale)
    _grass_material.set_shader_parameter("backlight", backlight)


func _apply_tree_material_values(material_values: Array[Dictionary]) -> void:
    var count := mini(_tree_leaf_materials.size(), material_values.size())
    for index in count:
        var material := _tree_leaf_materials[index]
        var values := material_values[index]
        if material == null:
            continue
        material.set_shader_parameter("normal_scale", values["normal_scale"])
        material.set_shader_parameter("roughness", values["roughness"])
        material.set_shader_parameter("metallic_specular", values["metallic_specular"])
        material.set_shader_parameter("alpha_scissor_threshold", values["alpha_scissor_threshold"])
        material.set_shader_parameter("backlight_color", values["backlight_color"])
        material.set_shader_parameter("sss_strength", values["sss_strength"])


func _refresh_debug_menu() -> void:
    var debug_menu := get_node_or_null("/root/DebugMenu")
    if debug_menu != null and debug_menu.has_method("update_settings_label"):
        debug_menu.call_deferred("update_settings_label")
