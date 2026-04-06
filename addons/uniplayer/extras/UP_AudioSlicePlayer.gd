extends AudioStreamPlayer
class_name UP_AudioStreamSlicePlayer

@export var slices: PackedVector2Array = PackedVector2Array()
@export var slice: int = 0
@export var pitch_range: Vector2 = Vector2(1.0, 1.0)
@export var randomize_pitch: bool = false
@export var next_slice:NextSliceStrategy = NextSliceStrategy.Next
enum NextSliceStrategy {Same, Next, Random}

const STRATEGY_MAP = {
    0: NextSliceStrategy.Same,
    1: NextSliceStrategy.Next,
    2: NextSliceStrategy.Random,
}


signal stop_playing

@export var pitch_min: float = 1.0
@export var pitch_max: float = 1.0
@export var polyphony: int = 4



var _audioplayer:AudioStreamPlayer


var _timers:Array = []
var _current_audioplayer:int = 0
var _players:Array = []

func _enter_tree():
    pass


func _exit_tree() -> void:
    for x in _players:
        remove_child(x)
        x.queue_free()
    _players.clear()


func _on_play_timer_timeout(player, timer):
    if is_instance_valid(player):
        player.stop()
    remove_child(timer)
    timer.queue_free()

func _ready():
    _players.clear()
    for i in range(polyphony):
        _players.append(self.duplicate(0))
    for x in _players:
        add_child(x)


func play_slice(slice_number=null, offset=0.0):
    if not _players.size():
        return

    if not slice_number == null:
        slice = slice_number

    _current_audioplayer = wrapi(_current_audioplayer+1, 0, _players.size())
    var _player = _players[_current_audioplayer]
    var _timer = Timer.new()
    _timer.one_shot = true
    _timer.connect("timeout", Callable(_on_play_timer_timeout).bind(_player, _timer))
    add_child(_timer)

    var _start = 0.0
    var _length = 0.0
    var _usetimer = true

    if slices.size() > 0:
        var _range = slices[slice]
        _start = _range.x+offset
        _length = _range.y-_start
    else:
        _length = _player.stream.get_length()
        _usetimer = false

    if randomize_pitch:
        _player.pitch_scale = randf_range(pitch_min, pitch_max)

    if _usetimer or not _timer.is_stopped():
        _timer.stop()

    if _usetimer and _length > 0:
        _timer.wait_time = _length
        _timer.start()

    _player.play(_start)


    if next_slice == NextSliceStrategy.Next:
        slice = wrapi(slice+1, 0, slices.size())
    elif next_slice == NextSliceStrategy.Random:
        slice = randi() % slices.size()
