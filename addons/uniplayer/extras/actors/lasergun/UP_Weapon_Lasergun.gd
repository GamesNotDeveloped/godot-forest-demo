extends Node3D

var ball = preload("res://addons/uniplayer/extras/actors/lasergun/ball.tscn")

var _last_shot:float = 0.0
var _firing = false

@export var shoot_delay:float = 0.08:
    set(x):
        shoot_delay = x
        _last_shot = shoot_delay

@export_range(0.1, 100.0) var impulse_force:float = 20.0


func fire_start():
    _firing = true

func fire_end():
    _firing = false
    _last_shot = shoot_delay

func _process(delta):
    if _firing:
        _last_shot += delta
        if _last_shot > shoot_delay:
            _last_shot = 0
            var b:RigidBody3D = ball.instantiate() as RigidBody3D
            get_tree().root.add_child(b)

            var _t = Timer.new()
            add_child(_t)

            _t.timeout.connect(b.queue_free)
            _t.wait_time = 10.0
            _t.one_shot = true
            _t.start()
            $Shoot.play_slice()
            b.global_position = $BallStart.global_position
            b.apply_central_impulse($BallStart.global_transform.basis * Vector3(0, 0, -impulse_force))


