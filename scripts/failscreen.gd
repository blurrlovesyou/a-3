extends Control

signal finished

@export var window_scene: PackedScene = preload("res://scenes/window.tscn")
@export var window_scale := 0.6            
@export var spam_count := 14
@export var spam_interval := 0.18
@export var final_size := Vector2(800, 360)
@export var final_font_size := 48

@onready var windows: Control = %windows
@onready var glitch: ColorRect = %glitch
@onready var static_rect: ColorRect = %static
@onready var black: ColorRect = %black

const FAKE_LINES := [
	"tracing route to {ip} ...",
	"packet received from {ip}",
	"geolocating {ip} ... OK",
	"ISP identified: {ip}",
	"matching biometric profile ...",
	"HUMAN SIGNATURE DETECTED",
	"dispatching unit to {ip}",
	"uploading session log ...",
]

var _playing := false

func _ready() -> void:
	hide()
	visibility_changed.connect(_on_visibility_changed)

func _on_visibility_changed() -> void:
	if visible and not _playing:
		play()

func play() -> void:
	if _playing:
		return
	_playing = true
	_reset()
	show()

	# terminal spam, glitch appears after a while
	var glitch_start := int(spam_count * 0.5)
	for i in spam_count:
		_spawn_window("trace.exe", _fake_text(), Vector2(420, 260), window_scale, 0, false)
		if i == glitch_start:
			_set_glitch(0.4, 1.5)
		await get_tree().create_timer(spam_interval).timeout

	# final message (glitch amnt stays low so it's readable)
	_spawn_window("!!!", "WE FOUND YOU.", final_size, 1.0, final_font_size, true)
	await get_tree().create_timer(2.0).timeout

	# glitch goes crazyyy, then static, then black
	_set_glitch(1.0, 1.0)
	await get_tree().create_timer(1.0).timeout
	static_rect.show()
	await get_tree().create_timer(1.2).timeout
	black.show()
	finished.emit()


func _set_glitch(value: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(glitch.material, "shader_parameter/intensity", value, duration)

func _reset() -> void:
	for w in windows.get_children():
		w.queue_free()
	glitch.material.set_shader_parameter("intensity", 0.15)
	static_rect.hide()
	black.hide()

func _fake_text() -> String:
	var lines := PackedStringArray()
	for i in 8:
		var ip := "%d.%d.%d.%d" % [randi_range(1, 255), randi_range(0, 255), randi_range(0, 255), randi_range(1, 255)]
		lines.append(FAKE_LINES.pick_random().replace("{ip}", ip))
	return "\n".join(lines)

func _spawn_window(title: String, text: String, win_size: Vector2, win_scale: float, font_size: int, final: bool) -> void:
	var win = window_scene.instantiate()
	win.closable = false
	windows.add_child(win)
	win.size = win_size
	win.scale = Vector2(win_scale, win_scale)

	var area: Vector2 = size if size.x > 0.0 else get_viewport_rect().size
	var visual_size: Vector2 = win_size * win_scale
	if final:
		win.position = (area - visual_size) / 2.0
	else:
		win.position = Vector2(randf_range(0, area.x - visual_size.x), randf_range(0, area.y - visual_size.y))
	win.set_title(title)

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	win.set_content(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color(1, 0.2, 0.2) if final else Color(0.3, 1, 0.4))
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	if final:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bg.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

#TEMPORARY!! press F9 to test the fail screen
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		play()
