@tool
extends Resource
class_name SfxBank

@export var events: Array[SfxEvent] = []:
    set(x):
        events = x
        _rebuild_events_cache()


var _events_cache = {}

func _rebuild_events_cache():
    _events_cache = {}
    for event in events:
        if event.name:
            _events_cache[event.name] = event

func get_event(event_name: StringName) -> SfxEvent:
    return _events_cache.get(event_name)
