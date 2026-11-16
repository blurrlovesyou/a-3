extends Control

@export var video_player: VideoStreamPlayer
@export var stop_button: Button

func _ready():
	if stop_button:
		stop_button.pressed.connect(_on_button_pressed)
		update_button_text()

func _on_button_pressed():
	if video_player.is_playing():
		video_player.stop()
	else:
		video_player.play()
	update_button_text()

func update_button_text():
	if video_player.is_playing():
		stop_button.text = "stop the bob"
	else:
		stop_button.text = "start the bob"
