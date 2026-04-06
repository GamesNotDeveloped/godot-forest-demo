@icon("res://addons/uniplayer/ability.png")

extends UP_BaseAbility
class_name ItemHolder

signal operating()
signal operating_started()
signal operating_finished()
signal item_changed(item)

@export_node_path("Camera3D") var camera_path:NodePath = NodePath("")
@export var ACTION_OPERATE = "operate"


var DEFAULT_ACTIONS = [
    [ACTION_OPERATE, null, MOUSE_BUTTON_LEFT],
]

var camera:Camera3D

var item:Node3D:
    set(x):
        if item:
            item.queue_free()
        item = x
        item_changed.emit(item)
        if camera:
            camera.add_child(item)


func _ready():
    if not Engine.is_editor_hint():
        player.register_control_ability(self)
        player.register_default_input_bindings(DEFAULT_ACTIONS)

        if camera_path:
            camera = get_node(camera_path)


func _process_control(delta):
    if not active:
        return

    if item:
        if Input.is_action_pressed(ACTION_OPERATE):
            operating.emit()
        if Input.is_action_just_pressed(ACTION_OPERATE):
            operating_started.emit()
        elif Input.is_action_just_released(ACTION_OPERATE):
            operating_finished.emit()
