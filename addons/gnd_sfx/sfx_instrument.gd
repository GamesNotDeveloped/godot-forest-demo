@tool
extends Resource
class_name SfxInstrument

enum SfxInstrumentPlaybackMode { SHUFFLE, RANDOMIZE, SEQUENTIAL }

var streams : Array[AudioStream] = []
var mode : SfxInstrumentPlaybackMode = SfxInstrumentPlaybackMode.SHUFFLE
var fade_in_curve: Curve
var fade_out_curve: Curve
