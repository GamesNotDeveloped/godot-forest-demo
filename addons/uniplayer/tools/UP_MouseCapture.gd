extends UP_Tool
class_name UP_MouseCapture

## Captures the mouse pointer at startup
##
## By default it uses ui_cancel action to toggle between captured and visible state.
## The action can be configured by changing [member action_toggle] property.

## Emmited when mouse mode changes. Provides current captured state as an argument.
signal toggled(captured:bool)


## If true, the mouse pointer is captured.
var captured := true

## Action name to perform a change of the mouse capture state.
@export var action_toggle = "ui_cancel"
@export var pause_target_path = NodePath("")

func _ready():
    _update()
    toggled.connect(self.pause_target)


func _input(event):
    if event.is_action_pressed(action_toggle):
        captured = not captured
        _update()
        toggled.emit(captured)

func _update():
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE

func pause_target(captured:bool):
    if pause_target_path:
        var node = get_node(pause_target_path) as Node
        if node:
            node.process_mode = Node.PROCESS_MODE_INHERIT if captured else Node.PROCESS_MODE_DISABLED
