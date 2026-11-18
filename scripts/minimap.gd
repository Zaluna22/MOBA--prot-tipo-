extends Control
## Strip minimap of the single lane.

var main


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if main == null:
		return
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(0, h * 0.3, w, h * 0.4), Color(0.55, 0.45, 0.3, 0.9))
	draw_rect(Rect2(w * 0.5 - 4, 0, 8, h), Color(0.25, 0.5, 0.8, 0.9))
	for u in main.get_tree().get_nodes_in_group("units"):
		if u.dead:
			continue
		var p := Vector2(u.position.x / main.WORLD_W * w, u.position.y / main.WORLD_H * h)
		var c: Color = u.team_color()
		match u.kind:
			3, 4:
				draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), c.lightened(0.2))
			0:
				draw_circle(p, 5.0, Color.WHITE if u.is_player else Color.BLACK)
				draw_circle(p, 3.5, c)
			_:
				draw_circle(p, 2.0, c)
	# camera view
	var vr: Rect2 = main.camera_rect()
	draw_rect(Rect2(vr.position.x / main.WORLD_W * w, 1, vr.size.x / main.WORLD_W * w, h - 2), Color(1, 1, 1, 0.7), false, 1.5)
