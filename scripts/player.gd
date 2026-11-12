extends CharacterBody3D

const SPEED = 2.0
const SPRINT_SPEED = 3.0
const JUMP_VELOCITY = 3.0

var gravity = 8.0

@export var mouse_sensitivity = 0.003
@export var jump_sounds: Array[AudioStream] = []
@export var walk_sounds: Array[AudioStream] = []
@export var land_sounds: Array[AudioStream] = []
@export var walk_step_interval := 0.25

@onready var camera: Camera3D = $Camera3D

var was_on_floor := false
var footstep_timer := 0.0
var is_sprinting := false

#flag so the computer can tell the player to freeze
var is_locked_in := false


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event):
	if is_locked_in:
		return

	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))


func _physics_process(delta):
	if is_locked_in:
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		play_random_sound(jump_sounds)

	var input_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		input_dir.x += 1

	input_dir = input_dir.normalized()
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var current_speed = SPEED
	walk_step_interval = 0.25

	if is_on_floor() and Input.is_key_pressed(KEY_SHIFT):
		is_sprinting = true
	elif is_on_floor():
		is_sprinting = false

	if is_sprinting:
		current_speed = SPRINT_SPEED
		walk_step_interval = 0.15

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	was_on_floor = is_on_floor()
	move_and_slide()

	if not was_on_floor and is_on_floor():
		play_random_sound(land_sounds)

	if is_on_floor() and direction.length() > 0:
		footstep_timer -= delta
		if footstep_timer <= 0:
			play_random_sound(walk_sounds)
			footstep_timer = walk_step_interval
	else:
		footstep_timer = 0.0


func play_random_sound(sounds: Array[AudioStream]):
	if sounds.is_empty():
		return
	var sound = sounds.pick_random()
	if sound == null:
		return

	var player = AudioStreamPlayer3D.new()
	add_child(player)
	player.stream = sound
	player.volume_db = -35.0
	player.finished.connect(player.queue_free)
	player.play()
