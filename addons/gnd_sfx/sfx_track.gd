extends Resource
class_name SfxTrack

#@export var instrument : SfxInstrument
enum SfxTrackPlaybackMode { SHUFFLE, RANDOMIZE, SEQUENTIAL }

@export var streams : Array[SfxStream] = []
@export var mode : SfxTrackPlaybackMode = SfxTrackPlaybackMode.SEQUENTIAL
@export var fade_in_curve: Curve
@export var fade_out_curve: Curve
@export var audio_bus : StringName
@export var pitch_curve: Curve

var _last_stream = -1

func get_next_sfx_stream() -> SfxStream:
    if not streams.size():
        return null

    match mode:
        SfxTrackPlaybackMode.SEQUENTIAL:
            _last_stream += 1
            if _last_stream >= streams.size():
                _last_stream = 0
            return streams[_last_stream]
        SfxTrackPlaybackMode.RANDOMIZE:
            return streams[randi_range(0, streams.size() - 1)]
        SfxTrackPlaybackMode.SHUFFLE:
            var chance_sum = streams.reduce(func(accum, x): return x.chance + accum, 0)
            if chance_sum <= 0:
                return null
            var roll = randi_range(0, chance_sum - 1)
            for stream in streams:
                roll -= stream.chance
                if roll < 0:
                    return stream

    return null

func get_next_audio_stream() -> AudioStream:
    var sfx_stream = get_next_sfx_stream()
    return sfx_stream.stream if sfx_stream else null
