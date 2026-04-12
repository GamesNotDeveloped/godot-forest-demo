extends UP_PlayerBase
class_name UP_FPSController_Prefab

# most common signals of Prefab

signal footstep(leg: int)
signal floor_changed(floor: Node3D)
signal landed(velocity: Vector3)
signal item_collected(item: Node3D)
signal interacted_with(target)
signal interaction_target(target)
signal killed

var _dirty = false
var _remote_transform_target: NodePath = NodePath("")
# high level interface of Prefab

@export_category("Initialization")
@export var start_marker:Marker3D
@export_node_path("Node3D") var remote_transform_target: NodePath = NodePath(""):
    set(x):
        _remote_transform_target = x
        _sync_remote_transform_target()
    get:
        return _remote_transform_target

@export_category("Features")
@export var bobbing_enabled:bool = true:
    set(x):
        bobbing_enabled = x
        _dirty = true

@export var zoom_enabled:bool = true:
    set(x):
        zoom_enabled = x
        _dirty = true

@export var kill_y_enabled:bool = true:
    set(x):
        kill_y_enabled = x
        _dirty = true

@export var kill_y_position:float = -10.0:
    set(x):
        kill_y_position = x
        _dirty = true

@export_category("Movement")
@export var enable_walk:bool = true:
    set(x):
        enable_walk = x
        _dirty = true
@export var enable_run:bool = true:
    set(x):
        enable_run = x
        _dirty = true
@export var enable_jump:bool = true:
    set(x):
        enable_jump = x
        _dirty = true
@export var enable_crouch:bool = true:
    set(x):
        enable_crouch = x
        _dirty = true
@export var always_run:bool = false:
    set(x):
        always_run = x
        _dirty = true

@export_range(-5, 5) var gravity_factor:float = 1.0:
    set(x):
        gravity_factor = x
        _dirty = true

@export_range(0.01, 10) var speed_factor:float = 1.0:
    set(x):
        speed_factor = x
        _dirty = true

@export_range(0.01, 1) var hurry_factor:float = 0.2:
    set(x):
        hurry_factor = x
        _dirty = true

@export_range(0.01, 10) var jump_factor:float = 1.0:
    set(x):
        jump_factor = x
        _dirty = true

@export_range(0.01, 10) var footstep_time_factor:float = 0.8:
    set(x):
        footstep_time_factor = x
        _dirty = true

@export_range(0.0, 100.0) var push_factor:float = 1.0:
    set(x):
        push_factor = x
        _dirty = true

@export_category("Health & Damage")
@export var max_health:float = 10.0:
    set(x):
        max_health = x
        _dirty = true

@export var immortal:bool = false:
    set(x):
        immortal = x
        _dirty = true

@export var respawn_type:UP_Killable.RespawnType = UP_Killable.RespawnType.RespawnLastGood:
    set(x):
        respawn_type = x
        _dirty = true

@export_category("Visuals")
@export_range(0.0, 10.0) var bob_strength_factor:float = 0.8:
    set(x):
        bob_strength_factor = x
        _dirty = true

@export_range(0.0, 5.0) var nervous:float = 1.0:
    set(x):
        nervous = x
        _dirty = true

@export_range(0.0, 32768.0) var camera_far:float = 1000.0:
    set(x):
        camera_far = x
        _dirty = true

@export_range(0.01, 10.0) var player_fatness:float = 1.0:
    set(x):
        player_fatness = x
        _dirty = true

@export_range(0.01, 10.0) var player_scale:float = 1.0:
    set(x):
        player_scale = x
        _dirty = true

@export_category("Controls")
@export var mouse_sensitivity_factor:float = 1.0:
    set(x):
        mouse_sensitivity_factor = x
        _dirty = true

@export_range(0.05, 1.0) var hardness:float = 0.8:
    set(x):
        hardness = x
        _dirty = true

@export_range(0, 90) var head_rotation_min = 20.0
@export_range(90, 180) var head_rotation_max = 180.0

@export_category("Interaction")
@export_flags_3d_physics var collecting_collision_mask = 2
@export_flags_3d_physics var interaction_collision_mask = 4

var _defaults = {}
func _get_default(key, default):
    if not _defaults.has(key):
        _defaults[key] = default
    return _defaults[key]


func _apply_settings():
    # features

    $Bobbing.active = bobbing_enabled
    $Zooming.active = zoom_enabled
    $Kill_Y.active = kill_y_enabled
    $Kill_Y.global_y_position = kill_y_position

    # enable movements

    $Walking.ALWAYS_RUN = always_run
    $Walking.enable_walk = enable_walk
    $Walking.enable_run = enable_run
    $Walking.enable_jump = enable_jump
    $Walking.enable_crouch = enable_crouch

    # gravity factor

    $Walking.GRAVITY = _get_default("walking_gravity", $Walking.GRAVITY) * gravity_factor

    # speed factor

    $Walking.WALK_SPEED = _get_default("walk_speed", $Walking.WALK_SPEED) * speed_factor
    $Walking.RUN_SPEED = _get_default("run_speed", $Walking.RUN_SPEED) * speed_factor
    $Walking.CROUCH_SPEED = _get_default("crouch_speed", $Walking.CROUCH_SPEED) * speed_factor

    # hurry factor
    #var def_walk = _get_default("walk_speed", $Walking.WALK_SPEED)
    var def_walk = $Walking.WALK_SPEED
    $Walking.WALK_SPEED = def_walk + ($Walking.RUN_SPEED-def_walk) * hurry_factor

    # jump factor

    var def_jump = _get_default("jump_speed", $Walking.JUMP_SPEED)
    var def_jump_run = _get_default("jump_speed_run", $Walking.JUMP_SPEED_RUN)

    $Walking.JUMP_SPEED = def_jump * jump_factor
    $Walking.JUMP_SPEED_RUN = def_jump_run * jump_factor

    # footstep time factor

    $Walking.walk_footstep_time_factor = _get_default("walk_footstep_time_factor", $Walking.walk_footstep_time_factor) * footstep_time_factor
    $Walking.run_footstep_time_factor = _get_default("run_footstep_time_factor", $Walking.run_footstep_time_factor) * footstep_time_factor
    $Walking.crouch_footstep_time_factor = _get_default("crouch_footstep_time_factor", $Walking.crouch_footstep_time_factor) * footstep_time_factor

    # max health
    $Health.max_health = max_health

    # immortal
    $Killable.active = not immortal
    $Kill_Y.active = not immortal

    # respawn type
    $Killable.respawn_type = respawn_type

    # bob strength factor
    $Walking.BOB_STRENGTH = bob_strength_factor

    # nervous
    $Walking.BOB_STAY_FACTOR = _get_default("walking_bob_stay_factor", $Walking.BOB_STAY_FACTOR) * nervous
    $Walking.BOB_STAY_SHAKINESS = _get_default("walking_bob_stay_shakiness", $Walking.BOB_STAY_SHAKINESS) * pow(nervous, 2)

    # camera far
    $RotationHelper/Camera.far = camera_far

    # fatness
    $CollisionShape3D.shape.radius = _get_default("collision_shape_radius", $CollisionShape3D.shape.radius) * player_scale * player_fatness

    # mouse sensitivity
    $HeadRotation.MOUSE_SENSITIVITY = _get_default("head_rotation_mouse_sensitivity", $HeadRotation.MOUSE_SENSITIVITY) * mouse_sensitivity_factor

    # hardness
    $Walking.ACCEL = hardness
    $Walking.FRICTION = clampf(0.5 * hardness, 0.0, 1.0)
    $HeadRotation.mouse_rotation_friction = clampf(hardness * 1.2, 0, 1.0)
    $HeadRotation.LOOK_FRICTION = clampf(hardness * 1.2, 0, 1.0)

    # head rotation limits

    $HeadRotation.HEAD_ANGLE_RANGE = Vector2(head_rotation_min, head_rotation_max)

    # scale
    var shape = $CollisionShape3D.shape
    shape.height = _get_default("collision_shape_height", $CollisionShape3D.shape.height) * player_scale
    shape.radius = _get_default("collision_shape_radius", $CollisionShape3D.shape.radius) * player_scale * player_fatness
    $CollisionShape3D.shape = shape
    $CollisionShape3D.position.y = shape.height * 0.5
    $RotationHelper.position.y = _get_default("rotation_helper_position_y", $RotationHelper.position.y) * player_scale

    # autoscale speeds (use other property than player_scale?)
    var inv_player_scale:float = 1.0/player_scale
    $Walking.WALK_SPEED *= player_scale
    $Walking.RUN_SPEED *= player_scale
    $Walking.CROUCH_SPEED *= player_scale
    $Walking.GRAVITY *= player_scale
    $Walking.JUMP_SPEED *= player_scale
    $Walking.JUMP_SPEED_RUN *= player_scale
    $Walking.walk_footstep_time_factor *= inv_player_scale
    $Walking.run_footstep_time_factor *= inv_player_scale
    $Walking.crouch_footstep_time_factor *= inv_player_scale

    # Interaction
    $Collect.collision_mask = collecting_collision_mask
    $Interaction.collision_mask = interaction_collision_mask

    # Pushing
    push_force = _get_default("base_push_force", push_force) * push_factor


func _sync_remote_transform_target() -> void:
    var remote_transform := get_node_or_null("RotationHelper/RemoteTransform3D") as RemoteTransform3D
    if remote_transform == null:
        return

    if _remote_transform_target.is_empty():
        remote_transform.remote_path = NodePath("")
        return

    var target := get_node_or_null(_remote_transform_target) as Node3D
    if target == null:
        push_warning("Remote transform target not found: %s" % _remote_transform_target)
        remote_transform.remote_path = NodePath("")
        return

    remote_transform.remote_path = remote_transform.get_path_to(target)


func _ready():
    _apply_settings()
    _sync_remote_transform_target()
    $Walking.footstep.connect(func(leg): footstep.emit(leg))
    $Walking.land.connect(func(vel): landed.emit(vel))
    $DetectFloorChange.floor_changed.connect(func(floor): floor_changed.emit(floor))
    $Collect.collected.connect(func(x): item_collected.emit(x))
    $Interaction.pressed.connect(func(x): interacted_with.emit(x))
    $Interaction.target_changed.connect(func(x): interaction_target.emit(x))
    $Killable.killed.connect(func(): killed.emit())

    if start_marker:
        global_transform = start_marker.global_transform
        $HeadRotation.target_basis = start_marker.global_basis

func _process(delta):

    if _dirty:
        _dirty = false

        _apply_settings()

func _on_walking_crouch(enabled):
    if enabled:
        $CollisionShape3D.shape.height *= 0.5
    else:
        $CollisionShape3D.shape.height *= 2.0


func _on_item_collected(item):
    if item and item.has_method("collect"):
        item.collect()
        if item is UP_Gun and item.gun:
            var weapon = item.gun.instantiate()
            $ItemHolder.operating_started.connect(weapon.fire_start)
            $ItemHolder.operating_finished.connect(weapon.fire_end)
            $ItemHolder.item = weapon
