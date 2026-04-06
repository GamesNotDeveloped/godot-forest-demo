extends UP_BaseAbility
class_name UP_Kill_Y

# Responsibility;
# - automatically kill the player below specified world Y value

enum ForceRespawnType {UseDefault, RespawnFromStart, RespawnLastGood, Quit}

var _forced_respawn_map = {
    ForceRespawnType.UseDefault: null,
    ForceRespawnType.RespawnFromStart: UP_Killable.RespawnType.RespawnFromStart,
    ForceRespawnType.RespawnLastGood: UP_Killable.RespawnType.RespawnLastGood,
    ForceRespawnType.Quit: UP_Killable.RespawnType.Quit,
}

var _bypass_store_position = false

@export_node_path("UP_Killable") var killable_behaviour_path = NodePath("")
@export var force_respawn_type:ForceRespawnType = ForceRespawnType.UseDefault

@export_range(0.01, 10) var check_interval = 1.0
@export var global_y_position = -10.0

var timer = Timer.new()
var killable_behaviour:UP_Killable

func _ready():
    super()
    killable_behaviour = get_node(killable_behaviour_path)

    if killable_behaviour:
        timer.wait_time = check_interval
        timer.one_shot = false
        timer.timeout.connect(_update)
        add_child(timer)
        timer.start()

        player.register_control_ability(self)
    else:
        push_warning("UP_Kill_Y requires UP_Killable to be set")

func _update():
    if not active:
        return

    if player.global_position.y < global_y_position:
        killable_behaviour.kill(_forced_respawn_map[force_respawn_type])

func _process_control(delta):
    if not active:
        return
    if not _bypass_store_position and player.global_position.y < global_y_position:
        _bypass_store_position = true
        if killable_behaviour:
            killable_behaviour.bypass_store_position = true
    if _bypass_store_position and player.global_position.y > global_y_position:
        _bypass_store_position = false
        if killable_behaviour:
            killable_behaviour.bypass_store_position = false
