extends UP_CollectibleItem
class_name UP_Gun

@export var gun:PackedScene



func collect():
    collected.emit()
    visible = false
    queue_free()
