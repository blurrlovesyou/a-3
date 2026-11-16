extends CanvasLayer

@export var dot_size := 5
@export var dot_color := Color.WHITE

var _crosshair: Control

func _ready() -> void:
	layer = 100 #so its above eveything
	#centered cross shown when player is not behind computer
	_crosshair = Control.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_dot)
	add_child(_crosshair)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	#same cross cursor replaces system cursor
	var tex: ImageTexture = _make_dot_texture()
	var hotspot: Vector2 = tex.get_size() / 2.0
	for shape in range(17): #for every cursor shape, so it never turns back into an arrow
		Input.set_custom_mouse_cursor(tex, shape as Input.CursorShape, hotspot)

func _process(_delta: float) -> void:
	_crosshair.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

#canvas layer item
func _draw_dot() -> void:
	var half: float = dot_size / 2.5
	var thickness: float = max(1.0, floor(dot_size / 3.0))
	var t_half: float = thickness / 2.0
	#draw cross cursor
	_crosshair.draw_rect(Rect2(-dot_size / 2.0, -t_half, dot_size, thickness), dot_color)
	_crosshair.draw_rect(Rect2(-t_half, -dot_size / 2.0, thickness, dot_size), dot_color)

#system needs image, so it turns the same cross cursor into an image
func _make_dot_texture() -> ImageTexture:
	var s: int = dot_size + 2
	var img: Image = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	
	var center: int = s / 2
	var thickness: int = max(1, int(dot_size / 3))
	var t_half: int = thickness / 2
	
	for x in s:
		for y in s:
			var is_horizontal: bool = (y >= center - t_half and y < center - t_half + thickness and abs(x - center) <= dot_size / 2)
			var is_vertical: bool = (x >= center - t_half and x < center - t_half + thickness and abs(y - center) <= dot_size / 2)
			
			if is_horizontal or is_vertical:
				img.set_pixel(x, y, dot_color)
				
	return ImageTexture.create_from_image(img)
