@tool
extends EditorPlugin

var default_icon = preload("ability.png")
var visual_icon = preload("visual_ability.png")

var CUSTOM_TYPES = [
    ["Walking", "Node", preload("abilities/UP_Walk.gd"), default_icon],
    ["Zooming", "Node", preload("abilities/UP_Zoom.gd"), default_icon],
    ["HeadRotation", "Node", preload("abilities/UP_HeadRotation.gd"), default_icon],
    ["Bobbing", "Node", preload("abilities/UP_Bobbing.gd"), default_icon],
    ["DisplayInEditorOnly", "Node", preload("behaviours/UP_DisplayInEditorOnly.gd"), default_icon],
    ["Killable", "Node", preload("behaviours/UP_Killable.gd"), default_icon],
    ["Kill_Y", "Node", preload("behaviours/UP_Kill_Y.gd"), default_icon],
    ["Health", "Node", preload("behaviours/UP_Health.gd"), default_icon],
    ["Interaction", "Node", preload("abilities/UP_Interaction.gd"), default_icon],
    ["DetectFloorChange", "Node", preload("abilities/UP_DetectFloorChange.gd"), default_icon],
    ["Collect", "Node3D", preload("abilities/UP_Collect.gd"), visual_icon],
    ["HealthRegeneration", "Node", preload("behaviours/UP_HealthRegeneration.gd"), default_icon],
    ["MouseCapture", "Node", preload("tools/UP_MouseCapture.gd"), preload("mouse.png")],
    ["RotationHelper", "Node3D", preload("tools/UP_RotationHelper.gd"), preload("rotationhelper.png")],
    ["ItemHolder", "Node3D", preload("abilities/UP_ItemHolder.gd"), default_icon],
    ["PlayerStart", "Marker3D", preload("res://addons/uniplayer/tools/UP_PlayerStart.gd"), preload("res://addons/uniplayer/uniplayer.png")],
]

func _enter_tree():
    for item in CUSTOM_TYPES:
        add_custom_type(item[0], item[1], item[2], item[3])


func _exit_tree():
    for item in CUSTOM_TYPES:
        remove_custom_type(item[0])
