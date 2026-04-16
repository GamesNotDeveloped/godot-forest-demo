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


func get_automation(automation_name:StringName) -> SfxAutomation:
    for automation in automations:
        if automation.parameter_name == automation_name:
            return automation
    return null
