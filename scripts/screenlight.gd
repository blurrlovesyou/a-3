extends OmniLight3D

@export var sub_viewport: SubViewport
@export var color_blend_speed: float = 5.0

var target_color: Color = Color.BLACK
#find average color of screen and make that the oclor of the lightsource dynamically
func _process(delta):
	var texture = sub_viewport.get_texture()
	var image = texture.get_image()
	if image and not image.is_empty():
		var width = image.get_width()
		var height = image.get_height()
		var total_r: float = 0.0
		var total_g: float = 0.0
		var total_b: float = 0.0
		var sample_count: int = 0
		
		var steps = 4
		for x in range(steps):
			for y in range(steps):
				var px = int((width / float(steps)) * x + (width / float(steps * 2)))
				var py = int((height / float(steps)) * y + (height / float(steps * 2)))
				
				var col = image.get_pixel(px, py)
				total_r += col.r
				total_g += col.g
				total_b += col.b
				sample_count += 1
		
		if sample_count > 0:
			target_color = Color(
				total_r / sample_count,
				total_g / sample_count,
				total_b / sample_count
			)
		
		light_color = light_color.lerp(target_color, color_blend_speed * delta)
