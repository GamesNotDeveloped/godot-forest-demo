extends Control

@export_node_path("UP_Health") var health_path:NodePath = NodePath("")

var health_behaviour:UP_Health:
    set(x):
        health_behaviour = x
        if health_behaviour:
            health_behaviour.health_changed.connect(_update)
            $%ProgressBar.max_value = health_behaviour.max_health
            _update()

func _ready():
    if health_path:
        health_behaviour = get_node(health_path)

func _update():
    $%ProgressBar.value = health_behaviour.health
