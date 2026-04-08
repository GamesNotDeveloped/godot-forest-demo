import re

tres_path = "scenery/materials/M_filmic_procedural_sky.tres"
shader_path = "scenery/shaders/filmic_procedural_sky.gdshader"
gd_path = "scenery/Skydome.gd"

# --- 1. Write the new Shader ---
shader_content = """shader_type sky;

uniform sampler2D cloud_tex_a : source_color, filter_linear, repeat_enable;
uniform sampler2D cloud_tex_b : source_color, filter_linear, repeat_enable;

group_uniforms DaySky;
	uniform vec3 lower_sky_color : source_color = vec3(0.66, 0.71, 0.8);
	uniform vec3 horizon_color : source_color = vec3(0.82, 0.86, 0.89);
	uniform vec3 zenith_color : source_color = vec3(0.12, 0.24, 0.48);
	uniform float sky_energy : hint_range(0.0, 10.0) = 1.0;
	uniform float horizon_height : hint_range(-0.4, 0.5) = -0.02;
	uniform float horizon_softness : hint_range(0.02, 1.0) = 0.24;
	uniform float zenith_curve : hint_range(0.1, 8.0) = 1.65;
	uniform float horizon_glow_strength : hint_range(0.0, 4.0) = 0.5;

group_uniforms NightSky;
	uniform vec3 night_lower_sky_color : source_color = vec3(0.03, 0.05, 0.09);
	uniform vec3 night_horizon_color : source_color = vec3(0.06, 0.1, 0.18);
	uniform vec3 night_zenith_color : source_color = vec3(0.01, 0.015, 0.03);
	uniform float night_sky_energy : hint_range(0.0, 10.0) = 1.0;
	uniform vec3 stars_color : source_color = vec3(1.0, 1.0, 1.0);
	uniform float stars_speed : hint_range(0.0, 1.0) = 0.1;

group_uniforms GI;
	uniform vec3 gi_tint : source_color = vec3(1.0, 1.0, 1.0);
	uniform float gi_energy_multiplier : hint_range(0.0, 10.0) = 1.0;

group_uniforms Sun;
	uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.8);
	uniform float sun_disk_size : hint_range(0.0, 2.0) = 1.0;
	uniform float sun_disk_softness : hint_range(0.0, 1.0) = 0.5;
	uniform float sun_disk_strength : hint_range(0.0, 20.0) = 5.0;
	uniform float sun_halo_size : hint_range(0.0, 2.0) = 1.0;
	uniform float sun_halo_strength : hint_range(0.0, 10.0) = 1.5;
	uniform float sun_atmosphere_size : hint_range(0.0, 4.0) = 1.0;
	uniform float sun_atmosphere_strength : hint_range(0.0, 10.0) = 1.0;
	uniform float sun_energy_scale : hint_range(0.0, 10.0) = 1.0;

group_uniforms Moon;
	uniform vec3 moon_color : source_color = vec3(0.9, 0.95, 1.0);
	uniform float moon_size : hint_range(0.0, 2.0) = 1.0;
	uniform float moon_glow_strength : hint_range(0.0, 10.0) = 1.0;
	uniform float moon_eclipse_size : hint_range(0.0, 4.0) = 2.5;

group_uniforms Clouds;
	uniform vec2 cloud_scroll_a = vec2(0.0012, 0.00015);
	uniform vec2 cloud_scroll_b = vec2(-0.0018, 0.0004);
	uniform vec2 cloud_scale_a = vec2(0.045, 0.055);
	uniform vec2 cloud_scale_b = vec2(0.082, 0.125);
	uniform float cloud_plane_height : hint_range(0.02, 4.0) = 0.25;
	uniform float cloud_plane_curve : hint_range(0.0, 1.0) = 0.15;
	uniform float cloud_warp_strength : hint_range(0.0, 1.0) = 0.14;
	uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5;
	uniform float cloud_softness : hint_range(0.01, 1.0) = 0.2;
	uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.6;
	uniform float cloud_horizon_fade : hint_range(0.0, 1.0) = 0.3;
	uniform float cloud_top_fade : hint_range(0.0, 1.0) = 0.2;
	uniform vec3 cloud_light_color : source_color = vec3(1.0, 0.98, 0.95);
	uniform vec3 cloud_shadow_color : source_color = vec3(0.4, 0.45, 0.55);
	uniform float cloud_forward_scatter : hint_range(0.0, 4.0) = 1.5;
	uniform float cloud_backscatter : hint_range(0.0, 1.0) = 0.2;
	uniform float sun_cloud_occlusion : hint_range(0.0, 1.0) = 0.8;

uniform vec3 custom_sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 custom_moon_dir = vec3(0.0, -1.0, 0.0);

vec2 dir_to_cloud_plane_uv(vec3 dir, float plane_height, float curve) {
	float denom = max(dir.y + plane_height, 0.05);
	vec2 uv = dir.xz / denom;
	float dist = length(uv);
	uv *= 1.0 + dist * curve;
	return uv;
}

float saturate(float value) { return clamp(value, 0.0, 1.0); }

float hash(vec3 p) {
	p = fract(p * vec3(123.34, 456.21, 876.45));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	float sun_alt = custom_sun_dir.y;
	float day_blend = smoothstep(-0.05, 0.05, sun_alt);

	float horizon_t = smoothstep(horizon_height - horizon_softness, horizon_height + horizon_softness, dir.y);
	float zenith_t = pow(saturate(max(dir.y, 0.0)), zenith_curve);
	
	vec3 day_base = mix(lower_sky_color, horizon_color, horizon_t);
	day_base = mix(day_base, zenith_color, zenith_t);
	float day_glow = pow(1.0 - saturate(abs(dir.y - horizon_height) * 2.5), 4.0);
	day_base += horizon_color * day_glow * horizon_glow_strength;
	day_base *= sky_energy;

	vec3 night_base = mix(night_lower_sky_color, night_horizon_color, horizon_t);
	night_base = mix(night_base, night_zenith_color, zenith_t);
	float night_glow = pow(1.0 - saturate(abs(dir.y - horizon_height) * 2.5), 4.0);
	night_base += night_horizon_color * night_glow * horizon_glow_strength;
	night_base *= night_sky_energy;

	vec3 final_color = mix(night_base, day_base, day_blend);

	float star_hash = hash(dir * 300.0 + TIME * stars_speed * 0.01);
	float stars = smoothstep(0.99, 1.0, star_hash) * 3.0;
	final_color += stars_color * stars * (1.0 - day_blend);

	vec2 cloud_uv = dir_to_cloud_plane_uv(dir, cloud_plane_height, cloud_plane_curve);
	vec2 warp = texture(cloud_tex_b, cloud_uv * 0.01 + vec2(0.003, -0.002) * TIME).rg * 2.0 - 1.0;
	cloud_uv += warp * cloud_warp_strength;

	float cloud_a = texture(cloud_tex_a, cloud_uv * cloud_scale_a + cloud_scroll_a * TIME).r;
	float cloud_b = texture(cloud_tex_b, cloud_uv * cloud_scale_b + cloud_scroll_b * TIME).r;
	float breakup = texture(cloud_tex_b, cloud_uv * 0.04 - vec2(0.0015, 0.0008) * TIME).r;

	float cloud_shape = mix(cloud_a, cloud_b, 0.5);
	cloud_shape = mix(cloud_shape, cloud_shape * breakup, 0.4);
	float cloud_mask = 1.0 - smoothstep(cloud_coverage - cloud_softness, cloud_coverage + cloud_softness, cloud_shape);

	float horizon_mask = smoothstep(-0.1, cloud_horizon_fade, dir.y);
	float top_mask = 1.0 - smoothstep(1.0 - cloud_top_fade, 1.0, max(dir.y, 0.0));
	cloud_mask *= horizon_mask * top_mask * cloud_opacity;
	
	float sky_visibility = 1.0 - (cloud_mask * sun_cloud_occlusion);

	// Sun
	float sun_dot = dot(dir, custom_sun_dir);
	float disk_radius = 0.015 * sun_disk_size;
	float disk_soft = disk_radius * sun_disk_softness;
	float disk = smoothstep(1.0 - disk_radius - disk_soft, 1.0 - disk_radius, sun_dot);
	float halo = pow(saturate(sun_dot), 1.0 / (0.08 * sun_halo_size)) * sun_halo_strength;
	float atmosphere = pow(saturate(sun_dot), 1.0 / (0.35 * sun_atmosphere_size)) * sun_atmosphere_strength;
	
	vec3 sun_body = sun_color * sun_energy_scale;
	final_color += sun_body * disk * sky_visibility * sun_disk_strength;
	final_color += sun_body * halo * sky_visibility;
	final_color += sun_body * atmosphere * sky_visibility;

	// Moon
	float moon_dot = dot(dir, custom_moon_dir);
	float m_radius = 0.015 * moon_size;
	float moon_light = 0.0;
	float moon_mask_val = 0.0;

	if (moon_dot > 1.0 - m_radius * 2.0) {
		vec3 up = abs(custom_moon_dir.y) < 0.999 ? vec3(0,1,0) : vec3(1,0,0);
		vec3 right = normalize(cross(up, custom_moon_dir));
		up = cross(custom_moon_dir, right);

		float x = dot(dir, right) / m_radius;
		float y = dot(dir, up) / m_radius;
		float r2 = x*x + y*y;

		if (r2 < 1.0) {
			moon_mask_val = smoothstep(1.0, 1.0 - 0.05, r2);
			float z = -sqrt(1.0 - r2);
			vec3 N = normalize(x * right + y * up + z * custom_moon_dir);
			
			moon_light = max(0.0, dot(N, custom_sun_dir));
			
			float earth_shadow_radius = m_radius * moon_eclipse_size;
			float umbra_dist = length(dir + custom_sun_dir);
			float umbra = smoothstep(earth_shadow_radius * 0.8, earth_shadow_radius, umbra_dist);
			
			moon_light *= umbra;
			moon_light += (1.0 - umbra) * 0.02; // blood moon / ambient
		}
	}

	float moon_glow = pow(saturate(moon_dot), 1.0 / (0.05 * moon_size)) * moon_glow_strength * (1.0 - day_blend);
	vec3 moon_body = moon_color;
	
	final_color += moon_body * moon_light * moon_mask_val * sky_visibility * 2.0;
	final_color += moon_body * moon_glow * sky_visibility;

	// Clouds
	vec3 active_light_dir = mix(custom_moon_dir, custom_sun_dir, day_blend);
	float cloud_dot = dot(dir, active_light_dir);
	float silver_lining = pow(saturate(cloud_dot), 12.0) * cloud_forward_scatter;
	float backscatter_val = pow(1.0 - saturate(cloud_dot), 2.0) * cloud_backscatter;
	
	vec3 active_light_color = mix(moon_color * 0.5, sun_color * sun_energy_scale, day_blend);
	vec3 cloud_col = mix(cloud_shadow_color * mix(0.1, 1.0, day_blend), active_light_color, saturate(0.2 + silver_lining - backscatter_val));
	
	final_color = mix(final_color, cloud_col, cloud_mask);

	if (AT_CUBEMAP_PASS) {
		final_color *= gi_tint * gi_energy_multiplier;
	}

	COLOR = final_color;
}
"""

with open(shader_path, "w") as f:
    f.write(shader_content)

# --- 2. Parse existing .tres to keep user settings ---
params = {}
with open(tres_path, "r") as f:
    for line in f:
        m = re.match(r'^shader_parameter/(\w+) = (.+)$', line.strip())
        if m:
            key, val = m.groups()
            params[key] = val

params["cloud_tex_a"] = "preload(\"res://scenery/materials/cloud_noise_a.tres\")"
params["cloud_tex_b"] = "preload(\"res://scenery/materials/cloud_noise_b.tres\")"

props = [
    ("DaySky", [
        ("lower_sky_color", "Color", "Color(0.66, 0.71, 0.8, 1)"),
        ("horizon_color", "Color", "Color(0.82, 0.86, 0.89, 1)"),
        ("zenith_color", "Color", "Color(0.12, 0.24, 0.48, 1)"),
        ("sky_energy", "float", "1.0"),
        ("horizon_height", "float", "-0.02"),
        ("horizon_softness", "float", "0.24"),
        ("zenith_curve", "float", "1.65"),
        ("horizon_glow_strength", "float", "0.5")
    ]),
    ("NightSky", [
        ("night_lower_sky_color", "Color", "Color(0.03, 0.05, 0.09, 1)"),
        ("night_horizon_color", "Color", "Color(0.06, 0.1, 0.18, 1)"),
        ("night_zenith_color", "Color", "Color(0.01, 0.015, 0.03, 1)"),
        ("night_sky_energy", "float", "1.0"),
        ("stars_color", "Color", "Color(1.0, 1.0, 1.0, 1)"),
        ("stars_speed", "float", "0.1")
    ]),
    ("GI", [
        ("gi_tint", "Color", "Color(1.0, 1.0, 1.0, 1)"),
        ("gi_energy_multiplier", "float", "1.0")
    ]),
    ("Sun", [
        ("sun_color", "Color", "Color(1.0, 0.95, 0.8, 1)"),
        ("sun_disk_size", "float", "1.0"),
        ("sun_disk_softness", "float", "0.5"),
        ("sun_disk_strength", "float", "5.0"),
        ("sun_halo_size", "float", "1.0"),
        ("sun_halo_strength", "float", "1.5"),
        ("sun_atmosphere_size", "float", "1.0"),
        ("sun_atmosphere_strength", "float", "1.0"),
        ("sun_energy_scale", "float", "1.0")
    ]),
    ("Moon", [
        ("moon_color", "Color", "Color(0.9, 0.95, 1.0, 1)"),
        ("moon_size", "float", "1.0"),
        ("moon_glow_strength", "float", "1.0"),
        ("moon_eclipse_size", "float", "2.5")
    ]),
    ("Clouds", [
        ("cloud_tex_a", "Texture2D", "null"),
        ("cloud_tex_b", "Texture2D", "null"),
        ("cloud_scroll_a", "Vector2", "Vector2(0.0012, 0.00015)"),
        ("cloud_scroll_b", "Vector2", "Vector2(-0.0018, 0.0004)"),
        ("cloud_scale_a", "Vector2", "Vector2(0.045, 0.055)"),
        ("cloud_scale_b", "Vector2", "Vector2(0.082, 0.125)"),
        ("cloud_plane_height", "float", "0.25"),
        ("cloud_plane_curve", "float", "0.15"),
        ("cloud_warp_strength", "float", "0.14"),
        ("cloud_coverage", "float", "0.5"),
        ("cloud_softness", "float", "0.2"),
        ("cloud_opacity", "float", "0.6"),
        ("cloud_horizon_fade", "float", "0.3"),
        ("cloud_top_fade", "float", "0.2"),
        ("cloud_light_color", "Color", "Color(1.0, 0.98, 0.95, 1)"),
        ("cloud_shadow_color", "Color", "Color(0.4, 0.45, 0.55, 1)"),
        ("cloud_forward_scatter", "float", "1.5"),
        ("cloud_backscatter", "float", "0.2"),
        ("sun_cloud_occlusion", "float", "0.8")
    ])
]

updated_props = []
for g_name, g_props in props:
    new_g = []
    for p_name, p_type, default in g_props:
        if p_name in params:
            new_g.append((p_name, p_type, params[p_name]))
        else:
            new_g.append((p_name, p_type, default))
    updated_props.append((g_name, new_g))

# --- 3. Generate Skydome.gd ---

out = """@tool
class_name Skydome
extends Node

const SUN_SHAFTS_EFFECT_SCRIPT := preload("res://scenery/SunShaftsCompositorEffect.gd")
const SKY_MATERIAL_RES := preload("res://scenery/materials/M_filmic_procedural_sky.tres")
const SKY_RES := preload("res://materials/sky_filmic.tres")

@export_group("Time & Date")
@export_range(1, 365) var day_of_year: int = 180:
	set(v):
		day_of_year = v
		_update_sun_transform()
@export_range(0.0, 24.0) var time_of_day: float = 12.0:
	set(v):
		time_of_day = v
		_update_sun_transform()
@export_range(-90.0, 90.0) var latitude: float = 45.0:
	set(v):
		latitude = v
		_update_sun_transform()

@export_group("Light Settings")
@export var sun_light_color: Color = Color(1.0, 0.93, 0.85)
@export var sun_light_energy: float = 1.28
@export var moon_light_color: Color = Color(0.6, 0.8, 1.0)
@export var moon_light_energy: float = 0.2
@export_range(0.0, 1.0) var moon_phase: float = 0.5:
	set(v):
		moon_phase = v
		_update_sun_transform()

@export_group("Nodes")
@export var directional_light_path: NodePath:
	set(v):
		directional_light_path = v
		_refresh()
@export var world_environment_path: NodePath:
	set(v):
		world_environment_path = v
		_refresh()

@export_group("Sunshafts")
@export var sunshafts_enabled: bool = true:
	set(v):
		sunshafts_enabled = v
		_update_effect()
@export var sunshafts_distance: float = 3000.0
@export var sunshafts_shaft_color: Color = Color(0.718, 0.637, 0.379, 1):
	set(v):
		sunshafts_shaft_color = v
		_update_effect()
@export var sunshafts_density: float = 0.485:
	set(v):
		sunshafts_density = v
		_update_effect()
@export var sunshafts_bright_threshold: float = 0.182:
	set(v):
		sunshafts_bright_threshold = v
		_update_effect()
@export var sunshafts_weight: float = 0.0355:
	set(v):
		sunshafts_weight = v
		_update_effect()
@export var sunshafts_decay: float = 0.93:
	set(v):
		sunshafts_decay = v
		_update_effect()
@export var sunshafts_exposure: float = 1.59:
	set(v):
		sunshafts_exposure = v
		_update_effect()
@export var sunshafts_max_radius: float = 1.377:
	set(v):
		sunshafts_max_radius = v
		_update_effect()

var _sky_material: ShaderMaterial
var _compositor_effect: CompositorEffect
var _is_ready: bool = false

"""

for group_name, group_props in updated_props:
    out += f'@export_group("Sky Shader: {group_name}")\n'
    for name, type_name, default in group_props:
        out += f'@export var shader_{name}: {type_name} = {default}:\n'
        out += f'\tset(v):\n'
        out += f'\t\tshader_{name} = v\n'
        out += f'\t\t_set_shader_param("{name}", v)\n'

out += """

func _enter_tree() -> void:
	if Engine.is_editor_hint() or is_inside_tree():
		_init_sky()

func _ready() -> void:
	_is_ready = true
	_init_sky()
	_update_sun_transform()
	set_process(true)

func _process(_delta: float) -> void:
	_update_effect()

func _refresh() -> void:
	if is_inside_tree():
		_init_sky()

func _get_directional_light() -> DirectionalLight3D:
	if not directional_light_path.is_empty():
		return get_node_or_null(directional_light_path) as DirectionalLight3D
	return get_tree().current_scene.find_child("DirectionalLight3D", true, false) as DirectionalLight3D if get_tree().current_scene else null

func _get_world_environment() -> WorldEnvironment:
	if not world_environment_path.is_empty():
		return get_node_or_null(world_environment_path) as WorldEnvironment
	return get_tree().current_scene.find_child("WorldEnvironment", true, false) as WorldEnvironment if get_tree().current_scene else null

func _init_sky() -> void:
	var env_node = _get_world_environment()
	if not env_node: return
	var env = env_node.environment
	if not env: return
	
	if env.sky != SKY_RES:
		env.sky = SKY_RES
	
	_sky_material = SKY_MATERIAL_RES
	if _sky_material and _is_ready:
		_sync_shader_params()

func _set_shader_param(param_name: String, value: Variant) -> void:
	if not _sky_material:
		_sky_material = SKY_MATERIAL_RES
	if _sky_material:
		_sky_material.set_shader_parameter(param_name, value)

func _sync_shader_params() -> void:
	if not _sky_material: return
"""

for group_name, group_props in updated_props:
    for name, type_name, default in group_props:
        out += f'\t_sky_material.set_shader_parameter("{name}", shader_{name})\n'

out += """
func _update_sun_transform() -> void:
	var light = _get_directional_light()
	if not light: return
	
	var delta_deg = -23.45 * cos(deg_to_rad(360.0 / 365.0 * (day_of_year + 10.0)))
	var declination = deg_to_rad(delta_deg)
	var hour_angle = deg_to_rad(15.0 * (time_of_day - 12.0))
	var lat_rad = deg_to_rad(latitude)
	
	var get_dir = func(ha: float, dec: float) -> Vector3:
		var y = sin(lat_rad) * sin(dec) + cos(lat_rad) * cos(dec) * cos(ha)
		var x = -cos(dec) * sin(ha)
		var z = sin(lat_rad) * cos(dec) * cos(ha) - cos(lat_rad) * sin(dec)
		return Vector3(x, y, z).normalized()
		
	var sun_dir = get_dir.call(hour_angle, declination)
	var moon_hour_angle = hour_angle - moon_phase * TAU
	var moon_dir = get_dir.call(moon_hour_angle, -declination * 0.5)
	
	_set_shader_param("custom_sun_dir", sun_dir)
	_set_shader_param("custom_moon_dir", moon_dir)
	
	var dir_to_basis = func(dir: Vector3) -> Basis:
		var up = Vector3.UP
		if abs(dir.y) > 0.999:
			up = Vector3.RIGHT
		var right = up.cross(dir).normalized()
		var new_up = dir.cross(right).normalized()
		return Basis(right, new_up, dir)
		
	var s_alt = sun_dir.y
	var m_alt = moon_dir.y
	
	if s_alt > 0.0:
		light.global_transform.basis = dir_to_basis.call(sun_dir)
		light.light_color = sun_light_color
		light.light_energy = sun_light_energy * smoothstep(0.0, 0.05, s_alt)
	else:
		light.global_transform.basis = dir_to_basis.call(moon_dir)
		light.light_color = moon_light_color
		light.light_energy = moon_light_energy * smoothstep(0.0, 0.05, m_alt)

func _ensure_effect_installed() -> void:
	var env_node = _get_world_environment()
	if not env_node: return
	var compositor = env_node.compositor
	if not compositor:
		compositor = Compositor.new()
		env_node.compositor = compositor
	
	var effects: Array[CompositorEffect] = compositor.compositor_effects
	effects = effects.filter(func(item): return item != null)
	
	var existing: CompositorEffect = null
	for item in effects:
		if item.get_script() == SUN_SHAFTS_EFFECT_SCRIPT:
			existing = item
			break
			
	if existing:
		_compositor_effect = existing
	else:
		_compositor_effect = SUN_SHAFTS_EFFECT_SCRIPT.new()
		effects.append(_compositor_effect)
		compositor.compositor_effects = effects

func _update_effect() -> void:
	_ensure_effect_installed()
	if not _compositor_effect: return
	
	if not sunshafts_enabled:
		_compositor_effect.set("sun_visible", false)
		return
		
	var light = _get_directional_light()
	if not light:
		_compositor_effect.set("sun_visible", false)
		return
		
	var camera = _get_active_camera()
	if not camera:
		_compositor_effect.set("sun_visible", false)
		return
		
	var viewport_size = _get_active_viewport_size()
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		_compositor_effect.set("sun_visible", false)
		return
		
	var sun_dir = light.global_transform.basis.z.normalized()
	# The basis.z is actually the direction towards the light source in our setup
	var sun_world_pos = camera.global_position + (sun_dir * sunshafts_distance)
	
	if camera.is_position_behind(sun_world_pos):
		_compositor_effect.set("sun_visible", false)
		return
		
	var screen_pos = camera.unproject_position(sun_world_pos)
	_compositor_effect.set("sun_screen_uv", Vector2(screen_pos.x / viewport_size.x, screen_pos.y / viewport_size.y))
	_compositor_effect.set("sun_visible", true)
	
	_compositor_effect.set("shaft_color", sunshafts_shaft_color)
	_compositor_effect.set("density", sunshafts_density)
	_compositor_effect.set("bright_threshold", sunshafts_bright_threshold)
	_compositor_effect.set("weight", sunshafts_weight)
	_compositor_effect.set("decay", sunshafts_decay)
	_compositor_effect.set("exposure", sunshafts_exposure)
	_compositor_effect.set("max_radius", sunshafts_max_radius)

func _get_active_camera() -> Camera3D:
	if Engine.is_editor_hint():
		var editor_iface = Engine.get_singleton(&"EditorInterface")
		if editor_iface:
			var vp = editor_iface.get_editor_viewport_3d(0)
			if vp: return vp.get_camera_3d()
	return get_viewport().get_camera_3d()

func _get_active_viewport_size() -> Vector2:
	if Engine.is_editor_hint():
		var editor_iface = Engine.get_singleton(&"EditorInterface")
		if editor_iface:
			var vp = editor_iface.get_editor_viewport_3d(0)
			if vp: return vp.get_visible_rect().size
	return get_viewport().get_visible_rect().size
"""

with open(gd_path, "w") as f:
    f.write(out)

print("Night mode deployed successfully.")
