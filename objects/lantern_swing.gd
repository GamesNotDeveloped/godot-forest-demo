extends RigidBody3D

@export var wind_strength_multiplier: float = 0.5
@export var oscillation_speed: float = 2.0

func _physics_process(_delta: float) -> void:
	var wind_dir = WeatherServer.get_global_wind_direction() # Vector2
	var wind_speed = WeatherServer.get_global_wind_speed()
	
	# Convert wind_dir (Vector2) to Vector3
	var wind_v3 = Vector3(wind_dir.x, 0, wind_dir.y).normalized()
	
	# Apply a small force based on wind
	var time = Time.get_ticks_msec() * 0.001
	var force = wind_v3 * wind_speed * wind_strength_multiplier
	
	# Add some periodic movement to simulate wind gusts
	var gust = sin(time * oscillation_speed) * 0.5 + 0.5
	force *= gust
	
	apply_central_force(force)
