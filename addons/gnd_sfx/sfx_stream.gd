extends Resource
class_name SfxStream

@export var stream:AudioStream
@export var chance = 1
@export_range(0.0, 4.0, 0.01) var base_gain := 1.0
