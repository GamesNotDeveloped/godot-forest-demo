@tool
extends SfxStream
class_name SfxWindGeneratorStream

class RuntimeState:
    var playback: AudioStreamGeneratorPlayback
    var rng := RandomNumberGenerator.new()
    var dark_lp := 0.0
    var bright_lp := 0.0
    var side_lp := 0.0
    var gust_lp := 0.0
    var flutter_lp := 0.0
    var shimmer_lp := 0.0


const TAU := PI * 2.0
const OUTPUT_HEADROOM := 0.22

@export_range(8000, 96000, 100) var mix_sample_rate := 32000
@export_range(0.05, 2.0, 0.01) var buffer_length_sec := 0.35
@export var bright_gain_curve: Curve
@export var dark_gain_curve: Curve
@export var master_gain_curve: Curve
@export_range(0.0, 1.0, 0.01) var stereo_width := 0.35
@export_range(0.0, 1.0, 0.01) var turbulence_amount := 0.18
@export var seed := 0


func build_audio_stream() -> AudioStreamGenerator:
    var generator := AudioStreamGenerator.new()
    generator.mix_rate = mix_sample_rate
    generator.buffer_length = buffer_length_sec
    return generator


func create_runtime(playback: AudioStreamGeneratorPlayback) -> RuntimeState:
    if playback == null:
        return null

    var runtime := RuntimeState.new()
    runtime.playback = playback
    if seed == 0:
        runtime.rng.randomize()
    else:
        runtime.rng.seed = seed
    return runtime


func fill_buffer(runtime: RuntimeState, speed: float) -> void:
    if runtime == null or runtime.playback == null:
        return

    var frames_available := runtime.playback.get_frames_available()
    if frames_available <= 0:
        return

    var sample_rate := maxf(float(mix_sample_rate), 1.0)
    var clamped_speed := maxf(speed, 0.0)
    var dark_gain := _sample_speed_curve(dark_gain_curve, clamped_speed, 1.0)
    var bright_gain := _sample_speed_curve(bright_gain_curve, clamped_speed, 0.0)
    var master_gain := _sample_speed_curve(master_gain_curve, clamped_speed, 1.0)
    var speed_blend := clampf(clamped_speed / 12.0, 0.0, 1.0)

    var gust_alpha := _cutoff_to_alpha(lerpf(0.06, 0.34, speed_blend), sample_rate)
    var flutter_alpha := _cutoff_to_alpha(lerpf(0.35, 1.45, speed_blend), sample_rate)
    var shimmer_alpha := _cutoff_to_alpha(lerpf(1.6, 4.8, speed_blend), sample_rate)
    var flutter_depth := lerpf(0.025, 0.11, speed_blend)
    var gust_depth := lerpf(0.18, 0.6, speed_blend)

    for _frame in range(frames_available):
        var white := runtime.rng.randf_range(-1.0, 1.0)
        runtime.gust_lp += gust_alpha * (runtime.rng.randf_range(-1.0, 1.0) - runtime.gust_lp)
        runtime.flutter_lp += flutter_alpha * (runtime.rng.randf_range(-1.0, 1.0) - runtime.flutter_lp)
        runtime.shimmer_lp += shimmer_alpha * (runtime.rng.randf_range(-1.0, 1.0) - runtime.shimmer_lp)

        var flutter := runtime.flutter_lp * flutter_depth
        var shimmer := runtime.shimmer_lp * flutter_depth * 0.35
        var gust_norm := clampf(0.5 + runtime.gust_lp * 0.5 + flutter + shimmer, 0.0, 1.0)
        var gust_amp := lerpf(1.0 - gust_depth, 1.0, gust_norm)
        var filter_push := lerpf(0.82, 1.28, gust_norm)

        var dark_alpha := _cutoff_to_alpha(lerpf(95.0, 360.0, speed_blend) * filter_push, sample_rate)
        var bright_alpha := _cutoff_to_alpha(lerpf(280.0, 1750.0, speed_blend) * filter_push, sample_rate)
        var side_alpha := _cutoff_to_alpha(lerpf(120.0, 920.0, speed_blend) * filter_push, sample_rate)

        runtime.dark_lp += dark_alpha * (white - runtime.dark_lp)
        runtime.bright_lp += bright_alpha * (white - runtime.bright_lp)
        runtime.side_lp += side_alpha * (white - runtime.side_lp)

        var dark := runtime.dark_lp
        var bright := white - runtime.bright_lp
        var body := dark * dark_gain * lerpf(0.8, 1.08, gust_norm)
        var air := bright * bright_gain * lerpf(0.52, 1.35, gust_norm)
        var motion := lerpf(1.0 - turbulence_amount, 1.0, gust_norm)
        var mono := (body + air) * master_gain * gust_amp * motion
        var side := (white - runtime.side_lp) * stereo_width * OUTPUT_HEADROOM * lerpf(0.22, 0.7, gust_norm)
        var output := mono * OUTPUT_HEADROOM

        runtime.playback.push_frame(Vector2(
            clampf(output + side, -1.0, 1.0),
            clampf(output - side, -1.0, 1.0)
        ))


func _sample_speed_curve(curve: Curve, speed: float, default_value: float) -> float:
    if curve == null:
        return default_value

    var input_min := minf(curve.min_domain, curve.max_domain)
    var input_max := maxf(curve.min_domain, curve.max_domain)
    if is_equal_approx(input_min, input_max):
        return curve.sample_baked(curve.min_domain)

    var clamped_speed := clampf(speed, input_min, input_max)
    var weight := inverse_lerp(input_min, input_max, clamped_speed)
    var sample_position := lerpf(curve.min_domain, curve.max_domain, weight)
    return curve.sample_baked(sample_position)


func _cutoff_to_alpha(cutoff_hz: float, sample_rate: float) -> float:
    return clampf(1.0 - exp(-TAU * maxf(cutoff_hz, 0.001) / maxf(sample_rate, 1.0)), 0.0, 1.0)
