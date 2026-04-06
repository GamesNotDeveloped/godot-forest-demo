@tool
class_name SunShaftsCompositorEffect
extends CompositorEffect

const SHADER_CODE := """
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D source_color;
layout(rgba16f, set = 0, binding = 1) uniform image2D color_image;

layout(push_constant, std430) uniform Params {
    vec2 raster_size;
    vec2 sun_uv;
    vec4 shaft_color;
    vec4 shaft_params_a;
    vec4 shaft_params_b;
    vec4 debug_params;
} params;

const int SAMPLE_COUNT = 40;

float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = ivec2(params.raster_size);
    if (pixel.x >= size.x || pixel.y >= size.y) {
        return;
    }

    vec4 base = texelFetch(source_color, pixel, 0);
    if (params.debug_params.x > 0.0) {
        base.rgb = mix(base.rgb, params.debug_params.yzw, clamp(params.debug_params.x, 0.0, 1.0));
    }

    if (params.shaft_params_b.x < 0.5) {
        imageStore(color_image, pixel, base);
        return;
    }

    vec2 uv = (vec2(pixel) + vec2(0.5)) / params.raster_size;
    vec2 delta = params.sun_uv - uv;
    float distance_to_sun = length(delta);
    vec2 step_uv = delta * (params.shaft_params_a.x / float(SAMPLE_COUNT));
    vec2 sample_uv = uv;
    float illumination_decay = 1.0;
    float accumulation = 0.0;

    for (int i = 0; i < SAMPLE_COUNT; i++) {
        sample_uv += step_uv;
        if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
            continue;
        }

        ivec2 sample_pixel = ivec2(clamp(sample_uv * params.raster_size, vec2(0.0), params.raster_size - vec2(1.0)));
        vec3 sample_color = texelFetch(source_color, sample_pixel, 0).rgb;
        float bright = smoothstep(params.shaft_params_a.y, 1.0, luminance(sample_color));
        accumulation += bright * illumination_decay * params.shaft_params_a.z;
        illumination_decay *= params.shaft_params_a.w;
    }

    float radial_falloff = smoothstep(params.shaft_params_b.y, 0.0, distance_to_sun);
    vec3 shafts = params.shaft_color.rgb * accumulation * params.shaft_params_b.z * radial_falloff;
    base.rgb += shafts;
    imageStore(color_image, pixel, base);
}
"""

var _sun_screen_uv := Vector2(0.5, 0.5)
var _sun_visible := false
var _shaft_color := Color(1.0, 0.9, 0.72, 1.0)
var _density := 0.92
var _bright_threshold := 0.7
var _weight := 0.028
var _decay := 0.95
var _exposure := 1.1
var _max_radius := 0.9
var _debug_overlay_strength := 0.0
var _debug_overlay_color := Color(1.0, 0.0, 1.0, 1.0)


@export var sun_screen_uv := Vector2(0.5, 0.5):
	set(value):
		_mutex.lock()
		_sun_screen_uv = value
		_mutex.unlock()
	get:
		return _sun_screen_uv

@export var sun_visible := false:
	set(value):
		_mutex.lock()
		_sun_visible = value
		_mutex.unlock()
	get:
		return _sun_visible

@export var shaft_color: Color = Color(1.0, 0.9, 0.72, 1.0):
	set(value):
		_mutex.lock()
		_shaft_color = value
		_mutex.unlock()
	get:
		return _shaft_color

@export_range(0.0, 1.0, 0.001) var density: float = 0.92:
	set(value):
		_mutex.lock()
		_density = clampf(value, 0.0, 1.0)
		_mutex.unlock()
	get:
		return _density

@export_range(0.0, 1.0, 0.001) var bright_threshold: float = 0.7:
	set(value):
		_mutex.lock()
		_bright_threshold = clampf(value, 0.0, 1.0)
		_mutex.unlock()
	get:
		return _bright_threshold

@export_range(0.0, 0.2, 0.0005) var weight: float = 0.028:
	set(value):
		_mutex.lock()
		_weight = maxf(value, 0.0)
		_mutex.unlock()
	get:
		return _weight

@export_range(0.0, 1.0, 0.001) var decay: float = 0.95:
	set(value):
		_mutex.lock()
		_decay = clampf(value, 0.0, 1.0)
		_mutex.unlock()
	get:
		return _decay

@export_range(0.0, 8.0, 0.01) var exposure: float = 1.1:
	set(value):
		_mutex.lock()
		_exposure = maxf(value, 0.0)
		_mutex.unlock()
	get:
		return _exposure

@export_range(0.0, 2.0, 0.001) var max_radius: float = 0.9:
	set(value):
		_mutex.lock()
		_max_radius = maxf(value, 0.0)
		_mutex.unlock()
	get:
		return _max_radius

@export_group("Debug")
@export_range(0.0, 1.0, 0.001) var debug_overlay_strength: float = 0.0:
	set(value):
		_mutex.lock()
		_debug_overlay_strength = clampf(value, 0.0, 1.0)
		_mutex.unlock()
	get:
		return _debug_overlay_strength

@export var debug_overlay_color: Color = Color(1.0, 0.0, 1.0, 1.0):
	set(value):
		_mutex.lock()
		_debug_overlay_color = value
		_mutex.unlock()
	get:
		return _debug_overlay_color

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var sampler: RID
var _mutex := Mutex.new()


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	enabled = true
	rd = RenderingServer.get_rendering_device()
	_initialize_shader()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if rd != null:
			if sampler.is_valid():
				rd.free_rid(sampler)
			if pipeline.is_valid():
				rd.free_rid(pipeline)
			if shader.is_valid():
				rd.free_rid(shader)


func _initialize_shader() -> void:
	if rd == null:
		return
	var shader_file := RDShaderSource.new()
	shader_file.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	shader_file.source_compute = SHADER_CODE
	var shader_spirv := rd.shader_compile_spirv_from_source(shader_file)
	if shader_spirv.compile_error_compute != "":
		push_error(shader_spirv.compile_error_compute)
		return
	shader = rd.shader_create_from_spirv(shader_spirv)
	if not shader.is_valid():
		return
	var sampler_state := RDSamplerState.new()
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler = rd.sampler_create(sampler_state)
	pipeline = rd.compute_pipeline_create(shader)


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if rd == null or not pipeline.is_valid():
		return
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return

	var render_scene_buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if render_scene_buffers == null:
		return
	var size := render_scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return

	var params := _copy_params()
	var x_groups := int((size.x - 1) / 8) + 1
	var y_groups := int((size.y - 1) / 8) + 1
	var push_constant := PackedFloat32Array([
		float(size.x), float(size.y),
		params["sun_uv"].x, params["sun_uv"].y,
		params["color"].r, params["color"].g, params["color"].b, params["color"].a,
		params["density"], params["threshold"], params["weight"], params["decay"],
		1.0 if params["visible"] else 0.0, params["max_radius"], params["exposure"], 0.0,
		params["debug_overlay_strength"], params["debug_overlay_color"].r, params["debug_overlay_color"].g, params["debug_overlay_color"].b
	])

	var view_count := render_scene_buffers.get_view_count()
	var source_color := render_scene_buffers.get_texture("render_buffers", "color")
	if not source_color.is_valid():
		return
	for view in range(view_count):
		var color_image := render_scene_buffers.get_color_layer(view)
		if not color_image.is_valid():
			continue
		var source_uniform := RDUniform.new()
		source_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		source_uniform.binding = 0
		source_uniform.add_id(sampler)
		source_uniform.add_id(source_color)
		var target_uniform := RDUniform.new()
		target_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		target_uniform.binding = 1
		target_uniform.add_id(color_image)
		var uniform_set := UniformSetCacheRD.get_cache(shader, 0, [source_uniform, target_uniform])
		var compute_list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()


func _copy_params() -> Dictionary:
	_mutex.lock()
	var params := {
		"sun_uv": _sun_screen_uv,
		"visible": _sun_visible,
		"color": _shaft_color,
		"density": _density,
		"threshold": _bright_threshold,
		"weight": _weight,
		"decay": _decay,
		"exposure": _exposure,
		"max_radius": _max_radius,
		"debug_overlay_strength": _debug_overlay_strength,
		"debug_overlay_color": _debug_overlay_color,
	}
	_mutex.unlock()
	return params
