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
@onready var _environment: Environment = $WorldEnvironment.environment
@onready var _camera_attributes: CameraAttributesPractical = $WorldEnvironment.camera_attributes as CameraAttributesPractical
@onready var _directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var _terrain: TerrainPatch3D = $Terrain
@onready var _auto_biomes_fog: AutoBiomesFog = $AutoBiomesFog

var _active_quality_profile := QUALITY_PROFILE_HIGH

var _terrain_material: StandardMaterial3D
var _grass_material: ShaderMaterial
var _tree_leaf_materials: Array[ShaderMaterial] = []


func _ready() -> void:
    _cache_material_references()
    if _environment != null:
        _environment.volumetric_fog_enabled = true
    apply_quality_profile(_active_quality_profile)


func get_active_quality_profile() -> String:
    return _active_quality_profile


func apply_quality_profile(profile_name: String) -> void:
    if not QUALITY_PROFILES.has(profile_name):
        return

    _active_quality_profile = profile_name

    var profile: Dictionary = _build_quality_profile(profile_name)
    _apply_viewport_profile(profile["viewport"] as Dictionary)
    _apply_environment_profile(profile["environment"] as Dictionary)
    _apply_camera_profile(profile["camera"] as Dictionary)
    _apply_light_profile(profile["light"] as Dictionary)
    _apply_terrain_profile(profile["terrain"] as Dictionary)
    _apply_material_profile(profile["materials"] as String)
    _refresh_debug_menu()


func _cache_material_references() -> void:
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
                "camera": {
                    "auto_exposure_scale": 0.28,
                    "auto_exposure_speed": 1.5,
                    "auto_exposure_min_sensitivity": 80.0,
                    "auto_exposure_max_sensitivity": 220.0,
                },
                "environment": {
                    "ambient_light_energy": 2.55,
                    "tonemap_exposure": 1.18,
                    "tonemap_white": 8.6,
                    "tonemap_agx_contrast": 1.22,
                    "ssao_enabled": true,
                    "ssao_light_affect": 0.08,
                    "ssil_enabled": true,
                    "sdfgi_enabled": true,
                    "glow_enabled": true,
                    "glow_intensity": 1.08,
                    "glow_bloom": 0.31,
                    "fog_enabled": true,
                    "fog_light_color": Color(1.0, 0.95686275, 0.91764706, 1.0),
                    "fog_sun_scatter": 0.45,
                    "fog_density": 0.102,
                    "fog_sky_affect": 0.12,
                    "fog_depth_curve": 0.42,
                    "fog_depth_begin": 1.8,
                    "fog_depth_end": 430.0,
                    "volumetric_fog_enabled": true,
                    "volumetric_fog_density": 0.02,
                    "volumetric_fog_gi_inject": 1.2,
                    "volumetric_fog_anisotropy": 0.42,
                    "volumetric_fog_length": 8.0,
                    "volumetric_fog_ambient_inject": 0.18,
                    "volumetric_fog_sky_affect": 0.82,
                    "adjustment_saturation": 0.82,
                    "fog_controller_max_density": 0.02,
                },
                "light": {
                    "light_energy": 1.28,
                    "light_indirect_energy": 1.18,
                    "light_volumetric_fog_energy": 7.1,
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
                "camera": {
                    "auto_exposure_scale": 0.33,
                    "auto_exposure_speed": 3.0,
                    "auto_exposure_min_sensitivity": 91.33,
                    "auto_exposure_max_sensitivity": 506.5,
                },
                "environment": {
                    "ambient_light_energy": 2.35,
                    "tonemap_exposure": 1.32,
                    "tonemap_white": 9.64,
                    "tonemap_agx_contrast": 1.57,
                    "ssao_enabled": true,
                    "ssao_light_affect": 0.11,
                    "ssil_enabled": true,
                    "sdfgi_enabled": true,
                    "glow_enabled": true,
                    "glow_intensity": 0.96,
                    "glow_bloom": 0.23,
                    "fog_enabled": true,
                    "fog_light_color": Color(1.0, 1.0, 1.0, 1.0),
                    "fog_sun_scatter": 0.34,
                    "fog_density": 0.0885,
                    "fog_sky_affect": 0.071,
                    "fog_depth_curve": 0.32987642,
                    "fog_depth_begin": 3.4,
                    "fog_depth_end": 570.3,
                    "volumetric_fog_enabled": true,
                    "volumetric_fog_density": 0.015,
                    "volumetric_fog_gi_inject": 1.1,
                    "volumetric_fog_anisotropy": 0.35,
                    "volumetric_fog_length": 6.23,
                    "volumetric_fog_ambient_inject": 0.11,
                    "volumetric_fog_sky_affect": 0.768,
                    "adjustment_saturation": 0.88,
                    "fog_controller_max_density": 0.015,
                },
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
                "camera": {
                    "auto_exposure_scale": 0.32,
                    "auto_exposure_speed": 2.3,
                    "auto_exposure_min_sensitivity": 88.0,
                    "auto_exposure_max_sensitivity": 360.0,
                },
                "environment": {
                    "ambient_light_energy": 2.3,
                    "tonemap_exposure": 1.28,
                    "tonemap_white": 9.2,
                    "tonemap_agx_contrast": 1.46,
                    "ssao_enabled": true,
                    "ssao_light_affect": 0.08,
                    "ssil_enabled": false,
                    "sdfgi_enabled": false,
                    "glow_enabled": true,
                    "glow_intensity": 0.78,
                    "glow_bloom": 0.16,
                    "fog_enabled": true,
                    "fog_light_color": Color(0.972549, 0.9647059, 0.9529412, 1.0),
                    "fog_sun_scatter": 0.26,
                    "fog_density": 0.072,
                    "fog_sky_affect": 0.06,
                    "fog_depth_curve": 0.28,
                    "fog_depth_begin": 5.0,
                    "fog_depth_end": 500.0,
                    "volumetric_fog_enabled": true,
                    "volumetric_fog_density": 0.009,
                    "volumetric_fog_gi_inject": 0.8,
                    "volumetric_fog_anisotropy": 0.25,
                    "volumetric_fog_length": 5.0,
                    "volumetric_fog_ambient_inject": 0.08,
                    "volumetric_fog_sky_affect": 0.54,
                    "adjustment_saturation": 0.87,
                    "fog_controller_max_density": 0.009,
                },
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
                "camera": {
                    "auto_exposure_scale": 0.32,
                    "auto_exposure_speed": 2.0,
                    "auto_exposure_min_sensitivity": 85.0,
                    "auto_exposure_max_sensitivity": 300.0,
                },
                "environment": {
                    "ambient_light_energy": 2.22,
                    "tonemap_exposure": 1.26,
                    "tonemap_white": 9.0,
                    "tonemap_agx_contrast": 1.44,
                    "ssao_enabled": false,
                    "ssao_light_affect": 0.0,
                    "ssil_enabled": false,
                    "sdfgi_enabled": false,
                    "glow_enabled": false,
                    "glow_intensity": 0.0,
                    "glow_bloom": 0.0,
                    "fog_enabled": true,
                    "fog_light_color": Color(0.9529412, 0.94509804, 0.9372549, 1.0),
                    "fog_sun_scatter": 0.18,
                    "fog_density": 0.062,
                    "fog_sky_affect": 0.04,
                    "fog_depth_curve": 0.23,
                    "fog_depth_begin": 6.5,
                    "fog_depth_end": 460.0,
                    "volumetric_fog_enabled": false,
                    "volumetric_fog_density": 0.0,
                    "volumetric_fog_gi_inject": 0.0,
                    "volumetric_fog_anisotropy": 0.0,
                    "volumetric_fog_length": 4.0,
                    "volumetric_fog_ambient_inject": 0.0,
                    "volumetric_fog_sky_affect": 0.0,
                    "adjustment_saturation": 0.87,
                    "fog_controller_max_density": -1.0,
                },
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


func _apply_environment_profile(settings: Dictionary) -> void:
    if _environment == null:
        return

    _environment.ambient_light_energy = settings["ambient_light_energy"]
    _environment.tonemap_exposure = settings["tonemap_exposure"]
    _environment.tonemap_white = settings["tonemap_white"]
    _environment.tonemap_agx_contrast = settings["tonemap_agx_contrast"]
    _environment.ssao_enabled = settings["ssao_enabled"]
    _environment.ssao_light_affect = settings["ssao_light_affect"]
    _environment.ssil_enabled = settings["ssil_enabled"]
    _environment.sdfgi_enabled = settings["sdfgi_enabled"]
    _environment.glow_enabled = settings["glow_enabled"]
    _environment.glow_intensity = settings["glow_intensity"]
    _environment.glow_bloom = settings["glow_bloom"]
    _environment.fog_enabled = settings["fog_enabled"]
    _environment.fog_light_color = settings["fog_light_color"]
    _environment.fog_sun_scatter = settings["fog_sun_scatter"]
    _environment.fog_density = settings["fog_density"]
    _environment.fog_sky_affect = settings["fog_sky_affect"]
    _environment.fog_depth_curve = settings["fog_depth_curve"]
    _environment.fog_depth_begin = settings["fog_depth_begin"]
    _environment.fog_depth_end = settings["fog_depth_end"]
    _environment.volumetric_fog_enabled = settings["volumetric_fog_enabled"]
    _environment.volumetric_fog_density = settings["volumetric_fog_density"]
    _environment.volumetric_fog_gi_inject = settings["volumetric_fog_gi_inject"]
    _environment.volumetric_fog_anisotropy = settings["volumetric_fog_anisotropy"]
    _environment.volumetric_fog_length = settings["volumetric_fog_length"]
    _environment.volumetric_fog_ambient_inject = settings["volumetric_fog_ambient_inject"]
    _environment.volumetric_fog_sky_affect = settings["volumetric_fog_sky_affect"]
    _environment.adjustment_saturation = settings["adjustment_saturation"]

    if _auto_biomes_fog != null:
        _auto_biomes_fog.max_density = settings["fog_controller_max_density"]
        _auto_biomes_fog.call_deferred("_sample_and_apply_fog")


func _apply_camera_profile(settings: Dictionary) -> void:
    if _camera_attributes == null:
        return

    _camera_attributes.auto_exposure_scale = settings["auto_exposure_scale"]
    _camera_attributes.auto_exposure_speed = settings["auto_exposure_speed"]
    _camera_attributes.auto_exposure_min_sensitivity = settings["auto_exposure_min_sensitivity"]
    _camera_attributes.auto_exposure_max_sensitivity = settings["auto_exposure_max_sensitivity"]


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
