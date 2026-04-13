extends RefCounted
class_name SfxPlaybackRuntime

enum VoiceType { TRACK, AUTOMATION }


class ActiveVoice:
    var voice_type: VoiceType = VoiceType.TRACK
    var player
    var track: SfxTrack
    var stream: AudioStream
    var stream_length := 0.0
    var manual_fade_out_started := false
    var manual_fade_out_elapsed := 0.0
    var event_name: StringName = &""
    var automation_name: StringName = &""
    var automation: SfxAutomation
    var automation_value := 0.0
    var generator_playback: SfxGeneratorPlayback
    var generator_state
    var generator_stream_playback: AudioStreamGeneratorPlayback


signal finished
signal process_requirement_changed(required: bool)

var events: Array[SfxEvent] = []
var _players: Array = []
var _active_voices: Array[ActiveVoice] = []
var _players_in_use := 0


func set_events(value: Array[SfxEvent]) -> void:
    events = value


func set_players(players: Array) -> void:
    _players = players
    _notify_process_requirement_changed()


func clear() -> void:
    var had_voices := not _active_voices.is_empty()
    for voice in _active_voices:
        _cleanup_voice(voice)
    for player in _players:
        _reset_player(player, true)
    _active_voices.clear()
    _players_in_use = 0
    _notify_process_requirement_changed()
    if had_voices:
        finished.emit()


func handle_player_finished(player) -> void:
    _release_voice(_find_active_voice_index(player))


func update(delta: float) -> void:
    for index in range(_active_voices.size() - 1, -1, -1):
        _update_voice(index, delta)


func play(event_name: StringName, parameters: Dictionary = {}) -> void:
    if not event_name:
        return

    var event := _find_event(event_name)
    if event == null:
        push_error("Unknown sound event ", event_name)
        return

    for track in event.tracks:
        var player = _get_available_player()
        if player == null:
            break

        _start_voice(player, track, VoiceType.TRACK)


func stop(immediate: bool = false) -> void:
    if immediate:
        _stop_track_voices(true)
        return

    _stop_track_voices(false)


func play_automation(event_name: StringName, automation_name: StringName, value: float = 0.0) -> void:
    if not event_name or not automation_name:
        return

    var has_active_voices := false
    for voice in _active_voices:
        if not _is_automation_voice(voice, event_name, automation_name):
            continue
        has_active_voices = true
        voice.automation_value = value
        _apply_automation_value(voice)

    if has_active_voices:
        return

    var automation := _find_automation(event_name, automation_name)
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

        _start_voice(
            player,
            track,
            VoiceType.AUTOMATION,
            event_name,
            automation_name,
            automation,
            value
        )


func stop_automation(event_name: StringName, automation_name: StringName, immediate: bool = false) -> void:
    if not event_name or not automation_name:
        return

    for index in range(_active_voices.size() - 1, -1, -1):
        var voice = _active_voices[index]
        if not _is_automation_voice(voice, event_name, automation_name):
            continue
        _stop_voice(index)


func requires_process() -> bool:
    for voice in _active_voices:
        if voice.voice_type == VoiceType.TRACK or _is_generator_voice(voice):
            return true
    return false


func _update_players_in_use_debug(delta: int) -> void:
    _players_in_use = _active_voices.size()
    print("PLAYER %s %s" % [("+1" if delta > 0 else "-1"), _players_in_use])


func _find_active_voice_index(player) -> int:
    for index in range(_active_voices.size()):
        if _active_voices[index].player == player:
            return index
    return -1


func _is_automation_voice(voice: ActiveVoice, event_name: StringName, automation_name: StringName) -> bool:
    return (
        voice.voice_type == VoiceType.AUTOMATION
        and voice.event_name == event_name
        and voice.automation_name == automation_name
    )


func _get_available_player():
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
    var event := _find_event(event_name)
    if event == null:
        return null

    for automation in event.automations:
        if automation.parameter_name == automation_name:
            return automation

    return null


func _resolve_audio_bus(bus_name: StringName) -> StringName:
    return &"Master" if String(bus_name).is_empty() else bus_name


func _get_curve_duration(curve: Curve) -> float:
    if curve == null:
        return 0.0
    return maxf(curve.max_domain - curve.min_domain, 0.0)


func _sample_curve_gain(curve: Curve, elapsed: float) -> float:
    if curve == null:
        return 1.0

    var duration := _get_curve_duration(curve)
    if duration <= 0.0:
        return clampf(curve.sample_baked(curve.max_domain), 0.0, 1.0)

    var sample_position := curve.min_domain + clampf(elapsed, 0.0, duration)
    return clampf(curve.sample_baked(sample_position), 0.0, 1.0)


func _is_generator_voice(voice: ActiveVoice) -> bool:
    return voice.generator_playback != null and voice.generator_stream_playback != null


func _set_player_gain(player, gain: float) -> void:
    player.volume_db = linear_to_db(maxf(gain, 0.0001))


func _sample_automation_curve(curve: Curve, automation: SfxAutomation, value: float, default_value: float) -> float:
    if curve == null:
        return default_value

    var input_min := minf(automation.min_domain, automation.max_domain)
    var input_max := maxf(automation.min_domain, automation.max_domain)
    var clamped_value := clampf(value, input_min, input_max)

    if is_equal_approx(input_min, input_max):
        return curve.sample_baked(curve.min_domain)

    var weight := inverse_lerp(input_min, input_max, clamped_value)
    var sample_position := lerpf(curve.min_domain, curve.max_domain, weight)
    return curve.sample_baked(sample_position)


func _apply_automation_value(voice: ActiveVoice) -> void:
    if voice.automation == null or voice.track == null or not is_instance_valid(voice.player):
        return

    var fade_in_gain := _sample_automation_curve(voice.track.fade_in_curve, voice.automation, voice.automation_value, 1.0)
    var fade_out_gain := _sample_automation_curve(voice.track.fade_out_curve, voice.automation, voice.automation_value, 1.0)
    var pitch := _sample_automation_curve(voice.track.pitch_curve, voice.automation, voice.automation_value, 1.0)

    _set_player_gain(voice.player, clampf(fade_in_gain, 0.0, 1.0) * clampf(fade_out_gain, 0.0, 1.0))
    voice.player.pitch_scale = maxf(pitch, 0.01)
    _pump_generator_voice(voice, 0.0)


func _build_generator_context(voice: ActiveVoice, delta: float) -> Dictionary:
    var playback_position := 0.0
    if is_instance_valid(voice.player):
        playback_position = voice.player.get_playback_position()
    return {
        "delta": delta,
        "playback_position": playback_position,
        "voice_type": voice.voice_type,
        "automation_value": voice.automation_value,
        "event_name": voice.event_name,
        "automation_name": voice.automation_name,
        "track": voice.track,
        "player": voice.player,
        "stream_playback": voice.generator_stream_playback,
    }


func _pump_generator_voice(voice: ActiveVoice, delta: float) -> void:
    if not _is_generator_voice(voice):
        return
    voice.generator_playback.update(voice.generator_state, _build_generator_context(voice, delta))


func _build_track_stream(track: SfxTrack) -> AudioStream:
    if track == null or track.stream == null:
        return null

    if track.stream is AudioStreamGenerator:
        if track.generator_playback == null:
            push_error("AudioStreamGenerator track requires generator_playback")
            return null
        var stream_copy = track.stream.duplicate(true)
        return stream_copy as AudioStream if stream_copy != null else track.stream

    return track.stream


func _start_voice(
    player,
    track: SfxTrack,
    voice_type: VoiceType,
    event_name: StringName = &"",
    automation_name: StringName = &"",
    automation: SfxAutomation = null,
    automation_value: float = 0.0
) -> bool:
    if not player or track == null:
        return false

    var stream := _build_track_stream(track)
    if stream == null:
        return false

    player.stream = stream
    player.bus = _resolve_audio_bus(track.audio_bus)
    player.pitch_scale = 1.0
    player.play()

    var voice := ActiveVoice.new()
    voice.voice_type = voice_type
    voice.player = player
    voice.track = track
    voice.stream = stream
    voice.stream_length = maxf(stream.get_length(), 0.0)
    voice.event_name = event_name
    voice.automation_name = automation_name
    voice.automation = automation
    voice.automation_value = automation_value

    if stream is AudioStreamGenerator:
        voice.generator_playback = track.generator_playback
        voice.generator_stream_playback = player.get_stream_playback() as AudioStreamGeneratorPlayback
        if voice.generator_stream_playback == null:
            push_error("Failed to get AudioStreamGeneratorPlayback for generator track")
            _reset_player(player, true)
            return false
        voice.generator_state = voice.generator_playback.create_state(voice.generator_stream_playback, track)

    _active_voices.append(voice)

    if voice_type == VoiceType.AUTOMATION:
        _apply_automation_value(voice)
    else:
        _set_player_gain(player, _sample_curve_gain(track.fade_in_curve, 0.0))

    if _is_generator_voice(voice):
        _pump_generator_voice(voice, 0.0)

    _update_players_in_use_debug(1)
    _notify_process_requirement_changed()
    return true


func _cleanup_voice(voice: ActiveVoice) -> void:
    if voice != null and voice.generator_playback != null:
        voice.generator_playback.cleanup(voice.generator_state)


func _release_voice(index: int) -> void:
    if index == -1:
        return

    var voice := _active_voices[index]
    _cleanup_voice(voice)
    if is_instance_valid(voice.player):
        voice.player.volume_db = 0.0
        voice.player.pitch_scale = 1.0
    _active_voices.remove_at(index)
    _update_players_in_use_debug(-1)
    _notify_process_requirement_changed()
    if _active_voices.is_empty():
        finished.emit()


func _stop_voice(index: int) -> void:
    if index == -1:
        return

    var voice := _active_voices[index]
    _release_voice(index)
    _reset_player(voice.player, true)


func _reset_player(player, clear_stream := false) -> void:
    if not is_instance_valid(player):
        return
    player.stop()
    player.pitch_scale = 1.0
    player.volume_db = 0.0
    if clear_stream:
        player.stream = null


func _update_track_voice(index: int, delta: float) -> bool:
    if index < 0 or index >= _active_voices.size():
        return false

    var voice := _active_voices[index]
    if not is_instance_valid(voice.player) or not voice.player.playing:
        _release_voice(index)
        return false

    var playback_position: float = voice.player.get_playback_position()
    var fade_in_gain := _sample_curve_gain(voice.track.fade_in_curve, playback_position)
    var fade_out_gain := 1.0
    var fade_out_duration := _get_curve_duration(voice.track.fade_out_curve)

    if voice.manual_fade_out_started:
        voice.manual_fade_out_elapsed += delta
        fade_out_gain = _sample_curve_gain(voice.track.fade_out_curve, voice.manual_fade_out_elapsed)
        if fade_out_duration <= 0.0 or voice.manual_fade_out_elapsed >= fade_out_duration:
            _stop_voice(index)
            return false
    elif voice.stream_length > 0.0 and fade_out_duration > 0.0:
        var remaining: float = maxf(voice.stream_length - playback_position, 0.0)
        if remaining <= fade_out_duration:
            fade_out_gain = _sample_curve_gain(voice.track.fade_out_curve, fade_out_duration - remaining)

        if playback_position >= voice.stream_length:
            _stop_voice(index)
            return false

    _set_player_gain(voice.player, fade_in_gain * fade_out_gain)
    return true


func _update_generator_voice(index: int, delta: float) -> bool:
    if index < 0 or index >= _active_voices.size():
        return false

    var voice := _active_voices[index]
    if not is_instance_valid(voice.player) or not voice.player.playing:
        _release_voice(index)
        return false

    if voice.voice_type == VoiceType.AUTOMATION:
        _pump_generator_voice(voice, delta)
        return true

    var playback_position: float = voice.player.get_playback_position()
    var fade_in_gain := _sample_curve_gain(voice.track.fade_in_curve, playback_position)
    var fade_out_gain := 1.0
    var fade_out_duration := _get_curve_duration(voice.track.fade_out_curve)

    if voice.manual_fade_out_started:
        voice.manual_fade_out_elapsed += delta
        fade_out_gain = _sample_curve_gain(voice.track.fade_out_curve, voice.manual_fade_out_elapsed)
        if fade_out_duration <= 0.0 or voice.manual_fade_out_elapsed >= fade_out_duration:
            _stop_voice(index)
            return false

    _set_player_gain(voice.player, fade_in_gain * fade_out_gain)
    _pump_generator_voice(voice, delta)
    return true


func _update_voice(index: int, delta: float) -> bool:
    if index < 0 or index >= _active_voices.size():
        return false

    var voice := _active_voices[index]
    if _is_generator_voice(voice):
        return _update_generator_voice(index, delta)

    if voice.voice_type == VoiceType.AUTOMATION:
        if not is_instance_valid(voice.player) or not voice.player.playing:
            _release_voice(index)
            return false
        return true

    return _update_track_voice(index, delta)


func _stop_track_voices(immediate: bool) -> void:
    for index in range(_active_voices.size() - 1, -1, -1):
        var voice := _active_voices[index]
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


func _notify_process_requirement_changed() -> void:
    process_requirement_changed.emit(requires_process())
