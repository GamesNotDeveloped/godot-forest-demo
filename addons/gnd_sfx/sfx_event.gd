@tool
extends Resource
class_name SfxEvent

@export var tracks: Array[SfxTrack] = []:
    set(value):
        tracks = value
        emit_changed()

@export var name: StringName = "":
    set(value):
        name = value
        emit_changed()

@export var automations: Array[SfxAutomation] = []:
    set(value):
        automations = value
        emit_changed()
