extends Resource
class_name QualityProfile

@export var id: StringName = &""
@export var name: String = ""
@export var scaling_3d_mode: Viewport.Scaling3DMode = Viewport.SCALING_3D_MODE_BILINEAR
@export_range(0.1, 1.0, 0.01) var scaling_3d_scale: float = 1.0
@export_range(0.0, 2.0, 0.01) var fsr_sharpness: float = 0.0
@export var use_taa: bool = false
@export var msaa_3d: Viewport.MSAA = Viewport.MSAA_DISABLED
@export var screen_space_aa: Viewport.ScreenSpaceAA = Viewport.SCREEN_SPACE_AA_DISABLED
@export var background_energy_multiplier: float = 1.0
@export var tonemap_exposure: float = 1.0
@export var tonemap_white: float = 1.0
@export var tonemap_agx_contrast: float = 1.0
@export var ssao_enabled: bool = false
@export var ssao_light_affect: float = 0.0
@export var ssil_enabled: bool = false
@export var sdfgi_enabled: bool = false
@export var glow_enabled: bool = false
@export var glow_intensity: float = 0.0
@export var glow_bloom: float = 0.0
@export var volumetric_fog_enabled: bool = false
@export var adjustment_saturation: float = 1.0
@export var adjustment_color_correction: Texture3D
@export var auto_exposure_enabled: bool = false
@export var auto_exposure_scale: float = 0.4
@export var auto_exposure_speed: float = 0.5
@export var auto_exposure_min_sensitivity: float = 0.0
@export var auto_exposure_max_sensitivity: float = 800.0
