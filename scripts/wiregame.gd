extends Control

signal server_reached(index: int)
signal fizzled
signal finished
signal lives_changed(remaining: int)
signal firewall_caught
signal game_over

@export var virus_speed := 180.0
@export var fizzle_time := 0.5
@export var pan_time := 0.8
@export var pan_margin := 80.0
@export var drag_radius := 22.0
@export var debug_draw := false
@export var test_start_key := KEY_CAPSLOCK   # TEMPORARY: starts/restarts the minigame while testing (KEY_NONE turns it off)

@export_group("firewall")
@export var firewall_speed := 30.0
@export var firewall_start_gap := 180.0
@export var firewall_width := 32.0
@export var firewall_visible_width := 32.0   # how much of the firewall stays on screen once it pushes the view
@export var virus_hit_radius := 8.0
@export var max_lives := 2

@export_group("glow")
@export var glow_range := 320.0              # distance at which the glow starts to appear
@export var glow_width := 140.0
@export var glow_strength := 0.8
@export var glow_color := Color(0.687, 0.312, 0.332, 1.0)

@export_group("overlays")
@export var overlay_font: Font               # drag a font file in here (empty = use the theme font)
@export var title_size := 32
@export var subtitle_size := 16
@export var win_title := "ACCESS GRANTED"
@export var win_subtitle := "SERVER 001 OFFLINE"
@export var over_title := "GAME OVER: INFILTRATION DETECTED"
@export var over_subtitle := "Start again and avoid the firewall!"
@export var restart_on_click := true         # click the game over screen to try again

@export_group("hearts")
@export var heart_full: Texture2D            # drag your heart drawings in here
@export var heart_empty: Texture2D           # (squares are used until you do)
@export var heart_size := Vector2(24, 24)    # size on screen
@export var heart_gap := 6.0
@export var heart_margin := 12.0

var lives := 2
var firewall_active := true
var running := false
var cam_base := 0.0   # left edge of the view, as set by the segment panning

const MAX_STEPS := 2000
const TRANSPOSE_LAST := false

const BASE_OPEN := {
	"straight": [Vector2i.LEFT, Vector2i.RIGHT],
	"curve": [Vector2i.LEFT, Vector2i.DOWN],
	"cross": [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN],
	"plug": [Vector2i.RIGHT],
	"frayed": [Vector2i.LEFT],
	"broken": [Vector2i.LEFT, Vector2i.RIGHT],
}

enum State { IDLE, DRAGGING, RUNNING, FIZZLE, RETURNING, PANNING, DONE }

@onready var world: Node2D = $world
@onready var wires: TileMapLayer = $world/wires
@onready var virus: Node2D = $world/virus
@onready var firewall: Node2D = $world/firewall

var servers: Array[Vector2i] = []
var all_plugs: Array[Vector2i] = []

var _server_cells: Dictionary = {}
var _server_centers: Dictionary = {}

var _state := State.IDLE
var _current_server := Vector2i.ZERO
var _source_plug := Vector2i.ZERO

var _points := PackedVector2Array()
var _cum := PackedFloat32Array()
var _dist := 0.0
var _route: Dictionary = {}
var _timer := 0.0
var _mouse_pos := Vector2.ZERO

var _drag_line: Line2D
var _debug: Node2D
var _glow: TextureRect
var _win_overlay: ColorRect
var _over_overlay: ColorRect
var _hearts: Array[TextureRect] = []
var _heart_full_tex: Texture2D
var _heart_empty_tex: Texture2D
var _pan_tween: Tween


func _ready() -> void:
	_scan()

	if servers.is_empty():
		push_warning("wiregame: no server tiles found!")
		return

	_drag_line = Line2D.new()
	_drag_line.width = 4.0
	_drag_line.default_color = Color(0.353, 0.443, 0.545, 1.0)
	_drag_line.visible = false
	world.add_child(_drag_line)

	if debug_draw:
		_debug = Node2D.new()
		world.add_child(_debug)
		_debug.draw.connect(_draw_debug)
		_debug.queue_redraw()

	_build_overlays()

	for flame in firewall.get_children():
		if flame is AnimatedSprite2D:
			flame.play("burn")

	_reset()   # sets everything up, but the game only runs after start()


# ---------- starting and resetting ----------

func start() -> void:
	if servers.is_empty():
		return
	_reset()
	running = true


func stop() -> void:
	running = false


func _reset() -> void:
	if _pan_tween:
		_pan_tween.kill()

	_win_overlay.hide()
	_over_overlay.hide()
	lives = max_lives
	lives_changed.emit(lives)
	_update_hearts()
	firewall_active = true

	_current_server = servers[0]
	virus.position = _server_centers[_current_server]

	_points.clear()
	_cum.clear()
	_route.clear()
	_dist = 0.0

	_drag_line.visible = false
	_drag_line.clear_points()

	cam_base = _cam_target(_current_server)
	firewall.position = Vector2(_server_centers[_current_server].x - firewall_start_gap, -8.0)

	_find_source_plug()
	_state = State.IDLE
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if test_start_key == KEY_NONE:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == test_start_key:
		start()


# ---------- glow, hearts and overlays (built in code) ----------

func _build_overlays() -> void:
	# glow on the left edge of the view
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(glow_color.r, glow_color.g, glow_color.b, 0.9),
		Color(glow_color.r, glow_color.g, glow_color.b, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	tex.width = 64
	tex.height = 4

	_glow = TextureRect.new()
	_glow.texture = tex
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.modulate.a = 0.0
	add_child(_glow)
	_glow.position = Vector2.ZERO
	_glow.size = Vector2(glow_width, size.y)

	# hearts, top right corner
	_heart_full_tex = heart_full if heart_full else _placeholder(Color(0.9, 0.15, 0.2))
	_heart_empty_tex = heart_empty if heart_empty else _placeholder(Color(0.25, 0.1, 0.12))
	var total_w := max_lives * heart_size.x + (max_lives - 1) * heart_gap
	var start_x := size.x - heart_margin - total_w
	for i in max_lives:
		var rect := TextureRect.new()
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		rect.size = heart_size
		rect.position = Vector2(start_x + i * (heart_size.x + heart_gap), heart_margin)
		_hearts.append(rect)

	# win and game over screens
	_win_overlay = _make_overlay(win_title, win_subtitle, Color(0.3, 1.0, 0.4))
	_over_overlay = _make_overlay(over_title, over_subtitle, Color(1.0, 0.25, 0.2))
	_over_overlay.gui_input.connect(_on_over_gui_input)


func _make_overlay(title: String, subtitle: String, color: Color) -> ColorRect:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.8)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	overlay.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	box.add_child(_make_label(title, title_size, color))
	box.add_child(_make_label(subtitle, subtitle_size, Color(0.85, 0.85, 0.85)))
	return overlay


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if overlay_font:
		label.add_theme_font_override("font", overlay_font)
	return label


func _placeholder(color: Color) -> Texture2D:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _fade_in(overlay: ColorRect) -> void:
	overlay.modulate.a = 0.0
	overlay.show()
	create_tween().tween_property(overlay, "modulate:a", 1.0, 0.6)


func _show_win() -> void:
	_fade_in(_win_overlay)


func _show_game_over() -> void:
	_fade_in(_over_overlay)


func _on_over_gui_input(event: InputEvent) -> void:
	if restart_on_click and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		start()


func _update_hearts(animate := false) -> void:
	for i in _hearts.size():
		_hearts[i].texture = _heart_full_tex if i < lives else _heart_empty_tex
	if animate and lives >= 0 and lives < _hearts.size():
		# flicker the heart that was just lost
		var rect := _hearts[lives]
		var tween := create_tween()
		for i in 3:
			tween.tween_property(rect, "modulate:a", 0.1, 0.07)
			tween.tween_property(rect, "modulate:a", 1.0, 0.07)


# ---------- tilemap reading ----------

func _scan() -> void:
	servers.clear()
	all_plugs.clear()
	_server_cells.clear()
	_server_centers.clear()

	for cell in wires.get_used_cells():
		var kind := _kind(cell)

		if kind == "server":
			var source := wires.tile_set.get_source(
				wires.get_cell_source_id(cell)
			) as TileSetAtlasSource

			var span := source.get_tile_size_in_atlas(
				wires.get_cell_atlas_coords(cell)
			)

			var sum := Vector2.ZERO

			for x in range(span.x):
				for y in range(span.y):
					var c := cell + Vector2i(x, y)
					_server_cells[c] = cell
					sum += wires.map_to_local(c)

			_server_centers[cell] = sum / float(span.x * span.y)
			servers.append(cell)

		elif kind == "plug":
			all_plugs.append(cell)

	servers.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x
	)


func _kind(cell: Vector2i) -> String:
	var data := wires.get_cell_tile_data(cell)

	if data == null:
		return ""

	return str(data.get_custom_data("kind"))


func _open_dirs(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var kind := _kind(cell)

	if not BASE_OPEN.has(kind):
		return out

	var flip_h := wires.is_cell_flipped_h(cell)
	var flip_v := wires.is_cell_flipped_v(cell)
	var transpose := wires.is_cell_transposed(cell)

	for d in BASE_OPEN[kind]:
		out.append(_transform_dir(d, flip_h, flip_v, transpose))

	return out


func _transform_dir(d: Vector2i, flip_h: bool, flip_v: bool, transpose: bool) -> Vector2i:
	if not TRANSPOSE_LAST and transpose:
		d = Vector2i(d.y, d.x)

	if flip_h:
		d.x = -d.x

	if flip_v:
		d.y = -d.y

	if TRANSPOSE_LAST and transpose:
		d = Vector2i(d.y, d.x)

	return d


# ---------- finding the start plug ----------

func _find_source_plug() -> void:
	_source_plug = Vector2i.ZERO

	for plug in all_plugs:
		var opens := _open_dirs(plug)

		if opens.is_empty():
			continue

		# start plug is immediately next to the current server
		if _server_cells.has(plug - opens[0]):
			if _server_cells[plug - opens[0]] == _current_server:
				_source_plug = plug
				return

	push_warning("wiregame: couldn't find starting plug for server!")


# ---------- tracing routes ----------

func _trace(plug: Vector2i) -> Dictionary:
	var points := PackedVector2Array()
	points.append(wires.map_to_local(plug))

	var opens := _open_dirs(plug)

	if opens.is_empty():
		return {"points": points, "result": "dead", "target": Vector2i.ZERO}

	var dir: Vector2i = opens[0]
	var cur := plug
	var result := "dead"
	var target := Vector2i.ZERO

	for _i in range(MAX_STEPS):
		var nxt := cur + dir

		# reached a server
		if _server_cells.has(nxt):
			target = _server_cells[nxt]

			if target != _current_server:
				result = "arrived"
				points.append(wires.map_to_local(nxt))
				points.append(_server_centers[target])

			break

		var kind := _kind(nxt)
		var next_opens := _open_dirs(nxt)

		if kind == "" or not next_opens.has(-dir):
			break

		points.append(wires.map_to_local(nxt))
		cur = nxt

		if kind == "frayed":
			break

		if kind == "broken":
			result = "broken"
			break

		if kind == "cross":
			continue

		# straight/curve: take the other open side
		for d in next_opens:
			if d != -dir:
				dir = d
				break

	return {"points": points, "result": result, "target": target}


# ---------- dragging the plug ----------

func _gui_input(event: InputEvent) -> void:
	if not running:
		return

	if event is InputEventMouseButton:
		_mouse_pos = event.position

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _state == State.IDLE:
				_begin_drag(event.position)
			elif not event.pressed and _state == State.DRAGGING:
				_end_drag(event.position)

	elif event is InputEventMouseMotion:
		_mouse_pos = event.position


func _begin_drag(mouse_pos: Vector2) -> void:
	var mouse_world := mouse_pos - world.position
	var source_pos := wires.map_to_local(_source_plug)

	if source_pos.distance_to(mouse_world) > drag_radius:
		return

	_state = State.DRAGGING
	_drag_line.visible = true
	_drag_line.clear_points()
	_drag_line.add_point(source_pos)
	_drag_line.add_point(mouse_world)


func _end_drag(mouse_pos: Vector2) -> void:
	var mouse_world := mouse_pos - world.position
	var selected := Vector2i(-99999, -99999)

	var next_server_x := INF
	for server in servers:
		if server.x > _current_server.x:
			next_server_x = minf(next_server_x, float(server.x))

	for plug in all_plugs:
		if plug == _source_plug:
			continue

		# only look at plugs in the current segment
		if plug.x <= _source_plug.x or float(plug.x) >= next_server_x:
			continue

		if wires.map_to_local(plug).distance_to(mouse_world) <= drag_radius:
			selected = plug
			break

	if selected.x == -99999:
		_cancel_drag()
		return

	_launch(selected)


func _cancel_drag() -> void:
	_drag_line.visible = false
	_drag_line.clear_points()
	_state = State.IDLE


# ---------- sending the virus along the route ----------

func _launch(destination: Vector2i) -> void:
	var traced := _trace(destination)
	_route = traced

	_points = PackedVector2Array()
	_points.append(_server_centers[_current_server])
	_points.append(wires.map_to_local(_source_plug))
	_points.append(wires.map_to_local(destination))

	for point in traced["points"]:
		if point != _points[_points.size() - 1]:
			_points.append(point)

	_cum = PackedFloat32Array([0.0])

	for i in range(1, _points.size()):
		_cum.append(_cum[i - 1] + _points[i - 1].distance_to(_points[i]))

	_dist = 0.0
	_state = State.RUNNING

	_drag_line.set_point_position(1, wires.map_to_local(destination))


# ---------- every frame ----------

func _process(delta: float) -> void:
	if not running:
		return

	# the firewall creeps forward
	if firewall_active and _state != State.DONE:
		firewall.position.x += firewall_speed * delta

		# no catching while the view slides to the next segment
		if _state != State.PANNING and firewall.position.x + firewall_width >= virus.position.x - virus_hit_radius:
			_on_firewall_caught()
			return

	# virus movement
	if _points.size() >= 2:
		var total := _cum[_cum.size() - 1]

		match _state:
			State.RUNNING:
				_dist += virus_speed * delta

				if _dist >= total:
					_dist = total
					_on_route_end()

			State.FIZZLE:
				_timer -= delta

				if _timer <= 0.0:
					_state = State.RETURNING

			State.RETURNING:
				_dist -= virus_speed * delta

				if _dist <= 0.0:
					_dist = 0.0
					_state = State.IDLE
					_drag_line.visible = false
					_drag_line.clear_points()

		virus.position = _pos_at(_dist)

	# the dragged wire follows the mouse, even while the view is scrolling
	if _state == State.DRAGGING:
		_drag_line.set_point_position(1, _mouse_pos - world.position)

	_update_camera()


# the view usually shows on the current segment, but once the firewall catches up,it pushes the view along with it, so the player can't linger and so I don't need to make anything behind the firewall #lazy
func _camera_x() -> float:
	return maxf(cam_base, firewall.position.x + firewall_width - firewall_visible_width)


func _update_camera() -> void:
	var cam := _camera_x()
	world.position.x = -cam

	# glow on the left edge: grows as the firewall approaches the view 
	# glow settings can be tweaked with: glow_color, glow_width, glow_range and glow_strength in inspector
	var fw_right := firewall.position.x + firewall_width
	var d := cam - fw_right
	var a := clampf(1.0 - d / glow_range, 0.0, 1.0) * glow_strength
	a *= 0.88 + 0.12 * sin(Time.get_ticks_msec() * 0.012)
	_glow.modulate.a = a


func _pos_at(d: float) -> Vector2:
	d = clampf(d, 0.0, _cum[_cum.size() - 1])

	for i in range(1, _points.size()):
		if d <= _cum[i]:
			var seg := _cum[i] - _cum[i - 1]
			var t := 0.0 if seg == 0.0 else (d - _cum[i - 1]) / seg
			return _points[i - 1].lerp(_points[i], t)

	return _points[_points.size() - 1]


func _on_route_end() -> void:
	if _route["result"] == "arrived":
		_arrive(_route["target"])
	else:
		_state = State.FIZZLE
		_timer = fizzle_time
		fizzled.emit()


# ---------- arriving at a server ----------

func _arrive(server: Vector2i) -> void:
	_current_server = server
	var is_last := servers.find(server) == servers.size() - 1
	_state = State.DONE if is_last else State.PANNING

	_drag_line.visible = false
	_drag_line.clear_points()

	server_reached.emit(servers.find(server))

	# start the pan from wherever the view is right now
	cam_base = _camera_x()
	_pan_tween = create_tween()
	_pan_tween.tween_property(self, "cam_base", _cam_target(server), pan_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _pan_tween.finished

	_points.clear()
	_cum.clear()
	virus.position = _server_centers[server]

	if is_last:
		_show_win()
		finished.emit()
	else:
		_find_source_plug()
		_state = State.IDLE


func _cam_target(server: Vector2i) -> float:
	return _server_centers[server].x - pan_margin


# ---------- getting caught ----------

func _on_firewall_caught() -> void:
	if not firewall_active:
		return

	firewall_caught.emit()

	lives -= 1
	lives_changed.emit(lives)
	_update_hearts(true)

	# stop the current route
	_points.clear()
	_cum.clear()
	_route.clear()
	_dist = 0.0

	_drag_line.visible = false
	_drag_line.clear_points()

	if lives <= 0:
		firewall_active = false
		_state = State.DONE
		game_over.emit()
		_show_game_over()
		return

	# back to the last server, firewall pushed back
	virus.position = _server_centers[_current_server]
	firewall.position.x = _server_centers[_current_server].x - firewall_start_gap
	_state = State.IDLE


# ---------- debug: red ticks on the tiles ----------

func _draw_debug() -> void:
	for cell in wires.get_used_cells():
		if _kind(cell) == "server":
			continue

		var center := wires.map_to_local(cell)

		for d in _open_dirs(cell):
			_debug.draw_line(center, center + Vector2(d) * 7.0, Color.RED, 2.0)
