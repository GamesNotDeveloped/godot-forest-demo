extends VBoxContainer

@export_node_path("UP_FPSController_Prefab") var fps_player_controller_path:NodePath

var _controller:UP_FPSController_Prefab


func _ready():
    if fps_player_controller_path:
        _controller = get_node(fps_player_controller_path)

        $HudHealth.health_behaviour = _controller.get_node("Health")
        _controller.get_node("Killable").killed.connect(
            func(): $YouDied.visible = true; $YouDied/YouDiedTimer.start()
        )


func _on_you_died_timer_timeout() -> void:
    $YouDied.visible = false
