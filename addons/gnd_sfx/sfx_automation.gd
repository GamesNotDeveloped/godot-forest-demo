extends Resource
class_name SfxAutomation

@export var parameter_name : StringName = ""
@export var tracks : Array[SfxTrack]
@export var audio_bus : StringName
@export var fade_in_curve: Curve
@export var fade_out_curve: Curve
@export var pitch_curve: Curve
@export var min_domain = 0.0
@export var max_domain = 1.0
