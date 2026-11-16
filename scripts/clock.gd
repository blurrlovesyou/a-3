extends Label

const FAKE_YEAR := 2034

func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_update)
	add_child(timer)
	_update()

func _update() -> void:
	var t := Time.get_datetime_dict_from_system()
	text = "%02d:%02d\n%02d/%02d/%d" % [t.hour, t.minute, t.day, t.month, FAKE_YEAR]
