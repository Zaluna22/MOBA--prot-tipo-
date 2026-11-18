extends Node2D
## Short-lived visual effects: shots, rings, novas, floating text.

var items: Array = []


func add_shot(a: Vector2, b: Vector2, c: Color, ranged: bool) -> void:
	items.append({"type": "shot", "a": a, "b": b, "c": c, "t": 0.0, "dur": 0.14 if ranged else 0.08, "ranged": ranged})


func add_ring(p: Vector2, r: float, c: Color, dur: float) -> void:
	items.append({"type": "ring", "p": p, "r": r, "c": c, "t": 0.0, "dur": dur})


func add_nova(p: Vector2, r: float, c: Color) -> void:
	items.append({"type": "nova", "p": p, "r": r, "c": c, "t": 0.0, "dur": 0.4})


func add_text(p: Vector2, text: String, c: Color) -> void:
	items.append({"type": "text", "p": p, "text": text, "c": c, "t": 0.0, "dur": 1.2})


func _process(delta: float) -> void:
	var keep: Array = []
	for it in items:
		it["t"] += delta
		if it["t"] < it["dur"]:
			keep.append(it)
	items = keep
	queue_redraw()


func _draw() -> void:
	for it in items:
		var k: float = it["t"] / it["dur"]
		var c: Color = it["c"]
		match it["type"]:
			"shot":
				var a: Vector2 = it["a"]
				var b: Vector2 = it["b"]
				if it["ranged"]:
					var p := a.lerp(b, k)
					draw_line(a.lerp(b, max(0.0, k - 0.35)), p, Color(c, 0.6), 2.0)
					draw_circle(p, 4.0, c)
				else:
					draw_line(a, b, Color(c, 1.0 - k), 3.0)
			"ring":
				draw_arc(it["p"], it["r"] * (1.0 + k * 0.3), 0, TAU, 32, Color(c, 1.0 - k), 3.0)
			"nova":
				draw_circle(it["p"], it["r"] * k, Color(c, 0.3 * (1.0 - k)))
				draw_arc(it["p"], it["r"] * k, 0, TAU, 48, Color(c, 1.0 - k * 0.5), 5.0)
			"text":
				var pos: Vector2 = it["p"] + Vector2(-60, -40 - 40 * k)
				draw_string(ThemeDB.fallback_font, pos, it["text"], HORIZONTAL_ALIGNMENT_CENTER, 120, 20, Color(c, 1.0 - k))
