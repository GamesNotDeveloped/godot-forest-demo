@tool
extends Node
class_name SfxPlayer

const SfxPlaybackRuntimeScript = preload("res://addons/gnd_sfx/sfx_playback_runtime.gd")
const PLAYBACK_NONE_OPTION := "<none>"

signal finished

var _runtime = SfxPlaybackRuntimeScript.new()

@export var events: Array[SfxEvent] = []:
    set(value):
        _disconnect_playback_resource_watchers()
        events = value
        _runtime.set_events(events)
        _connect_playback_resource_watchers()
        _sanitize_playback_selection()
        _notify_playback_property_list_changed()

@export var max_tracks: int = 10:
    set(value):
        max_tracks = value
        sync_values(true)

@export var max_polyphony: int = 1:
    set(value):
        max_polyphony = value
        sync_values()

@export_group("Playback", "playback")
@export var playback_enabled: bool = false:
    set(x):
        playback_enabled = x
        sync_values()

@export var playback_effect: StringName = "":
    set(x):
        if x == PLAYBACK_NONE_OPTION:
            x = &""
        playback_effect = x
        _sanitize_playback_selection()
        _notify_playback_property_list_changed()
        sync_values()

@export var playback_automation: StringName = "":
    set(x):
        if x == PLAYBACK_NONE_OPTION:
            x = &""
        playback_automation = x
        sync_values()

@export var playback_automation_value: float = 0.0:
    set(x):
        playback_automation_value = x
        sync_values()

var _preview_enabled: bool = false
var _preview_effect: StringName = &""
var _preview_automation: StringName = &""
var _preview_automation_value: float = 0.0
var _suspend_preview_sync: bool = false
var _watched_events: Array[SfxEvent] = []
var _watched_automations: Array[SfxAutomation] = []

var _players: Array = []


func _enter_tree() -> void:
    _reset_playback_preview_state()
    if Engine.is_editor_hint():
        _suspend_preview_sync = true
        #playback_effect = &""
        #playback_automation = &""
        playback_enabled = false
        _suspend_preview_sync = false
        _notify_playback_property_list_changed()


func _ready() -> void:
    _ensure_runtime_connections()
    _runtime.set_events(events)
    _connect_playback_resource_watchers()
    sync_values(true)
    _update_process_state()


func _exit_tree() -> void:
    _disconnect_playback_resource_watchers()


func _process(delta: float) -> void:
    _runtime.update(delta)


func sync_values(rebuild := false) -> void:
    if _suspend_preview_sync:
        return

    _ensure_runtime_connections()
    if rebuild:
        _runtime.clear()
        for player in _players:
            if is_instance_valid(player):
                remove_child(player)
                player.queue_free()
        _players = []
        var i := 0
        while i < max_tracks:
            var player := AudioStreamPlayer.new()
            _players.append(player)
            add_child(player)
            player.finished.connect(_on_player_finished.bind(player))
            i += 1
        _runtime.set_players(_players)

    _runtime.set_events(events)
    for player in _players:
        player.max_polyphony = max_polyphony
    _sync_editor_playback()
    _update_process_state()


func play(event_name: StringName, parameters: Dictionary = {}) -> void:
    _runtime.play(event_name, parameters)


func stop(immediate: bool = false) -> void:
    _runtime.stop(immediate)


func play_automation(event_name: StringName, automation_name: StringName, value: float = 0.0) -> void:
    _runtime.play_automation(event_name, automation_name, value)


func stop_automation(event_name: StringName, automation_name: StringName, immediate: bool = false) -> void:
    _runtime.stop_automation(event_name, automation_name, immediate)


func _ensure_runtime_connections() -> void:
    if not _runtime.process_requirement_changed.is_connected(_on_runtime_process_requirement_changed):
        _runtime.process_requirement_changed.connect(_on_runtime_process_requirement_changed)
    if not _runtime.finished.is_connected(_on_runtime_finished):
        _runtime.finished.connect(_on_runtime_finished)


func _on_runtime_process_requirement_changed(required: bool) -> void:
    if Engine.is_editor_hint():
        _update_process_state()
        return
    set_process(required)


func _on_runtime_finished() -> void:
    finished.emit()


func _on_player_finished(player: AudioStreamPlayer) -> void:
    _runtime.handle_player_finished(player)


func _sync_editor_playback() -> void:
    if not Engine.is_editor_hint() or not is_inside_tree():
        return

    var config_changed := (
        playback_enabled != _preview_enabled
        or playback_effect != _preview_effect
        or playback_automation != _preview_automation
    )
    var value_changed := not is_equal_approx(playback_automation_value, _preview_automation_value)

    if not config_changed and not value_changed:
        return

    if not playback_enabled or String(playback_effect).is_empty():
        _runtime.clear()
        _store_playback_preview_state()
        return

    if config_changed:
        _runtime.clear()
        if String(playback_automation).is_empty():
            _runtime.play(playback_effect)
        else:
            _runtime.play_automation(playback_effect, playback_automation, playback_automation_value)
        _store_playback_preview_state()
        return

    if not String(playback_automation).is_empty():
        _runtime.play_automation(playback_effect, playback_automation, playback_automation_value)
    _store_playback_preview_state()


func _store_playback_preview_state() -> void:
    _preview_enabled = playback_enabled
    _preview_effect = playback_effect
    _preview_automation = playback_automation
    _preview_automation_value = playback_automation_value


func _reset_playback_preview_state() -> void:
    _preview_enabled = false
    _preview_effect = &""
    _preview_automation = &""
    _preview_automation_value = 0.0


func _update_process_state() -> void:
    if Engine.is_editor_hint():
        set_process(_runtime.requires_process())


func _validate_property(property: Dictionary) -> void:
    if property.name == "playback_effect":
        property.hint = PROPERTY_HINT_ENUM
        property.hint_string = _build_playback_effect_hint()
    elif property.name == "playback_automation":
        property.hint = PROPERTY_HINT_ENUM
        property.hint_string = _build_playback_automation_hint()


func _build_playback_effect_hint() -> String:
    var options := PackedStringArray([PLAYBACK_NONE_OPTION])
    for event in events:
        if event == null or String(event.name).is_empty():
            continue
        options.append(String(event.name))
    return ",".join(options)


func _build_playback_automation_hint() -> String:
    var options := PackedStringArray([PLAYBACK_NONE_OPTION])
    var event := _find_playback_event()
    if event == null:
        return ",".join(options)

    for automation in event.automations:
        if automation == null or String(automation.parameter_name).is_empty():
            continue
        options.append(String(automation.parameter_name))
    return ",".join(options)


func _find_playback_event() -> SfxEvent:
    for event in events:
        if event != null and event.name == playback_effect:
            return event
    return null


func _sanitize_playback_selection() -> void:
    var event := _find_playback_event()
    if not String(playback_effect).is_empty() and event == null:
        playback_effect = &""
        playback_automation = &""
        return

    if String(playback_automation).is_empty() or event == null:
        return

    for automation in event.automations:
        if automation != null and automation.parameter_name == playback_automation:
            return
    playback_automation = &""


func _notify_playback_property_list_changed() -> void:
    if Engine.is_editor_hint():
        notify_property_list_changed()


func _connect_playback_resource_watchers() -> void:
    if not Engine.is_editor_hint():
        return

    for event in events:
        if event == null or _watched_events.has(event):
            continue
        event.changed.connect(_on_playback_source_changed)
        _watched_events.append(event)

        for automation in event.automations:
            if automation == null or _watched_automations.has(automation):
                continue
            automation.changed.connect(_on_playback_source_changed)
            _watched_automations.append(automation)


func _disconnect_playback_resource_watchers() -> void:
    for event in _watched_events:
        if is_instance_valid(event) and event.changed.is_connected(_on_playback_source_changed):
            event.changed.disconnect(_on_playback_source_changed)
    for automation in _watched_automations:
        if is_instance_valid(automation) and automation.changed.is_connected(_on_playback_source_changed):
            automation.changed.disconnect(_on_playback_source_changed)
    _watched_events.clear()
    _watched_automations.clear()


func _on_playback_source_changed() -> void:
    _disconnect_playback_resource_watchers()
    _connect_playback_resource_watchers()
    _sanitize_playback_selection()
    _notify_playback_property_list_changed()
    sync_values()
