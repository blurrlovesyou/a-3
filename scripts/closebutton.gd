extends Control

signal closed

@export var closable := true

@onready var close_button: TextureButton = %CloseButton

func _ready() -> void:
	close_button.visible = closable
	close_button.pressed.connect(_on_close_pressed)

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()

func set_content(node: Node) -> void:
	%Content.add_child(node)

func set_title(text: String) -> void:
	%Title.text = text
