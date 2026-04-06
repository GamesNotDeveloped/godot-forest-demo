extends UP_BaseAbility
class_name UP_Killable

# Responsibility:
# - make character killable
# - handle respawning
# - store "last good" player position

signal killed
signal respawned
signal game_stopped

enum RespawnType {DisableControl, RespawnFromStart, RespawnLastGood, EmitStopSignal, Quit}

@export var respawn_type:RespawnType = RespawnType.DisableControl


var initial_transform:Transform3D
var last_good_transform:Transform3D
var bypass_store_position: bool = false
var is_killed:bool = false
var _timer:Timer
var _floor = null


func _ready():
    super()
    initial_transform = player.global_transform
    player.reset.connect(_reset)
    _timer = Timer.new()
    _timer.wait_time = 0.25
    _timer.one_shot = false
    _timer.timeout.connect(store_last_good_position)
    add_child(_timer)
    _timer.start()
    get_parent().floor_changed.connect(on_floor_changed)



func on_floor_changed(floor):
    _floor = floor

func store_last_good_position():
    if _floor and not bypass_store_position:
        last_good_transform = get_parent().global_transform

func kill(force_respawn_type=null):
    if not active:
        return
    is_killed = true

    killed.emit()

    var x = force_respawn_type if force_respawn_type else respawn_type

    match x:
        RespawnType.DisableControl:
            player.controllable = false
        RespawnType.RespawnFromStart:
            player.global_transform = initial_transform
            player.reset.emit()
            is_killed = false
            respawned.emit()
        RespawnType.RespawnLastGood:
            player.global_transform = last_good_transform
            player.reset.emit()
            is_killed = false
            respawned.emit()
        RespawnType.EmitStopSignal:
            game_stopped.emit()
        RespawnType.Quit:
            get_tree().quit()

func _reset():
    is_killed = false
