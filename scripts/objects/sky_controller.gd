extends WorldEnvironment
## Exposes weather hooks (cloud cover, rain) on the sky.gdshader material so
## future weather features can tie in. Cloud drift/shape animation happens
## entirely inside the shader (driven by TIME), so no per-frame work is
## needed here.

## Opacity of the cloud layer; higher values mean more overcast skies.
## Maps to the shader's clouds_cutoff (inverted: lower cutoff = more cloud).
@export_range(0.0, 1.0) var cloud_cover: float = 0.35
## Whether it's currently raining; darkens the clouds/sky when true.
@export var raining: bool = false

var _sky_material: ShaderMaterial


func _ready() -> void:
	if environment and environment.sky:
		_sky_material = environment.sky.sky_material as ShaderMaterial
	_apply_weather()


func set_raining(value: bool) -> void:
	raining = value
	_apply_weather()


func set_cloud_cover(value: float) -> void:
	cloud_cover = clampf(value, 0.0, 1.0)
	_apply_weather()


func _apply_weather() -> void:
	if not _sky_material:
		return
	_sky_material.set_shader_parameter("clouds_cutoff", clampf(0.6 - cloud_cover * 0.5, 0.05, 0.6))
	_sky_material.set_shader_parameter("clouds_weight", 0.85 if raining else 0.0)
