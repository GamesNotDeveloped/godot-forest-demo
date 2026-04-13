@tool
extends Node
class_name SfxPlayer

const SfxPlaybackRuntimeScript = preload("res://addons/gnd_sfx/sfx_playback_runtime.gd")

signal finished

var _runtime = SfxPlaybackRuntimeScript.new()

@export var events: Array[SfxEvent] = []:
	set(value):
		events = value
		_runtime.set_events(events)

@export var max_tracks: int = 10:
	set(value):
		max_tracks = value
		sync_values(true)

@export var max_polyphony: int = 1:
	set(value):
		max_polyphony = value
		sync_values()

var _players: Array = []


func _ready() -> void:
	_ensure_runtime_connections()
	_runtime.set_events(events)
	sync_values(true)
	set_process(false)


func _process(delta: float) -> void:
	_runtime.update(delta)


func sync_values(rebuild := false) -> void:
	if Engine.is_editor_hint():
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
		return
	set_process(required)


func _on_runtime_finished() -> void:
	finished.emit()


func _on_player_finished(player: AudioStreamPlayer) -> void:
	_runtime.handle_player_finished(player)
