extends StaticBody3D
class_name UP_CollectibleItem

signal collected

enum ItemTypes {DEFAULT, GUN}

@export var sound_name:String = ""
@export var type:ItemTypes = ItemTypes.DEFAULT

@export var enable_rotate:bool = true
@export var points:int = 0

func collect():
    collected.emit()
    visible = false
    queue_free()


func _process(delta: float) -> void:
    if enable_rotate:
        rotate_y(deg_to_rad(1))
