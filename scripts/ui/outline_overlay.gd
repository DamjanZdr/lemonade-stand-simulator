extends Node
## Screen-space silhouette outline system.
##
## Architecture:
##   1. Highlighted interactables get "_Outline" child MeshInstance3D nodes
##      placed on render layer 2 with a flat white unshaded material.
##   2. The SubViewport's OutlineCamera (cull_mask=2) renders ONLY those fills
##      against a transparent background → solid white silhouette texture.
##   3. A canvas edge-detect shader on DisplayRect reads that texture and
##      draws only the border pixels as yellow.
##
## The main Camera3D has bit 2 excluded from its cull_mask, so the fill
## nodes are completely invisible in the main view.

const _OUTLINE_SHADER := preload("res://scripts/shaders/outline.gdshader")

@onready var _subvp:   SubViewport = $SubViewport
@onready var _cam:     Camera3D    = $SubViewport/OutlineCamera
@onready var _display: TextureRect = $OverlayLayer/DisplayRect

var _main_cam: Camera3D = null


func _ready() -> void:
	# Resize SubViewport to always match the window.
	_subvp.size = get_viewport().size
	get_viewport().size_changed.connect(func(): _subvp.size = get_viewport().size)

	# Build the edge-detect material and point it at the SubViewport texture.
	var mat := ShaderMaterial.new()
	mat.shader = _OUTLINE_SHADER
	_display.material = mat
	_display.texture  = _subvp.get_texture()

	# Dev panel live controls.
	EventBus.debug_set_outline_width.connect(_on_set_width)
	EventBus.debug_set_outline_color.connect(_on_set_color)


func _on_set_width(width: float) -> void:
	(_display.material as ShaderMaterial).set_shader_parameter("outline_width", width)


func _on_set_color(color: Color) -> void:
	(_display.material as ShaderMaterial).set_shader_parameter("outline_color", color)


func setup(main_cam: Camera3D) -> void:
	_main_cam = main_cam


func _process(_delta: float) -> void:
	if _main_cam == null:
		return
	# Mirror main camera every frame so the outline mask stays in sync.
	_cam.global_transform = _main_cam.global_transform
	_cam.fov  = _main_cam.fov
	_cam.near = _main_cam.near
	_cam.far  = _main_cam.far
