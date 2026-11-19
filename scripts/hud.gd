extends CanvasLayer
## Mobile HUD: floating joystick, attack + 4 skill buttons, bars, minimap, end/rotate screens.

const Unit := preload("res://scripts/unit3d.gd")
const SKILL_NAMES := ["NOVA", "SALTO", "FÚRIA", "METEORO"]
const SKILL_KEYS := ["1", "2", "3", "4"]
const SKILL_COLORS := [Color(0.35, 0.7, 1.0), Color(0.55, 1.0, 0.75), Color(1.0, 0.75, 0.25), Color(1.0, 0.45, 0.3)]

var game
var ui: Control
var font: Font
var joy_finger := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var key_dir := Vector2.ZERO
var end_visible := false
var end_won := false
var help_time := 10.0
var pressed_flash := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.draw.connect(_draw_ui)
	add_child(ui)


func vs() -> Vector2:
	return get_viewport().get_visible_rect().size


func is_portrait() -> bool:
	var s := vs()
	return s.y > s.x * 1.05


# ---------------------------------------------------------------- layout
func atk_center() -> Vector2:
	var s := vs()
	return Vector2(s.x - 135, s.y - 125)


func skill_center(i: int) -> Vector2:
	var ang := deg_to_rad(180.0 + 30.0 * i)
	return atk_center() + Vector2(cos(ang), sin(ang)) * 195.0


func upgrade_rect() -> Rect2:
	return Rect2(vs().x - 200, 64, 186, 52)


func restart_rect() -> Rect2:
	var s := vs()
	return Rect2(s.x / 2 - 170, s.y / 2 + 30, 340, 84)


# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			handle_press(event.index, p)
		elif event.index == joy_finger:
			joy_finger = -1
			game.player.move_input = Vector2.ZERO
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == joy_finger:
			joy_pos = event.position
			update_joy()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and not event.echo:
		var k: int = event.keycode
		var dirs := {KEY_W: Vector2(0, -1), KEY_UP: Vector2(0, -1), KEY_S: Vector2(0, 1), KEY_DOWN: Vector2(0, 1),
			KEY_A: Vector2(-1, 0), KEY_LEFT: Vector2(-1, 0), KEY_D: Vector2(1, 0), KEY_RIGHT: Vector2(1, 0)}
		if dirs.has(k):
			key_dir += dirs[k] if event.pressed else -dirs[k]
			key_dir = key_dir.clamp(Vector2(-1, -1), Vector2(1, 1))
			if joy_finger == -1:
				game.player.move_input = key_dir.normalized() if key_dir.length() > 0.1 else Vector2.ZERO
		elif event.pressed:
			match k:
				KEY_1, KEY_Q: press_skill(0)
				KEY_2, KEY_E: press_skill(1)
				KEY_3, KEY_R: press_skill(2)
				KEY_4, KEY_F: press_skill(3)
				KEY_SPACE: press_attack()
				KEY_B, KEY_G: game.buy_upgrade(game.player)


func handle_press(idx: int, p: Vector2) -> void:
	if is_portrait():
		return
	if end_visible:
		if restart_rect().grow(20).has_point(p):
			game.restart()
		return
	help_time = min(help_time, 1.0)
	if p.distance_to(atk_center()) < 92:
		press_attack()
		return
	for i in 4:
		if p.distance_to(skill_center(i)) < 60:
			press_skill(i)
			return
	if upgrade_rect().grow(10).has_point(p):
		game.buy_upgrade(game.player)
		pressed_flash["up"] = 0.15
		return
	if p.x < vs().x * 0.5 and joy_finger == -1:
		joy_finger = idx
		joy_origin = p
		joy_pos = p
		update_joy()


func update_joy() -> void:
	var d := joy_pos - joy_origin
	if d.length() > 95:
		joy_origin = joy_pos - d.normalized() * 95
		d = joy_pos - joy_origin
	var v := d / 95.0
	game.player.move_input = v if v.length() > 0.12 else Vector2.ZERO


func press_attack() -> void:
	game.player.attack_cmd = true
	pressed_flash["atk"] = 0.15


func press_skill(i: int) -> void:
	if game.game_over:
		return
	if game.player.cast(i):
		pressed_flash[i] = 0.15


func show_end(won: bool) -> void:
	end_visible = true
	end_won = won


# ---------------------------------------------------------------- draw
func _process(delta: float) -> void:
	if not get_tree().paused:
		help_time -= delta
	for k in pressed_flash.keys():
		pressed_flash[k] -= delta
		if pressed_flash[k] <= 0:
			pressed_flash.erase(k)
	ui.queue_redraw()


var text_q: Array = []


## Texts are queued and drawn together (all outlines, then all fills) so the
## renderer can batch them instead of breaking the batch for every label.
func text(pos: Vector2, s: String, size: int, c := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	text_q.append([pos, s, size, c, align, width])


func flush_text() -> void:
	text_q.sort_custom(func(a, b): return a[2] < b[2])
	for t in text_q:
		var c: Color = t[3]
		ui.draw_string_outline(font, t[0], t[1], t[4], t[5], t[2], max(4, t[2] / 4), Color(0, 0, 0, 0.85 * c.a))
	for t in text_q:
		ui.draw_string(font, t[0], t[1], t[4], t[5], t[2], t[3])
	text_q.clear()


func ctext(center: Vector2, s: String, size: int, c := Color.WHITE) -> void:
	var w := 1000.0
	text(center + Vector2(-w / 2, size * 0.35), s, size, c, HORIZONTAL_ALIGNMENT_CENTER, w)


func pie(center: Vector2, r: float, frac: float, c: Color) -> void:
	if frac <= 0.001:
		return
	var pts := PackedVector2Array([center])
	var n := 32
	for i in n + 1:
		var a := -PI / 2 + TAU * frac * i / n
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	ui.draw_colored_polygon(pts, c)


func _draw_ui() -> void:
	if game == null or game.player == null:
		return
	var s := vs()
	draw_world_bars()
	var p = game.player
	# --- top left: minimap (whole map, square)
	var mm := Rect2(14, 14, 168, 168)
	var k: float = mm.size.x / game.MAP
	ui.draw_rect(mm, Color(0.08, 0.2, 0.09, 0.85))
	ui.draw_line(mm.position, mm.end, Color(0.25, 0.5, 0.85, 0.9), 7.0)
	for l in game.lanes:
		var pts := PackedVector2Array()
		for q in l:
			pts.append(mm.position + q * k)
		ui.draw_polyline(pts, Color(0.62, 0.5, 0.33, 0.95), 5.0)
	for c in game.camps:
		if game.camp_alive(c):
			ui.draw_circle(mm.position + c["pos"] * k, 3.5, Color(1.0, 0.82, 0.3, 0.9))
	for u in game.units:
		if u.dead or u.team == 2:
			continue
		var q: Vector2 = mm.position + u.p2() * k
		var c: Color = u.team_color()
		match u.kind:
			Unit.Kind.TOWER, Unit.Kind.BASE:
				ui.draw_rect(Rect2(q - Vector2(4, 4), Vector2(8, 8)), c.lightened(0.2))
			Unit.Kind.HERO:
				pass
			_:
				ui.draw_rect(Rect2(q - Vector2(1.5, 1.5), Vector2(3, 3)), c)
	for h in game.heroes:
		if h.dead:
			continue
		var q: Vector2 = mm.position + h.p2() * k
		ui.draw_circle(q, 6.5 if h.is_player else 5.5, Color.WHITE if h.is_player else Color.BLACK)
		ui.draw_circle(q, 4.5, Color(0.45, 1.0, 0.45) if h.is_player else h.team_color())
	# camera view
	var cf: Vector3 = game.cam_focus
	ui.draw_rect(Rect2(mm.position + Vector2(cf.x - 16, cf.z - 10) * k, Vector2(32, 18) * k), Color(1, 1, 1, 0.6), false, 1.5)
	ui.draw_rect(mm, Color(1, 1, 1, 0.35), false, 2.0)
	# --- top center: score + time
	var mins := int(game.game_time) / 60
	var secs := int(game.game_time) % 60
	var tc := Vector2(s.x / 2, 34)
	ui.draw_rect(Rect2(tc.x - 120, 8, 240, 56), Color(0, 0, 0, 0.5))
	text(Vector2(tc.x - 112, 48), str(game.team_kills[0]), 34, Color(0.45, 0.75, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
	text(Vector2(tc.x - 60, 42), "%02d:%02d" % [mins, secs], 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 120)
	text(Vector2(tc.x + 40, 48), str(game.team_kills[1]), 34, Color(1.0, 0.45, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, 72)
	text(Vector2(tc.x - 60, 60), "onda em %ds" % int(ceil(game.wave_timer)), 14, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 120)
	# --- top right: gold + upgrade
	ui.draw_rect(Rect2(s.x - 200, 12, 186, 44), Color(0, 0, 0, 0.5))
	ui.draw_circle(Vector2(s.x - 176, 34), 11, Color(1.0, 0.8, 0.2))
	text(Vector2(s.x - 156, 44), "%d" % int(p.gold), 28, Color(1.0, 0.88, 0.35))
	var ur := upgrade_rect()
	var cost: int = game.upgrade_cost(p)
	var can: bool = p.gold >= cost
	ui.draw_rect(ur, Color(0.55, 0.38, 0.08, 0.9) if can else Color(0.2, 0.2, 0.2, 0.7))
	if pressed_flash.has("up"):
		ui.draw_rect(ur, Color(1, 1, 1, 0.3))
	ui.draw_rect(ur, Color(1, 0.85, 0.4, 0.8 if can else 0.3), false, 2.0)
	text(ur.position + Vector2(0, 34), "+FORÇA  %d" % cost, 22, Color(1, 1, 1, 1.0 if can else 0.5), HORIZONTAL_ALIGNMENT_CENTER, ur.size.x)
	# --- bottom center: player hp + xp
	var bw := minf(420.0, s.x * 0.34)
	var bx := s.x / 2 - bw / 2
	var by := s.y - 58
	ui.draw_rect(Rect2(bx - 4, by - 30, bw + 8, 62), Color(0, 0, 0, 0.55))
	text(Vector2(bx, by - 8), "%s  Nv %d" % [p.hero_name, p.level], 20, Color(1, 1, 1, 0.95))
	if p.buff_t > 0:
		text(Vector2(bx + bw - 120, by - 8), "FÚRIA %ds" % ceil(p.buff_t), 18, Color(1, 0.8, 0.3), HORIZONTAL_ALIGNMENT_RIGHT, 120)
	ui.draw_rect(Rect2(bx, by, bw, 16), Color(0.15, 0.05, 0.05))
	ui.draw_rect(Rect2(bx, by, bw * clamp(p.hp / p.max_hp, 0.0, 1.0), 16), Color(0.3, 0.85, 0.3))
	text(Vector2(bx, by + 14), "%d / %d" % [p.hp, p.max_hp], 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bw)
	ui.draw_rect(Rect2(bx, by + 20, bw, 7), Color(0.1, 0.1, 0.2))
	ui.draw_rect(Rect2(bx, by + 20, bw * clamp(p.xp / p.xp_to_next(), 0.0, 1.0), 7), Color(0.6, 0.45, 1.0))
	# --- joystick
	var jo := joy_origin if joy_finger != -1 else Vector2(170, s.y - 160)
	var jp := joy_pos if joy_finger != -1 else jo
	ui.draw_circle(jo, 95, Color(1, 1, 1, 0.08 if joy_finger == -1 else 0.14))
	ui.draw_arc(jo, 95, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	var d := (jp - jo).limit_length(95)
	ui.draw_circle(jo + d, 42, Color(1, 1, 1, 0.35 if joy_finger != -1 else 0.22))
	ui.draw_arc(jo + d, 42, 0, TAU, 32, Color(1, 1, 1, 0.6), 2.0)
	# --- attack button
	var ac := atk_center()
	ui.draw_circle(ac, 80, Color(0.15, 0.12, 0.1, 0.75))
	ui.draw_arc(ac, 80, 0, TAU, 48, Color(1, 0.85, 0.5, 0.85), 4.0)
	if pressed_flash.has("atk"):
		ui.draw_circle(ac, 80, Color(1, 1, 1, 0.25))
	# sword glyph
	var dg := Vector2(1, -1).normalized()
	ui.draw_line(ac - dg * 34, ac + dg * 38, Color(0.9, 0.95, 1.0), 8.0)
	ui.draw_line(ac - dg * 14 + dg.orthogonal() * 16, ac - dg * 14 - dg.orthogonal() * 16, Color(1, 0.8, 0.35), 7.0)
	ctext(ac + Vector2(0, 54), "ATACAR", 15, Color(1, 1, 1, 0.85))
	# --- skills
	for i in 4:
		var c := skill_center(i)
		var col: Color = SKILL_COLORS[i]
		var locked: bool = i == 3 and p.level < 3
		ui.draw_circle(c, 52, Color(0.08, 0.08, 0.12, 0.8))
		ui.draw_circle(c, 46, Color(col.darkened(0.35), 0.95 if not locked else 0.35))
		var cd: float = p.cds[i]
		if cd > 0 or locked:
			pie(c, 46, 1.0 if locked else cd / p.cd_max[i], Color(0, 0, 0, 0.6))
		ui.draw_arc(c, 52, 0, TAU, 40, Color(col, 0.9 if cd <= 0 and not locked else 0.35), 3.0)
		if pressed_flash.has(i):
			ui.draw_circle(c, 52, Color(1, 1, 1, 0.3))
		if locked:
			ctext(c + Vector2(0, -6), "Nv 3", 20, Color(1, 1, 1, 0.8))
		elif cd > 0:
			ctext(c + Vector2(0, -6), str(int(ceil(cd))), 30, Color.WHITE)
		else:
			ctext(c + Vector2(0, -6), SKILL_KEYS[i], 26, Color(1, 1, 1, 0.9))
		ctext(c + Vector2(0, 26), SKILL_NAMES[i], 13, Color(1, 1, 1, 0.95))
	# --- respawn
	if p.dead:
		ctext(Vector2(s.x / 2, s.y * 0.32), "Renascendo em %d" % ceil(p.respawn_timer), 44, Color.WHITE)
	# --- help
	if help_time > 0:
		var a: float = clamp(help_time, 0.0, 1.0)
		var hr := Rect2(s.x / 2 - 360, s.y * 0.62 - 50, 720, 96)
		ui.draw_rect(hr, Color(0, 0, 0, 0.55 * a))
		ctext(Vector2(s.x / 2, s.y * 0.62 - 22), "Joystick à esquerda para mover. ATACAR mira o inimigo mais perto.", 18, Color(1, 1, 1, a))
		ctext(Vector2(s.x / 2, s.y * 0.62 + 8), "Habilidades: NOVA, SALTO, FÚRIA e METEORO (Nv 3).", 18, Color(1, 1, 1, a))
		ctext(Vector2(s.x / 2, s.y * 0.62 + 34), "Selva: pontos amarelos dão ouro e XP. Destrua o castelo vermelho!", 18, Color(1, 0.85, 0.4, a))
	flush_text()
	# --- end screen
	if end_visible:
		ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.72))
		ctext(Vector2(s.x / 2, s.y / 2 - 70), "VITÓRIA!" if end_won else "DERROTA", 80, Color(0.5, 0.8, 1.0) if end_won else Color(1.0, 0.45, 0.4))
		var rr := restart_rect()
		ui.draw_rect(rr, Color(0.2, 0.35, 0.6, 0.95))
		ui.draw_rect(rr, Color(1, 1, 1, 0.8), false, 3.0)
		ctext(rr.get_center(), "Jogar de novo", 34, Color.WHITE)
	flush_text()
	# --- rotate
	if is_portrait():
		ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.06, 0.09, 0.97))
		ctext(Vector2(s.x / 2, s.y / 2 - 40), "Gire o celular", 44, Color.WHITE)
		ctext(Vector2(s.x / 2, s.y / 2 + 20), "para a horizontal", 44, Color.WHITE)
		ui.draw_arc(Vector2(s.x / 2, s.y / 2 + 120), 40, 0.3, TAU - 0.6, 32, Color.WHITE, 5.0)
	flush_text()


func draw_world_bars() -> void:
	var cam: Camera3D = game.cam
	var scr := Rect2(Vector2(-80, -40), vs() + Vector2(160, 80))
	var cf := Vector2(game.cam_focus.x, game.cam_focus.z)
	for u in game.units:
		if u.dead or not u.visible:
			continue
		if cf.distance_squared_to(u.p2()) > 900.0:
			continue
		var wp: Vector3 = u.position + Vector3(0, u.bar_height, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		if not scr.has_point(sp):
			continue
		var w := 36.0
		var h := 6.0
		match u.kind:
			Unit.Kind.HERO:
				w = 76.0; h = 10.0
			Unit.Kind.TOWER:
				w = 90.0; h = 9.0
			Unit.Kind.BASE:
				w = 130.0; h = 11.0
		var r := Rect2(sp.x - w / 2, sp.y - h / 2, w, h)
		ui.draw_rect(r.grow(2), Color(0, 0, 0, 0.8))
		var c: Color = [Color(0.3, 0.6, 1.0), Color(0.95, 0.25, 0.2), Color(1.0, 0.8, 0.25)][u.team]
		if u.is_player:
			c = Color(0.4, 0.95, 0.35)
		ui.draw_rect(Rect2(r.position, Vector2(w * clamp(u.hp / u.max_hp, 0.0, 1.0), h)), c)
		if u.kind == Unit.Kind.HERO:
			# segment ticks every 200 hp
			var ticks := int(u.max_hp / 200.0)
			for t in ticks:
				var x: float = r.position.x + w * (t + 1) * 200.0 / u.max_hp
				ui.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.6), 1.0)
			ui.draw_rect(Rect2(r.position.x - 26, r.position.y - 6, 22, 22), Color(0.1, 0.1, 0.15, 0.95))
			text(Vector2(r.position.x - 26, r.position.y + 11), str(u.level), 16, Color(1, 0.9, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 22)
		if u.invulnerable:
			ui.draw_rect(r.grow(2), Color(1, 1, 1, 0.8), false, 2.0)
			ctext(sp + Vector2(0, -16), "protegida", 13, Color(1, 1, 1, 0.75))
	for t in game.hud_texts:
		var k: float = t["t"] / t["dur"]
		var wp2: Vector3 = t["p"] + Vector3(0, 2.6 + k * 1.5, 0)
		if cam.is_position_behind(wp2):
			continue
		var sp2 := cam.unproject_position(wp2)
		var c2: Color = t["c"]
		ctext(sp2, t["text"], 22, Color(c2, 1.0 - k))
