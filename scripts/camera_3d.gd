extends Camera3D
@export var pixel_effect: ColorRect
@export var rotation_start_speed: float = 0.5
@export var rotation_max_speed: float = 3.0
@export var rotation_smoothing: float = 8.0
@export var fade_time: float = 1.5
var previous_rotation: Quaternion
var rotation_amount: float = 0.0
var shader_material: ShaderMaterial

func _ready() -> void:
	previous_rotation = global_transform.basis.get_rotation_quaternion()

func _process(delta: float) -> void:
	if not current:
		return
		
	shader_material = pixel_effect.material as ShaderMaterial
	var current_rotation: Quaternion = global_transform.basis.get_rotation_quaternion()
	var angle_difference: float = previous_rotation.angle_to(current_rotation)
	var rotation_speed: float = angle_difference / max(delta, 0.0001)
	var target: float = remap(rotation_speed, rotation_start_speed, rotation_max_speed, 0.0, 1.0)
	target = clamp(target, 0.0, 1.0)
	rotation_amount = lerp(rotation_amount, target, 1.0 - exp(-rotation_smoothing * delta))
	shader_material.set_shader_parameter("rotation_amount",rotation_amount) #send to shader
	
	var camera_height: float = clamp(global_position.y, -2500.0, 2500.0)
	var height_amount: float = remap(camera_height, -2500.0, 2500.0, 0.0, 1.0 )
	height_amount = clamp(height_amount, 0.0, 1.0)
	previous_rotation = current_rotation #remember for next frame
