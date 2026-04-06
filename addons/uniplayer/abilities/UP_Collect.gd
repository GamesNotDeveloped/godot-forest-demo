@tool
extends UP_VisualAbility

signal collected(body:Node3D)

# Creates Area3D with Sphere collision shape around the player.
# Emits `collected` signal when body from masked layer enters into area.

var _dirty:bool = false
var _area:Area3D

@export_range(0.01, 10) var radius:float = 1.0:
    set(x):
        radius = x
        _dirty = true
@export_flags_3d_physics var collision_mask = 2

func _create_collision_shape() -> CollisionShape3D:
    var coll = CollisionShape3D.new()
    var sphere = SphereShape3D.new()
    sphere.radius = radius
    coll.shape = sphere
    return coll

func _update_area():
    if _area:
        _area.get_child(0).shape.radius = radius

func _enter_tree() -> void:
    _area = Area3D.new()
    _area.collision_mask = collision_mask
    add_child(_area)
    _area.add_child(_create_collision_shape())
    _area.body_entered.connect(func(body): collected.emit(body))

func _exit_tree() -> void:
    if _area:
        remove_child(_area)
        #_area.queue_free()
        _area = null

func _process_control(delta):
    if not active:
        return


func _process(delta):
    if Engine.is_editor_hint() and _dirty:
        _update_area()
        _dirty = false
