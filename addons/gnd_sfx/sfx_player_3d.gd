@tool
extends Node3D
class_name SfxPlayer3D

signal finished

@export var events: Array[SfxEvent] = []

@export var max_tracks: int = 1:
    set(value):
        max_tracks = value
        sync_values(true)

@export var attenuation_model: AudioStreamPlayer3D.AttenuationModel = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE:
    set(value):
        attenuation_model = value
        sync_values()

@export_range(0.01, 100.0, 0.01) var unit_size: float = 10:
    set(value):
        unit_size = value
        sync_values()

@export var max_distance_m: int = 0:
    set(value):
        max_distance_m = value
        sync_values()

@export var max_polyphony: int = 1:
    set(value):
        max_polyphony = value
        sync_values()

@export_range(0.0, 3.0) var panning_strength: float = 1.0:
    set(value):
        panning_strength = value
        sync_values()

var _players: Array[AudioStreamPlayer3D] = []
var _active_players: Array[AudioStreamPlayer3D] = []
var _players_in_use = 0
var _players_needs_rebuild = true

func _update_players_in_use_debug(delta: int) -> void:
    _players_in_use = _active_players.size()
    print("PLAYER %s %s" % [("+1" if delta > 0 else "-1"), _players_in_use])

func _get_available_player() -> AudioStreamPlayer3D:
    for player in _players:
        if not _active_players.has(player):
            return player
    return null

func sync_values(rebuild=false) -> void:
    if Engine.is_editor_hint():
        return

    if rebuild:
        for player in _players:
            player.stop()
            remove_child(player)
            player.queue_free()
        _players = []
        _active_players = []
        _players_in_use = 0
        var i = 0
        while i < max_tracks:
            var player = AudioStreamPlayer3D.new()
            _players.append(player)
            add_child(player)
            player.finished.connect(_on_player_finished.bind(player))
            i += 1

    for player in _players:
        player.max_polyphony = max_polyphony
        player.max_distance = max_distance_m
        player.panning_strength = panning_strength
        player.attenuation_model = attenuation_model
        player.unit_size = unit_size


func _ready() -> void:
    sync_values(true)

func _on_player_finished(player: AudioStreamPlayer3D):
    var index = _active_players.find(player)
    if index == -1:
        return

    _active_players.remove_at(index)
    _update_players_in_use_debug(-1)

func _stop_all_players():
    for player in _players:
        player.stop()
    _active_players = []
    _players_in_use = 0

func play(event_name: StringName, parameters: Dictionary = {}) -> void:
    if not event_name:
        return
    for event in events:
        if event.name == event_name:
            #_stop_all_players()
            for track in event.tracks:
                var player = _get_available_player()
                if not player:
                    break

                var stream = track.get_next_audio_stream()
                if stream:
                    player.stream = stream
                    player.bus = track.audio_bus
                    _active_players.append(player)
                    player.play()
                    _update_players_in_use_debug(1)
            return
    push_error("Unknown sound event ", event_name)

func stop() -> void:
    _stop_all_players()
