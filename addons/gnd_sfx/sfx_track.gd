@tool
extends Resource
class_name SfxTrack

@export var stream : AudioStream
@export var fade_in_curve: Curve
@export var fade_out_curve: Curve
@export var audio_bus : StringName
@export var pitch_curve: Curve
