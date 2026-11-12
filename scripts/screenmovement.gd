extends Area3D

@export_group("Camera Target")
@export var camera_target: Marker3D #positino for camera
@export var transition_time := 1.0
@export var camera_follow_amount := 0.03
@export var camera_follow_speed := 10.0

@export_group("UI References")
@export var computer_screen: Control
@export var interaction_label: Label
@export var screen_input: ScreenInput

var player: CharacterBody3D = null
var camera: Camera3D = null
var can_interact := false
var is_using_computer := false
var is_transitioning := false

var original_camera_transform: Transform3D #original locaiton of camera before entering


func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if computer_screen:
		computer_screen.hide()
	if interaction_label:
		interaction_label.hide()


func _unhandled_input(event):
	if is_using_computer:
		if not is_transitioning and (event.is_action_pressed("ui_cancel")):
			exit_computer()
		return

	if can_interact and event.is_action_pressed("interact"):
		enter_computer()


func _on_body_entered(body: Node3D):
	if body is CharacterBody3D:
		player = body
		camera = player.get_node_or_null("Camera3D") # Assumes camera is a child of the player
		if camera:
			can_interact = true
			if interaction_label:
				interaction_label.show()


func _on_body_exited(body: Node3D):
	if body == player:
		can_interact = false
		if interaction_label:
			interaction_label.hide()
		player = null
		camera = null


func enter_computer():
	is_using_computer = true
	is_transitioning = true

	#tell player scritp to freeze
	if "is_locked_in" in player:
		player.is_locked_in = true

	original_camera_transform = camera.global_transform

	if interaction_label:
		interaction_label.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


	var start_transform = camera.global_transform
	var target_transform = camera_target.global_transform
	var start_quat = start_transform.basis.get_rotation_quaternion()
	var target_quat = target_transform.basis.get_rotation_quaternion()

	var tween = create_tween()
	tween.tween_method(
		func(weight: float):
			camera.global_transform.origin = start_transform.origin.lerp(target_transform.origin, weight)
			var interpolated_quat = start_quat.slerp(target_quat, weight)
			camera.global_transform.basis = Basis(interpolated_quat),
		0.0,
		1.0,
		transition_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tween.tween_callback(func():
		if computer_screen:
			computer_screen.show()
		if screen_input:
			screen_input.set_active(true)
		is_transitioning = false
	)


func exit_computer():
	if not player or not camera:
		return

	if screen_input:
		screen_input.set_active(false)
		
	is_transitioning = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var start_transform = camera.global_transform
	var target_transform = original_camera_transform

	var start_quat = start_transform.basis.get_rotation_quaternion()
	var target_quat = target_transform.basis.get_rotation_quaternion()

	var tween = create_tween()
	tween.tween_method(
		func(weight: float):
			camera.global_transform.origin = start_transform.origin.lerp(target_transform.origin, weight)
			var interpolated_quat = start_quat.slerp(target_quat, weight)
			camera.global_transform.basis = Basis(interpolated_quat),
		0.0,
		1.0,
		transition_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tween.tween_callback(func():
		if "is_locked_in" in player:
			player.is_locked_in = false
		is_using_computer = false
		is_transitioning = false
	)


func _process(delta):
	if not is_using_computer or is_transitioning or not computer_screen or not computer_screen.visible or not camera or not camera_target:
		return

	# Get mouse offset from the center of the screen (-0.5 to 0.5)
	var viewport_size = get_viewport().get_visible_rect().size
	var mouse_position = get_viewport().get_mouse_position()
	var mouse_offset = (mouse_position / viewport_size) - Vector2(0.5, 0.5)

	# Start with the marker's global rotation as the base, then apply mouse offset
	var base_euler = camera_target.global_rotation
	var target_euler = base_euler + Vector3(
		-mouse_offset.y * camera_follow_amount,
		-mouse_offset.x * camera_follow_amount,
		0.0
	)

	var target_quat = Basis.from_euler(target_euler).get_rotation_quaternion()
	var current_quat = camera.global_transform.basis.get_rotation_quaternion()

	# Smoothly slerp to the mouse-adjusted target rotation
	camera.global_transform.basis = Basis(current_quat.slerp(target_quat, camera_follow_speed * delta))
