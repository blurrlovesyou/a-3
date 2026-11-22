extends Node

func _ready() -> void:
	CameraServer.set("monitoring_feeds", true)
	await get_tree().create_timer(2.0).timeout
	var feeds := CameraServer.feeds()
	print("camera feeds found: ", feeds.size())
	for f in feeds:
		print("  ", f.get_id(), " ", f.get_name())
