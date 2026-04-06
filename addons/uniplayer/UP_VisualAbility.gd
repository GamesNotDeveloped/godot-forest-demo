@icon("res://addons/uniplayer/visual_ability.png")

class_name UP_VisualAbility
extends Node3D

## Base class for Godot Uniplayer abilities, which requires adding 3D objects
## to the scene.
#
## An abstract class for creating visual abilities for Godot Uniplayer.
## Visual abilities must be added as a direct children of [UP_PlayerBase].


signal active_toggled

## Reference to the player's character controller.
## It is automatically fetched from the parent node in [method _enter_tree].
var player:UP_PlayerBase

## Get or set the state of the ability.
## Changing the value emits [signal active_toggled] signal.
## Inactive abilities should do nothing and should not consume resources.
@export var active:bool = true:
    set(x):
        active = x
        active_toggled.emit()

func _enter_tree():
    player = get_parent()

func _exit_tree():
    pass

func _ready():
    pass

func _process_control(delta):
    pass

func _process_movement(delta):
    pass
