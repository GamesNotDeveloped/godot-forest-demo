@tool
extends Resource
class_name SfxAutomation

@export var parameter_name : StringName = "":
    set(value):
        parameter_name = value
        emit_changed()

@export var tracks : Array[SfxTrack]:
    set(value):
        tracks = value
        emit_changed()

@export var audio_bus : StringName:
    set(value):
        audio_bus = value
        emit_changed()

@export var fade_in_curve: Curve:
    set(value):
        fade_in_curve = value
        emit_changed()

@export var fade_out_curve: Curve:
    set(value):
        fade_out_curve = value
        emit_changed()

@export var pitch_curve: Curve:
    set(value):
        pitch_curve = value
        emit_changed()

@export var min_domain = 0.0:
    set(value):
        min_domain = value
        emit_changed()

@export var max_domain = 1.0:
    set(value):
        max_domain = value
        emit_changed()
