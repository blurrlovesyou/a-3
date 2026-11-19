extends Node2D
##"webcam check" event challange
## if user moves during the webcam check then they hit a fail state, otherwise it passes

signal webcam_started
signal webcam_ended #emitted on both success and fail
signal succeeded
signal failed

#!!! take proper look at what to select if we export as EXE
enum ColorMode {RAW_RGB, GRAYSCALE, YCBCR_SINGLE, YCBCR_SEPARATE}

@export_group("Timing")
@export var min_wait_time: float = 20.0
@export var max_wait_time: float = 60.0
@export var webcam_duration: float = 10.0
@export var terminal_flash_time: float = 0.15
#seconds at the start of the visible event where movement is ignored.
@export var grace_time: float = 0.5
@export var prewarm_lead_time: float = 2.0 #time for the camera to send frames
@export var prewarm_timeout: float = 8.0 #if no frames after 8 sec, send error

@export_group("Movement")
@export_range(0.0, 1.0, 0.01) var movement_threshold: float = 0.4
@export var sensitivity: float = 300.0 #mulitplier (also check this on multiple devices if it holds up)
@export_range(0.01, 1.0, 0.01) var meter_smoothing: float = 0.4

@export_group("Controls")
@export var terminal_control: Control
@export var failed_control: Control
@export var cameraborder_control: Control

@export_group("Webcam View")
@export var webcam_position: Vector2 = Vector2(40, 40)
@export var webcam_size: Vector2 = Vector2(320, 240)
@export var color_mode: ColorMode = ColorMode.RAW_RGB #CHECK BEST WITH TA BEFORE LAUNCH


var webcam_active: bool = false
const METER_WIDTH := 18.0
const ANALYSIS_SIZE := Vector2i(32, 24)
const ANALYSIS_INTERVAL := 0.1
const READY_FRAMES := 5

const SHADER_CODE := """
shader_type canvas_item;

uniform sampler2D cbcr_tex : filter_linear;
uniform int mode = 0; // 0 raw, 1 gray (Y only), 2 YCbCr single, 3 YCbCr separate

vec3 ycbcr_to_rgb(float y, float cb, float cr) {
	cb -= 0.5;
	cr -= 0.5;
	return vec3(y + 1.402 * cr, y - 0.344136 * cb - 0.714136 * cr, y + 1.772 * cb);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 rgb = c.rgb;
	if (mode == 1) {
		rgb = vec3(c.r);
	} else if (mode == 2) {
		rgb = ycbcr_to_rgb(c.r, c.g, c.b);
	} else if (mode == 3) {
		vec2 cbcr = texture(cbcr_tex, UV).rg;
		rgb = ycbcr_to_rgb(c.r, cbcr.x, cbcr.y);
	}
	COLOR = vec4(rgb, 1.0);
}
"""

signal _event_finished(success: bool)

var _view: Control
var _texture_rect: TextureRect
var _material: ShaderMaterial
var _meter: ProgressBar
var _threshold_line: ColorRect

var _feed: CameraFeed
var _cam_texture: CameraTexture
var _cbcr_texture: CameraTexture
var _applied_mode: int = -1

var _running: bool = false
var _aborted: bool = false
var _camera_on: bool = false #camera running (hidden or visible)
var _good_frames: int = 0
var _elapsed: float = 0.0
var _analysis_timer: float = 0.0
var _prev_frame: PackedByteArray = PackedByteArray()
var _motion: float = 0.0


func _ready() -> void:
	_build_webcam_view()
	terminal_control.hide()
	failed_control.hide()
	cameraborder_control.hide()
	CameraServer.set("monitoring_feeds", true) #aks for camera permission and list feeds
	_running = true
	_aborted = false
	_run_loop()

func _run_loop() -> void:
	while _running:
		var wait_time := randf_range(minf(min_wait_time, max_wait_time), maxf(min_wait_time, max_wait_time))
		var lead := minf(prewarm_lead_time, wait_time)
		await get_tree().create_timer(wait_time - lead).timeout
		if not _running:
			return

		var t0 := Time.get_ticks_msec()
		await _prewarm_camera()
		if not _running: #keep checking as time passes
			_close_camera()
			return

		var remaining := lead - (Time.get_ticks_msec() - t0) / 1000.0
		if remaining > 0.0:
			await get_tree().create_timer(remaining).timeout
			if not _running:
				_close_camera()
				return

		#flash the terminal for split second (as a warning for the plaer to not move and visual style)
		terminal_control.show()
		await get_tree().create_timer(terminal_flash_time).timeout
		terminal_control.hide()
		
		if not _running:
			_close_camera()
			return
		_show_webcam()

		var success: bool = await _event_finished
		_close_camera()
		if _aborted:
			return

		if success:
			succeeded.emit()
		else:
			if failed_control:
				failed_control.show()
			failed.emit()
			_running = false # stop after a fail



# ----------------- CAMERA STUFF ---------------------------
func _prewarm_camera() -> void:
	await _activate_camera()
	if _feed == null:
		return

	var waited := 0.0
	while _running and _good_frames < READY_FRAMES and waited < prewarm_timeout:
		await get_tree().create_timer(ANALYSIS_INTERVAL).timeout
		waited += ANALYSIS_INTERVAL
		_configure_textures()

	if _good_frames < READY_FRAMES:
		push_warning("WebcamEvent: camera did not deliver valid frames within %.1fs." % prewarm_timeout)


func _activate_camera() -> void:
	var feeds := CameraServer.feeds()
	if feeds.is_empty():
		await get_tree().create_timer(0.5).timeout
		feeds = CameraServer.feeds()

	_good_frames = 0
	_prev_frame = PackedByteArray()
	_applied_mode = -1
	_motion = 0.0
	_analysis_timer = 0.0

	if feeds.is_empty():
		push_warning("WebcamEvent: no camera feed found. Running without video (motion stays 0).")
		_feed = null
		_cam_texture = null
		_cbcr_texture = null
		_texture_rect.texture = null
		_camera_on = true
		return

	_feed = feeds[0]
	_feed.feed_is_active = true
	_camera_on = true
	_configure_textures()


func _configure_textures() -> void:
	if _feed == null:
		return
	var mode := color_mode
	if mode == _applied_mode:
		return
	_applied_mode = mode

	_cam_texture = CameraTexture.new()
	_cam_texture.camera_feed_id = _feed.get_id()
	match mode:
		ColorMode.RAW_RGB:
			_cam_texture.which_feed = CameraServer.FEED_RGBA_IMAGE
		ColorMode.YCBCR_SINGLE:
			_cam_texture.which_feed = CameraServer.FEED_YCBCR_IMAGE
		_:
			_cam_texture.which_feed = CameraServer.FEED_Y_IMAGE

	_cbcr_texture = null
	if mode == ColorMode.YCBCR_SEPARATE:
		_cbcr_texture = CameraTexture.new()
		_cbcr_texture.camera_feed_id = _feed.get_id()
		_cbcr_texture.which_feed = CameraServer.FEED_CBCR_IMAGE

	_texture_rect.texture = _cam_texture
	_material.set_shader_parameter("mode", mode)
	_material.set_shader_parameter("cbcr_tex", _cbcr_texture)
	_good_frames = 0
	_prev_frame = PackedByteArray()


func _show_webcam() -> void:
	_elapsed = 0.0
	_motion = 0.0
	_meter.value = 0.0
	_update_threshold_line()
	_view.show()
	cameraborder_control.show()
	webcam_active = true
	webcam_started.emit()


func _close_camera() -> void:
	var was_visible := _view.visible
	webcam_active = false
	_camera_on = false
	if _feed:
		_feed.feed_is_active = false
	_view.hide()
	cameraborder_control.hide()
	_prev_frame = PackedByteArray()
	_good_frames = 0
	if was_visible:
		webcam_ended.emit()


func _finish(success: bool, aborted: bool = false) -> void:
	if not webcam_active:
		return
	webcam_active = false #stops judging immediately
	_aborted = aborted
	_event_finished.emit(success)


func _process(delta: float) -> void:
	if not _camera_on:
		return

	_analysis_timer += delta
	if webcam_active:
		_elapsed += delta

	#sampoles frames the whole time the camera is on (also while hidden), so the first visible frame is always compared against a real previous frame
	#otherwise it would trigger fail state the second there is input
	if _analysis_timer >= ANALYSIS_INTERVAL:
		_analysis_timer = 0.0
		var raw := _sample_motion()
		if webcam_active:
			if raw < 0.0 or _elapsed < grace_time:
				raw = 0.0
			var target := clampf(raw * sensitivity, 0.0, 1.0)
			_motion = lerpf(_motion, target, meter_smoothing)
			_meter.value = _motion

	if webcam_active:
		if _elapsed >= grace_time and _motion > movement_threshold:
			_finish(false) #succes
		elif _elapsed >= webcam_duration:
			_finish(true) #fail


#average per-pixel brightness change vs. the previous frame (0..1).
#retrns -1 if no input
func _sample_motion() -> float:
	if _cam_texture == null:
		return -1.0
	var img := _cam_texture.get_image()
	if img == null or img.is_empty():
		_good_frames = 0
		_prev_frame = PackedByteArray()
		return -1.0

	img.resize(ANALYSIS_SIZE.x, ANALYSIS_SIZE.y, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_L8)
	var data := img.get_data()

	var brightness_sum := 0
	var diff_sum := 0
	var has_prev := _prev_frame.size() == data.size()
	for i in data.size():
		brightness_sum += data[i]
		if has_prev:
			diff_sum += absi(int(data[i]) - int(_prev_frame[i]))

	if brightness_sum == 0:
		#black frame = camera not delivering real data yet. (or user has tape on cam maybe idk)
		_good_frames = 0
		_prev_frame = PackedByteArray()
		return -1.0

	_good_frames += 1
	_prev_frame = data
	if not has_prev:
		return 0.0
	return float(diff_sum) / (data.size() * 255.0)


#view the webcam and and the meterrrrrrr
func _build_webcam_view() -> void:
	_view = Control.new()
	_view.name = "WebcamView"
	_view.visible = false
	add_child(_view)
	_view.position = webcam_position

	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader

	_texture_rect = TextureRect.new()
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_texture_rect.flip_h = true
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture_rect.material = _material
	_view.add_child(_texture_rect)
	_texture_rect.position = Vector2.ZERO
	_texture_rect.size = webcam_size

	_meter = ProgressBar.new()
	_meter.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	_meter.show_percentage = false
	_meter.min_value = 0.0
	_meter.max_value = 1.0
	_meter.step = 0.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1, 0, 0, 0.6)
	_meter.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	_meter.add_theme_stylebox_override("background", bg)
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_meter)
	_meter.position = Vector2(webcam_size.x - 16.0, 0.0) #inside the window
	_meter.size = Vector2(METER_WIDTH, webcam_size.y)

	_threshold_line = ColorRect.new()
	_threshold_line.color = Color.WHITE
	_threshold_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_threshold_line)
	_update_threshold_line()


func _update_threshold_line() -> void:
	var y := webcam_size.y * (1.0 - movement_threshold)
	_threshold_line.size = Vector2(METER_WIDTH + 8.0, 8.0)
	_threshold_line.position = Vector2(webcam_size.x - 21.0, y - 1.0)
