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
@export var environment: Environment
@export var camera_attributes: CameraAttributes
@export var compositor: Compositor
