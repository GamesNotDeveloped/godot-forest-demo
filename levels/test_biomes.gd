extends Node3D

func _ready():
    var env:Environment = $WorldEnvironment.environment
    if env:
        env.volumetric_fog_enabled = true
