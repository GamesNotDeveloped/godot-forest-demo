@tool
extends Node3D
class_name SfxPlayer3D

enum VoiceType { TRACK, AUTOMATION }

class ActiveVoice:
    var voice_type: VoiceType = VoiceType.TRACK
    var player: AudioStreamPlayer3D
    var track: SfxTrack
    var sfx_stream: SfxStream
    var stream_length := 0.0
    var manual_fade_out_started := false
    var manual_fade_out_elapsed := 0.0
    var event_name: StringName = &""
    var automation_name: StringName = &""
    var automation: SfxAutomation
    var automation_value := 0.0

signal finished

@export var events: Array[SfxEvent] = []

@export var max_tracks: int = 10:
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
var _active_voices: Array[ActiveVoice] = []
var _players_in_use = 0
var _players_needs_rebuild = true

func _update_players_in_use_debug(delta: int) -> void:
    _players_in_use = _active_voices.size()
    print("PLAYER %s %s" % [("+1" if delta > 0 else "-1"), _players_in_use])

func _find_active_voice_index(player: AudioStreamPlayer3D) -> int:
    for index in range(_active_voices.size()):
        if _active_voices[index].player == player:
            return index
    return -1

func _find_automation_voice_index(event_name: StringName, automation_name: StringName) -> int:
    for index in range(_active_voices.size()):
        var voice = _active_voices[index]
        if voice.voice_type != VoiceType.AUTOMATION:
            continue
        if voice.event_name == event_name and voice.automation_name == automation_name:
            return index
    return -1

func _is_automation_voice(voice: ActiveVoice, event_name: StringName, automation_name: StringName) -> bool:
    return (
        voice.voice_type == VoiceType.AUTOMATION
        and voice.event_name == event_name
        and voice.automation_name == automation_name
    )

func _requires_process() -> bool:
    for voice in _active_voices:
        if voice.voice_type == VoiceType.TRACK:
            return true
    return false

func _get_available_player() -> AudioStreamPlayer3D:
    for player in _players:
        if _find_active_voice_index(player) == -1:
            return player
    return null

func _find_event(event_name: StringName) -> SfxEvent:
    for event in events:
        if event.name == event_name:
            return event
    return null

func _find_automation(event_name: StringName, automation_name: StringName) -> SfxAutomation:
    var event = _find_event(event_name)
    if event == null:
        return null

    for automation in event.automations:
        if automation.parameter_name == automation_name:
            return automation

    return null

func _resolve_audio_bus(bus_name: StringName) -> StringName:
    return &"Master" if String(bus_name).is_empty() else bus_name

func sync_values(rebuild=false) -> void:
    if Engine.is_editor_hint():
        return

    if rebuild:
        for player in _players:
            player.stop()
            remove_child(player)
            player.queue_free()
        _players = []
        _active_voices = []
        _players_in_use = 0
        set_process(false)
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
    set_process(false)

func _on_player_finished(player: AudioStreamPlayer3D):
    _release_voice(_find_active_voice_index(player))

func _get_curve_duration(curve: Curve) -> float:
    if curve == null:
        return 0.0
    return maxf(curve.max_domain - curve.min_domain, 0.0)

func _sample_curve_gain(curve: Curve, elapsed: float) -> float:
    if curve == null:
        return 1.0

    var duration = _get_curve_duration(curve)
    if duration <= 0.0:
        return clampf(curve.sample_baked(curve.max_domain), 0.0, 1.0)

    var sample_position = curve.min_domain + clampf(elapsed, 0.0, duration)
    return clampf(curve.sample_baked(sample_position), 0.0, 1.0)

func _get_voice_base_gain(voice: ActiveVoice) -> float:
    return voice.sfx_stream.base_gain if voice.sfx_stream != null else 1.0

func _set_player_gain(player: AudioStreamPlayer3D, gain: float, base_gain: float = 1.0) -> void:
    player.volume_db = linear_to_db(maxf(gain * maxf(base_gain, 0.0), 0.0001))

func _sample_automation_curve(curve: Curve, automation: SfxAutomation, value: float, default_value: float) -> float:
    if curve == null:
        return default_value

    var input_min = minf(automation.min_domain, automation.max_domain)
    var input_max = maxf(automation.min_domain, automation.max_domain)
    var clamped_value = clampf(value, input_min, input_max)

    if is_equal_approx(input_min, input_max):
        return curve.sample_baked(curve.min_domain)

    var weight = inverse_lerp(input_min, input_max, clamped_value)
    var sample_position = lerpf(curve.min_domain, curve.max_domain, weight)
    return curve.sample_baked(sample_position)

func _apply_automation_value(voice: ActiveVoice) -> void:
    if voice.automation == null or voice.track == null or not is_instance_valid(voice.player):
        return

    var fade_in_gain = _sample_automation_curve(voice.track.fade_in_curve, voice.automation, voice.automation_value, 1.0)
    var fade_out_gain = _sample_automation_curve(voice.track.fade_out_curve, voice.automation, voice.automation_value, 1.0)
    var pitch = _sample_automation_curve(voice.track.pitch_curve, voice.automation, voice.automation_value, 1.0)

    _set_player_gain(
        voice.player,
        clampf(fade_in_gain, 0.0, 1.0) * clampf(fade_out_gain, 0.0, 1.0),
        _get_voice_base_gain(voice)
    )
    voice.player.pitch_scale = maxf(pitch, 0.01)

func _release_voice(index: int) -> void:
    if index == -1:
        return

    var voice = _active_voices[index]
    if is_instance_valid(voice.player):
        voice.player.volume_db = 0.0
        voice.player.pitch_scale = 1.0
    _active_voices.remove_at(index)
    _update_players_in_use_debug(-1)
    set_process(_requires_process())

func _stop_voice(index: int) -> void:
    if index == -1:
        return

    var voice = _active_voices[index]
    _release_voice(index)
    if is_instance_valid(voice.player):
        voice.player.stop()

func _update_track_voice(index: int, delta: float) -> bool:
    if index < 0 or index >= _active_voices.size():
        return false

    var voice = _active_voices[index]
    if not is_instance_valid(voice.player) or not voice.player.playing:
        _release_voice(index)
        return false

    var playback_position = voice.player.get_playback_position()
    var fade_in_gain = _sample_curve_gain(voice.track.fade_in_curve, playback_position)
    var fade_out_gain = 1.0
    var fade_out_duration = _get_curve_duration(voice.track.fade_out_curve)

    if voice.manual_fade_out_started:
        voice.manual_fade_out_elapsed += delta
        fade_out_gain = _sample_curve_gain(voice.track.fade_out_curve, voice.manual_fade_out_elapsed)
        if fade_out_duration <= 0.0 or voice.manual_fade_out_elapsed >= fade_out_duration:
            _stop_voice(index)
            return false
    elif voice.stream_length > 0.0 and fade_out_duration > 0.0:
        var remaining = maxf(voice.stream_length - playback_position, 0.0)
        if remaining <= fade_out_duration:
            fade_out_gain = _sample_curve_gain(voice.track.fade_out_curve, fade_out_duration - remaining)

        if playback_position >= voice.stream_length:
            _stop_voice(index)
            return false

    _set_player_gain(voice.player, fade_in_gain * fade_out_gain, _get_voice_base_gain(voice))
    return true

func _update_voice(index: int, delta: float) -> bool:
    if index < 0 or index >= _active_voices.size():
        return false

    var voice = _active_voices[index]
    if voice.voice_type == VoiceType.AUTOMATION:
        if not is_instance_valid(voice.player) or not voice.player.playing:
            _release_voice(index)
            return false
        return true

    return _update_track_voice(index, delta)

func _process(delta: float) -> void:
    for index in range(_active_voices.size() - 1, -1, -1):
        _update_voice(index, delta)

func _stop_all_players():
    for player in _players:
        player.stop()
        player.pitch_scale = 1.0
        player.volume_db = 0.0
    _active_voices = []
    _players_in_use = 0
    set_process(false)

func _stop_track_voices(immediate: bool) -> void:
    for index in range(_active_voices.size() - 1, -1, -1):
        var voice = _active_voices[index]
        if voice.voice_type != VoiceType.TRACK:
            continue

        if immediate:
            _stop_voice(index)
            continue

        if voice.manual_fade_out_started:
            continue

        if _get_curve_duration(voice.track.fade_out_curve) <= 0.0:
            _stop_voice(index)
            continue

        voice.manual_fade_out_started = true
        voice.manual_fade_out_elapsed = 0.0

func play(event_name: StringName, parameters: Dictionary = {}) -> void:
    if not event_name:
        return
    var event = _find_event(event_name)
    if event:
        #_stop_all_players()
        for track in event.tracks:
            var player = _get_available_player()
            if not player:
                break

            var sfx_stream = track.get_next_sfx_stream()
            var stream = sfx_stream.stream if sfx_stream else null
            if stream:
                player.stream = stream
                player.bus = _resolve_audio_bus(track.audio_bus)
                player.pitch_scale = 1.0
                var voice = ActiveVoice.new()
                voice.voice_type = VoiceType.TRACK
                voice.player = player
                voice.track = track
                voice.sfx_stream = sfx_stream
                voice.stream_length = maxf(stream.get_length(), 0.0)
                _active_voices.append(voice)
                _set_player_gain(player, _sample_curve_gain(track.fade_in_curve, 0.0), _get_voice_base_gain(voice))
                player.play()
                set_process(true)
                _update_players_in_use_debug(1)
        return
    push_error("Unknown sound event ", event_name)

func stop(immediate: bool = false) -> void:
    if immediate:
        _stop_track_voices(true)
        return

    _stop_track_voices(false)

func play_automation(event_name: StringName, automation_name: StringName, value: float = 0.0) -> void:
    if not event_name or not automation_name:
        return

    var has_active_voices = false
    for voice in _active_voices:
        if not _is_automation_voice(voice, event_name, automation_name):
            continue
        has_active_voices = true
        voice.automation_value = value
        _apply_automation_value(voice)

    if has_active_voices:
        return

    var automation = _find_automation(event_name, automation_name)
    if automation == null:
        push_error("Unknown sound automation ", event_name, ":", automation_name)
        return

    if automation.tracks.is_empty():
        push_error("Automation tracks are missing ", event_name, ":", automation_name)
        return

    for track in automation.tracks:
        var player = _get_available_player()
        if player == null:
            push_warning("No free player for automation %s:%s" % [event_name, automation_name])
            break

        var sfx_stream = track.get_next_sfx_stream()
        var stream = sfx_stream.stream if sfx_stream else null
        if stream == null:
            continue

        player.stream = stream
        player.bus = _resolve_audio_bus(track.audio_bus)
        player.pitch_scale = 1.0

        var voice = ActiveVoice.new()
        voice.voice_type = VoiceType.AUTOMATION
        voice.player = player
        voice.track = track
        voice.sfx_stream = sfx_stream
        voice.stream_length = maxf(stream.get_length(), 0.0)
        voice.event_name = event_name
        voice.automation_name = automation_name
        voice.automation = automation
        voice.automation_value = value
        _active_voices.append(voice)
        _apply_automation_value(voice)
        player.play()
        _update_players_in_use_debug(1)

    set_process(_requires_process())

func stop_automation(event_name: StringName, automation_name: StringName, immediate: bool = false) -> void:
    if not event_name or not automation_name:
        return

    for index in range(_active_voices.size() - 1, -1, -1):
        var voice = _active_voices[index]
        if not _is_automation_voice(voice, event_name, automation_name):
            continue
        _stop_voice(index)
