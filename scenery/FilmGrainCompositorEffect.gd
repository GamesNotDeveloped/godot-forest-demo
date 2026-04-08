@tool
class_name FilmGrainCompositorEffect
extends CompositorEffect

const SHADER_CODE := """
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D source_color;
layout(rgba16f, set = 0, binding = 1) uniform image2D color_image;

layout(push_constant, std430) uniform Params {
    vec2 raster_size;
    float time;
    float amount;
    vec4 response;
} params;

float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = ivec2(params.raster_size);
    if (pixel.x >= size.x || pixel.y >= size.y) {
        return;
    }

    vec4 base = texelFetch(source_color, pixel, 0);
    float luma = clamp(luminance(base.rgb), 0.0, 1.0);

    float shadow_mask = 1.0 - smoothstep(0.08, 0.42, luma);
    float highlight_mask = smoothstep(0.55, 0.98, luma);
    float mid_mask = clamp(1.0 - shadow_mask - highlight_mask, 0.0, 1.0);
    float tonal_weight = shadow_mask * params.response.x + mid_mask * params.response.y + highlight_mask * params.response.z;

    float grain = hash12(vec2(pixel) + vec2(params.time * 61.7, params.time * 17.3)) - 0.5;
    grain *= params.amount * tonal_weight;

    base.rgb = clamp(base.rgb + vec3(grain), 0.0, 65504.0);
    imageStore(color_image, pixel, base);
}
"""

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var sampler: RID
var _mutex := Mutex.new()

var _amount := 0.018
var _animation_speed := 1.0
var _shadow_response := 0.65
var _mid_response := 1.0
var _highlight_response := 0.35


@export_range(0.0, 0.08, 0.0005) var amount: float = 0.018:
	set(value):
		_mutex.lock()
		_amount = maxf(value, 0.0)
		_mutex.unlock()
	get:
		return _amount

@export_range(0.0, 8.0, 0.01) var animation_speed: float = 1.0:
	set(value):
		_mutex.lock()
		_animation_speed = maxf(value, 0.0)
		_mutex.unlock()
	get:
		return _animation_speed

@export_range(0.0, 2.0, 0.001) var shadow_response: float = 0.65:
	set(value):
		_mutex.lock()
		_shadow_response = maxf(value, 0.0)
		_mutex.unlock()
	get:
		return _shadow_response

@export_range(0.0, 2.0, 0.001) var mid_response: float = 1.0:
	set(value):
		_mutex.lock()
		_mid_response = maxf(value, 0.0)
		_mutex.unlock()
	get:
		return _mid_response

@export_range(0.0, 2.0, 0.001) var highlight_response: float = 0.35:
	set(value):
		_mutex.lock()
		_highlight_response = maxf(value, 0.0)
		_mutex.unlock()
	get:
		return _highlight_response


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
		params["time"], params["amount"],
		params["shadow_response"], params["mid_response"], params["highlight_response"], 0.0,
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
		"time": Time.get_ticks_msec() * 0.001 * _animation_speed,
		"amount": _amount,
		"shadow_response": _shadow_response,
		"mid_response": _mid_response,
		"highlight_response": _highlight_response,
	}
	_mutex.unlock()
	return params
