class_name ScreenInput
extends MeshInstance3D

const MISS := Vector2(-1, -1)

@export var sub_viewport: SubViewport
@export var screen_area: Area3D
@export_flags_3d_physics var screen_layer := 1 << 19 #layer 20
@export var cursor_scale := 1.5

var active := false
var _hovering := false
var _last_pos := Vector2.ZERO
var _cursor: Node2D
var _verts: PackedVector3Array
var _uvs: PackedVector2Array
var _indices: PackedInt32Array

func _ready() -> void:
	#building cursor texture
	var arrays := mesh.surface_get_arrays(0)
	_verts = arrays[Mesh.ARRAY_VERTEX]
	_uvs = arrays[Mesh.ARRAY_TEX_UV]
	_indices = arrays[Mesh.ARRAY_INDEX]

	#cursor shape
	var pts := PackedVector2Array([
		Vector2(0, 0), Vector2(0, 16), Vector2(4, 12.5), Vector2(7, 19),
		Vector2(9.5, 18), Vector2(6.5, 11.5), Vector2(11.5, 11.5)])

	var fill := Polygon2D.new()
	fill.polygon = pts

	var outline := Line2D.new()
	outline.points = pts
	outline.closed = true
	outline.width = 1.5
	outline.default_color = Color.BLACK

	_cursor = Node2D.new()
	_cursor.scale = Vector2.ONE * cursor_scale
	_cursor.visible = false
	_cursor.add_child(fill)
	_cursor.add_child(outline)

	#add to subviewport
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	canvas.add_child(_cursor)
	sub_viewport.add_child(canvas)

func set_active(value: bool) -> void:
	active = value
	if not value:
		_set_hover(false)

func _set_hover(on: bool) -> void:
	if on == _hovering:
		return
	_hovering = on
	_cursor.visible = on
	if active:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if on else Input.MOUSE_MODE_VISIBLE
	if not on:
		#push the fake mouse offscreen so hovered buttons unhover
		var m := InputEventMouseMotion.new()
		m.position = Vector2(-10000, -10000)
		sub_viewport.push_input(m, true)

func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey:
		sub_viewport.push_input(event)
	elif event is InputEventMouse:
		var p := _pick(event.position)
		_set_hover(p != MISS)
		if p == MISS:
			return
		_cursor.position = p
		var e := event.duplicate() as InputEventMouse
		e.position = p
		e.global_position = p
		if e is InputEventMouseMotion:
			(e as InputEventMouseMotion).relative = p - _last_pos
		_last_pos = p
		sub_viewport.push_input(e, true)

#mouse position in the main window to pixel position in the SubViewport (or MISS)
func _pick(mouse_pos: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	var from := cam.project_ray_origin(mouse_pos)
	var to := from + cam.project_ray_normal(mouse_pos) * 10.0
	var query := PhysicsRayQueryParameters3D.create(from, to, screen_layer)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return MISS

	var local: Vector3 = global_transform.affine_inverse() * hit["position"]
	for i in range(0, _indices.size(), 3):
		var ia := _indices[i]
		var ib := _indices[i + 1]
		var ic := _indices[i + 2]
		var w := _barycentric(local, _verts[ia], _verts[ib], _verts[ic])
		if w.x >= -0.001 and w.y >= -0.001 and w.z >= -0.001:
			return (_uvs[ia] * w.x + _uvs[ib] * w.y + _uvs[ic] * w.z) * Vector2(sub_viewport.size)
	return MISS

#helper func
func _barycentric(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var denom := d00 * d11 - d01 * d01
	var v := (d11 * d20 - d01 * d21) / denom
	var w := (d00 * d21 - d01 * d20) / denom
	return Vector3(1.0 - v - w, v, w)
