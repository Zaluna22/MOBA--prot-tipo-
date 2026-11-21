extends CanvasLayer
## Mobile HUD: floating joystick, attack + 4 skill buttons, bars, minimap, end/rotate screens.

const Unit := preload("res://scripts/unit3d.gd")
const Items := preload("res://scripts/items.gd")
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
var portraits := {}
var skill_icons := {}
var forca_icon: Texture2D
var passive_icon: Texture2D
var splash_tex: Texture2D
const KIT_KEYS := ["elfo", "elfa", "cavaleiro", "orc", "orca", "barbaro", "acougueiro"]
var aim_finger := -1
var aim_skill := -1
var aim_vec := Vector2.ZERO
const AIM_DEAD := 26.0
var shop_open := false
var shop_msg := ""
var shop_msg_t := 0.0
var sell_mode := false
const SHOP_COLS := 4


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ui.draw.connect(_draw_ui)
	add_child(ui)
	for k in KIT_KEYS:
		portraits[k] = load("res://assets/ui/p_%s.webp" % k)
		var arr := []
		for i in 4:
			arr.append(load("res://assets/ui/sk_%s_%d.webp" % [k, i]))
		skill_icons[k] = arr
	forca_icon = load("res://assets/ui/sk_forca.webp")
	passive_icon = load("res://assets/ui/sk_acougueiro_p.webp")
	splash_tex = load("res://assets/ui/splash.webp")


## Texture clipped to a circle (polygon with UVs).
func tex_circle(c: Vector2, r: float, tex: Texture2D, mod := Color.WHITE, zoom := 1.0) -> void:
	if tex == null:
		return
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for j in 32:
		var a := TAU * j / 32.0
		var d := Vector2(cos(a), sin(a))
		pts.append(c + d * r)
		uvs.append(Vector2(0.5, 0.5) + d * 0.5 / zoom)
	ui.draw_colored_polygon(pts, mod, uvs, tex)


func hero_portrait(h, c: Vector2, r: float, ring: Color) -> void:
	ui.draw_circle(c, r + 3, Color(0, 0, 0, 0.8))
	tex_circle(c, r, portraits.get(h.kit), Color(0.35, 0.35, 0.35) if h.dead else Color.WHITE)
	ui.draw_arc(c, r + 1.5, 0, TAU, 32, ring, 2.5)


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


# ---- loja layout
func slot_rect(i: int) -> Rect2:
	var s := vs()
	var w := 50.0
	var gap := 6.0
	var x0 := s.x / 2 - (w * Items.SLOTS + gap * (Items.SLOTS - 1)) / 2
	return Rect2(x0 + i * (w + gap), s.y - 58 - 30 - w - 10, w, w)


func shop_rect() -> Rect2:
	var s := vs()
	var w := minf(820.0, s.x - 120.0)
	var h := minf(470.0, s.y - 150.0)
	return Rect2(s.x / 2 - w / 2, 72, w, h)


func shop_tile(i: int) -> Rect2:
	var r := shop_rect()
	var pad := 14.0
	var rows := int(ceil(Items.ORDER.size() / float(SHOP_COLS)))
	var tw := (r.size.x - pad * (SHOP_COLS + 1)) / SHOP_COLS
	var th := minf(92.0, (r.size.y - 60 - 76 - pad * (rows + 1)) / rows)
	return Rect2(r.position.x + pad + (i % SHOP_COLS) * (tw + pad), r.position.y + 56 + pad + (i / SHOP_COLS) * (th + pad), tw, th)


func shop_slot(i: int) -> Rect2:
	var r := shop_rect()
	var w := 54.0
	return Rect2(r.position.x + 20 + i * (w + 10), r.end.y - w - 16, w, w)


func sell_rect() -> Rect2:
	var r := shop_rect()
	return Rect2(r.end.x - 300, r.end.y - 66, 130, 50)


func close_rect() -> Rect2:
	var r := shop_rect()
	return Rect2(r.end.x - 156, r.end.y - 66, 140, 50)


func toggle_shop() -> void:
	shop_open = not shop_open
	sell_mode = false


const PICK := [["elfo", "Mago arcano", "Dano em área e teleporte"], ["elfa", "Caçadora", "Ataque de longe e flecha que atravessa"],
	["cavaleiro", "Guardião", "Atordoa, aguenta e cura o time"], ["orc", "Brutamontes", "Terremoto, roubo de vida e esmagar"],
	["orca", "Xamã", "Raio em cadeia, cura e tempestade"], ["barbaro", "Guerreiro", "Redemoinho, fúria e machado gigante"],
	["acougueiro", "Tanque caçador", "Gancho puxa inimigo ou aliado"]]


func pick_rect(i: int) -> Rect2:
	var s := vs()
	var w: float = min(290.0, (s.x - 90.0) / 4.0)
	var hh: float = min(200.0, (s.y - 170.0) / 2.0)
	var row := i / 4
	var in_row: int = 4 if row == 0 else PICK.size() - 4
	var x0 := s.x / 2 - (w * in_row + 20 * (in_row - 1)) / 2
	return Rect2(x0 + (i % 4) * (w + 20), 110 + row * (hh + 20), w, hh)


func change_rect() -> Rect2:
	var r := restart_rect()
	return Rect2(r.position.x + 40, r.end.y + 22, r.size.x - 80, 58)


func restart_rect() -> Rect2:
	var s := vs()
	return Rect2(s.x / 2 - 170, s.y / 2 + 30, 340, 84)


# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if not is_inside_tree() or game == null or game.reloading:
		return
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			handle_press(event.index, p)
		elif event.index == joy_finger:
			joy_finger = -1
			game.player.move_input = Vector2.ZERO
		elif event.index == aim_finger:
			release_aim()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == joy_finger:
			joy_pos = event.position
			update_joy()
		elif event.index == aim_finger:
			aim_vec = event.position - skill_center(aim_skill)
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
				KEY_B, KEY_G: toggle_shop()
				KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0:
					var si: int = 5 if k == KEY_0 else k - KEY_5
					Items.use(game, game.player, si)
				KEY_ESCAPE:
					shop_open = false


func handle_press(idx: int, p: Vector2) -> void:
	if is_portrait():
		return
	if game.picking:
		for i in PICK.size():
			if pick_rect(i).has_point(p):
				game.pick_hero(PICK[i][0])
				return
		return
	if end_visible:
		if restart_rect().grow(20).has_point(p):
			game.restart()
			return
		elif change_rect().grow(14).has_point(p):
			game.change_hero()
		return
	help_time = min(help_time, 1.0)
	if shop_open and shop_press(p):
		return
	for i in Items.SLOTS:
		if slot_rect(i).grow(4).has_point(p):
			if Items.use(game, game.player, i):
				pressed_flash["slot%d" % i] = 0.15
			return
	if p.distance_to(atk_center()) < 92:
		press_attack()
		return
	for i in 4:
		if p.distance_to(skill_center(i)) < 60:
			var pl = game.player
			if Unit.AIMED[pl.kit][i] and pl.cds[i] <= 0 and not (i == 3 and pl.level < 3) and aim_finger == -1:
				aim_finger = idx
				aim_skill = i
				aim_vec = Vector2.ZERO
			else:
				press_skill(i)
			return
	if upgrade_rect().grow(10).has_point(p):
		toggle_shop()
		pressed_flash["up"] = 0.15
		return
	if p.x < vs().x * 0.5 and joy_finger == -1:
		joy_finger = idx
		joy_origin = p
		joy_pos = p
		update_joy()


## Touch inside the open shop panel. Returns true when the press was used by it.
func shop_press(p: Vector2) -> bool:
	var pl = game.player
	if not shop_rect().has_point(p):
		return false
	if close_rect().has_point(p):
		shop_open = false
		return true
	if sell_rect().has_point(p):
		sell_mode = not sell_mode
		return true
	for i in Items.SLOTS:
		if shop_slot(i).has_point(p):
			if sell_mode and Items.sell(game, pl, i):
				sell_mode = false
			return true
	for i in Items.ORDER.size():
		if shop_tile(i).has_point(p):
			var why: String = Items.buy_block(game, pl, Items.ORDER[i])
			if Items.buy(game, pl, Items.ORDER[i]):
				pressed_flash["shop%d" % i] = 0.15
				shop_msg = "Comprou %s!" % Items.ITEMS[Items.ORDER[i]]["name"]
			else:
				shop_msg = {"ouro": "Ouro insuficiente", "volte à base": "Volte à base (fonte) para comprar", "já tem": "Você já tem esse item",
					"máx": "Máximo atingido", "cheio": "Inventário cheio: venda um item", "morto": "Espere renascer"}.get(why, why)
			shop_msg_t = 2.0
			return true
	return true


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


func release_aim() -> void:
	var i := aim_skill
	aim_finger = -1
	aim_skill = -1
	if i < 0:
		return
	if aim_vec.length() > AIM_DEAD:
		game.player.aim_override = aim_vec.normalized()
	press_skill(i)


## Tap without dragging: the butcher aims at the closest enemy hero in reach.
func auto_aim(i: int) -> void:
	var pl = game.player
	if pl.kit != "acougueiro" or pl.aim_override.length() > 0.01 or pl.move_input.length() > 0.15:
		return
	var h = game.nearest_enemy_hero(pl, pl.skill_range(i) + 0.5)
	if h != null:
		pl.aim_override = (h.p2() - pl.p2()).normalized()


func press_skill(i: int) -> void:
	if game.game_over:
		return
	auto_aim(i)
	if game.player.cast(i):
		pressed_flash[i] = 0.15


func show_end(won: bool) -> void:
	end_visible = true
	end_won = won


# ---------------------------------------------------------------- draw
func _process(delta: float) -> void:
	if not get_tree().paused:
		help_time -= delta
	shop_msg_t = maxf(0.0, shop_msg_t - delta)
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


var river_mm := PackedVector2Array()


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
	if river_mm.is_empty():
		var u := -100.0
		while u <= 100.0:
			var q: Vector2 = game.river_point(u)
			if q.x > -2 and q.y > -2 and q.x < game.MAP + 2 and q.y < game.MAP + 2:
				river_mm.append(q)
			u += 4.0
	var rp := PackedVector2Array()
	for q in river_mm:
		rp.append(mm.position + Vector2(clamp(q.x, 0, game.MAP), clamp(q.y, 0, game.MAP)) * k)
	ui.draw_polyline(rp, Color(0.25, 0.5, 0.85, 0.9), 7.0)
	for l in game.lanes:
		var pts := PackedVector2Array()
		for q in l:
			pts.append(mm.position + q * k)
		ui.draw_polyline(pts, Color(0.62, 0.5, 0.33, 0.95), 5.0)
	for c in game.camps:
		if game.camp_alive(c):
			ui.draw_circle(mm.position + c["pos"] * k, 3.5, Color(1.0, 0.82, 0.3, 0.9))
	for w in game.wards:
		if w["team"] == game.player.team:
			ui.draw_circle(mm.position + w["pos"] * k, game.WARD_R * k, Color(1.0, 0.9, 0.3, 0.18))
			ui.draw_circle(mm.position + w["pos"] * k, 3.0, Color(1.0, 0.9, 0.3, 0.95))
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
		if h.dead or (h.concealed and h.team != game.player.team):
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
	var ai := 0
	var ei := 0
	for h in game.heroes:
		var left: bool = h.team == 0
		var idx: int = ai if left else ei
		var pc := Vector2(tc.x + (-148 - idx * 44 if left else 148 + idx * 44), 32)
		hero_portrait(h, pc, 19, Color(0.45, 1.0, 0.45) if h.is_player else h.team_color())
		if h.dead:
			ctext(pc + Vector2(0, -2), str(int(ceil(h.respawn_timer))), 18, Color.WHITE)
		if left:
			ai += 1
		else:
			ei += 1
	# --- top right: gold + upgrade
	ui.draw_rect(Rect2(s.x - 200, 12, 186, 44), Color(0, 0, 0, 0.5))
	ui.draw_circle(Vector2(s.x - 176, 34), 11, Color(1.0, 0.8, 0.2))
	text(Vector2(s.x - 156, 44), "%d" % int(p.gold), 28, Color(1.0, 0.88, 0.35))
	var ur := upgrade_rect()
	var at_shop: bool = Items.near_shop(game, p)
	ui.draw_rect(ur, Color(0.55, 0.38, 0.08, 0.9) if at_shop or shop_open else Color(0.25, 0.2, 0.12, 0.8))
	if pressed_flash.has("up"):
		ui.draw_rect(ur, Color(1, 1, 1, 0.3))
	ui.draw_rect(ur, Color(1, 0.85, 0.4, 0.9 if at_shop else 0.45), false, 2.0)
	ui.draw_texture_rect(forca_icon, Rect2(ur.position + Vector2(4, 4), Vector2(44, 44)), false)
	text(ur.position + Vector2(40, 34), "LOJA", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, ur.size.x - 40)
	if at_shop and not shop_open and int(game.game_time * 2.0) % 2 == 0:
		ui.draw_rect(ur.grow(3), Color(1, 0.9, 0.4, 0.7), false, 2.0)
	draw_item_slots(p)
	# --- bottom center: player hp + xp
	var bw := minf(420.0, s.x * 0.34)
	var bx := s.x / 2 - bw / 2
	var by := s.y - 58
	ui.draw_rect(Rect2(bx - 4, by - 30, bw + 8, 62), Color(0, 0, 0, 0.55))
	hero_portrait(p, Vector2(bx - 52, by - 2), 42, p.kit_color())
	ctext(Vector2(bx - 52, by + 36), str(p.level), 18, Color(1, 0.9, 0.5))
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
	if aim_skill >= 0:
		draw_aim(p)
	for i in 4:
		var c := skill_center(i)
		var col: Color = SKILL_COLORS[i] if i != 0 else p.kit_color()
		var locked: bool = i == 3 and p.level < 3
		ui.draw_circle(c, 52, Color(0.08, 0.08, 0.12, 0.8))
		ui.draw_circle(c, 46, Color(col.darkened(0.35), 0.95 if not locked else 0.35))
		var cd: float = p.cds[i]
		var ready_ic: bool = cd <= 0 and not locked
		tex_circle(c, 46, skill_icons[p.kit][i], Color.WHITE if ready_ic else Color(0.55, 0.55, 0.55, 0.9))
		if cd > 0 or locked:
			pie(c, 46, 1.0 if locked else cd / p.cd_max[i], Color(0, 0, 0, 0.6))
		ui.draw_arc(c, 52, 0, TAU, 40, Color(col, 0.9 if cd <= 0 and not locked else 0.35), 3.0)
		if pressed_flash.has(i):
			ui.draw_circle(c, 52, Color(1, 1, 1, 0.3))
		if i == 1 and p.rot_on:
			ui.draw_arc(c, 56, 0, TAU, 40, Color(0.5, 1.0, 0.25, 0.95), 5.0)
			ui.draw_circle(c, 46, Color(0.4, 0.9, 0.2, 0.18))
		if locked:
			ctext(c + Vector2(0, -6), "Nv 3", 20, Color(1, 1, 1, 0.8))
		elif cd > 0:
			ctext(c + Vector2(0, -6), str(int(ceil(cd))), 30, Color.WHITE)
		ui.draw_rect(Rect2(c.x - 46, c.y + 14, 92, 20), Color(0, 0, 0, 0.55))
		ctext(c + Vector2(0, 26), p.skill_names()[i], 13 if p.skill_names()[i].length() < 11 else (11 if p.skill_names()[i].length() < 14 else 9), Color(1, 1, 1, 0.95))
	# --- passive: Pilha de Carne stacks
	if p.kit == "acougueiro":
		var pc := skill_center(0) + Vector2(-96, -42)
		ui.draw_circle(pc, 31, Color(0.08, 0.08, 0.12, 0.85))
		tex_circle(pc, 27, passive_icon)
		ui.draw_arc(pc, 30, 0, TAU, 32, Color(1.0, 0.65, 0.35, 0.9), 2.5)
		ui.draw_circle(pc + Vector2(22, -20), 14, Color(0.75, 0.2, 0.15, 0.95))
		ctext(pc + Vector2(22, -21), str(p.flesh), 17, Color.WHITE)
		ctext(pc + Vector2(0, 44), "PILHA DE", 11, Color(1, 0.85, 0.6))
		ctext(pc + Vector2(0, 57), "CARNE", 11, Color(1, 0.85, 0.6))
	# --- respawn
	if p.dead:
		ctext(Vector2(s.x / 2, s.y * 0.32), "Renascendo em %d" % ceil(p.respawn_timer), 44, Color.WHITE)
	# --- help
	if help_time > 0:
		var a: float = clamp(help_time, 0.0, 1.0)
		var hr := Rect2(s.x / 2 - 360, s.y * 0.62 - 50, 720, 96)
		ui.draw_rect(hr, Color(0, 0, 0, 0.55 * a))
		ctext(Vector2(s.x / 2, s.y * 0.62 - 22), "Joystick à esquerda para mover. ATACAR mira o inimigo mais perto.", 18, Color(1, 1, 1, a))
		ctext(Vector2(s.x / 2, s.y * 0.62 + 8), "%s: %s (a última no Nv 3)." % [p.hero_name, ", ".join(p.skill_names())], 18, Color(1, 1, 1, a))
		ctext(Vector2(s.x / 2, s.y * 0.62 + 34), "Selva: pontos amarelos dão ouro e XP. Destrua o castelo vermelho!", 18, Color(1, 0.85, 0.4, a))
	if shop_open and not end_visible:
		draw_shop(p)
	flush_text()
	# --- end screen
	if end_visible:
		ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.72))
		ctext(Vector2(s.x / 2, s.y / 2 - 70), "VITÓRIA!" if end_won else "DERROTA", 80, Color(0.5, 0.8, 1.0) if end_won else Color(1.0, 0.45, 0.4))
		var rr := restart_rect()
		ui.draw_rect(rr, Color(0.2, 0.35, 0.6, 0.95))
		ui.draw_rect(rr, Color(1, 1, 1, 0.8), false, 3.0)
		ctext(rr.get_center(), "Jogar de novo", 34, Color.WHITE)
		var cr := change_rect()
		ui.draw_rect(cr, Color(0.25, 0.25, 0.3, 0.95))
		ui.draw_rect(cr, Color(1, 1, 1, 0.6), false, 2.0)
		ctext(cr.get_center(), "Trocar herói", 24, Color.WHITE)
	flush_text()
	# --- hero pick
	if game.picking and not is_portrait():
		var ts := splash_tex.get_size()
		var sc: float = max(s.x / ts.x, s.y / ts.y)
		ui.draw_texture_rect(splash_tex, Rect2((s - ts * sc) / 2, ts * sc), false)
		ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.03, 0.06, 0.45))
		ctext(Vector2(s.x / 2, 60), "Escolha seu herói", 42, Color(1, 0.9, 0.6))
		for i in PICK.size():
			var r := pick_rect(i)
			var col: Color = Unit.KITS[PICK[i][0]]["col"]
			ui.draw_rect(r, Color(0.08, 0.09, 0.13, 0.88))
			ui.draw_rect(Rect2(r.position, Vector2(r.size.x, 6)), col)
			var pr: float = minf(36.0, r.size.y * 0.2)
			tex_circle(r.position + Vector2(pr + 12, pr + 14), pr, portraits[PICK[i][0]])
			ui.draw_arc(r.position + Vector2(pr + 12, pr + 14), pr + 1, 0, TAU, 32, col, 2.5)
			ui.draw_rect(r, Color(col, 0.8), false, 3.0)
			var cx := r.position.x + r.size.x / 2
			var nm: String = game.cfgs["hero_" + PICK[i][0]]["name"]
			var tx := (r.position.x + pr * 2 + 20 + r.end.x) / 2
			ctext(Vector2(tx, r.position.y + 34), nm, 28 if nm.length() < 10 else 24, Color.WHITE)
			ctext(Vector2(tx, r.position.y + 66), PICK[i][1], 17, col.lightened(0.2))
			ctext(Vector2(cx, r.position.y + 104), PICK[i][2], 14, Color(1, 1, 1, 0.8))
			var names: Array = Unit.KITS[PICK[i][0]]["names"]
			ctext(Vector2(cx, r.position.y + r.size.y - 50), names[0] + " · " + names[1], 13, Color(1, 1, 1, 0.65))
			ctext(Vector2(cx, r.position.y + r.size.y - 28), names[2] + " · " + names[3], 13, Color(1, 1, 1, 0.65))
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


## Skill-shot preview while a skill button is dragged: line on the ground + knob.
func draw_aim(p) -> void:
	var c := skill_center(aim_skill)
	var col: Color = p.kit_color()
	ui.draw_arc(c, 110, 0, TAU, 40, Color(1, 1, 1, 0.35), 3.0)
	var knob := c + aim_vec.limit_length(110)
	ui.draw_circle(knob, 26, Color(col, 0.6))
	var dragging := aim_vec.length() > AIM_DEAD
	var dir: Vector2 = aim_vec.normalized() if dragging else p.facing
	var rng: float = p.skill_range(aim_skill)
	if rng <= 0.0 or game.cam == null:
		return
	var from := Vector3(p.position.x, 0.1, p.position.z)
	var to := from + Vector3(dir.x, 0, dir.y) * rng
	var a: Vector2 = game.cam.unproject_position(from)
	var b: Vector2 = game.cam.unproject_position(to)
	var w := 16.0 if aim_skill == 1 and p.kit == "acougueiro" else 10.0
	ui.draw_line(a, b, Color(0, 0, 0, 0.35), w + 6)
	ui.draw_line(a, b, Color(col.lightened(0.3), 0.75 if dragging else 0.35), w)
	ui.draw_circle(b, w, Color(col.lightened(0.4), 0.9 if dragging else 0.4))


# ---------------------------------------------------------------- loja
func item_box(r: Rect2, e, p, flash := false) -> void:
	ui.draw_rect(r, Color(0.06, 0.06, 0.09, 0.85))
	if e == null:
		ui.draw_rect(r, Color(1, 1, 1, 0.18), false, 1.5)
		return
	var it: Dictionary = Items.ITEMS[e["id"]]
	var col: Color = it["col"]
	ui.draw_rect(r.grow(-3), Color(col.darkened(0.3), 0.95))
	ctext(r.get_center() + Vector2(0, -2), it["short"], 16 if r.size.x < 60 else 20, Color.WHITE)
	if it.get("consumable", false):
		text(r.position + Vector2(0, r.size.y - 4), str(e["n"]), 14, Color(1, 1, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 4)
	var cd: float = e["cd"]
	if e["id"] == "blink" and p.blink_lock > cd:
		cd = p.blink_lock
	if cd > 0:
		ui.draw_rect(r.grow(-3), Color(0, 0, 0, 0.6))
		ctext(r.get_center(), str(int(ceil(cd))), 20, Color.WHITE)
	ui.draw_rect(r, Color(col.lightened(0.3), 0.9) if it.get("active", false) else Color(1, 1, 1, 0.35), false, 2.0)
	if flash:
		ui.draw_rect(r, Color(1, 1, 1, 0.35))


func draw_item_slots(p) -> void:
	for i in Items.SLOTS:
		item_box(slot_rect(i), p.items[i], p, pressed_flash.has("slot%d" % i))
	if p.tp_t > 0:
		var r := slot_rect(0)
		ctext(Vector2(vs().x / 2, r.position.y - 18), "Teleportando... %.1fs" % p.tp_t, 18, Color(0.6, 0.85, 1.0))


func draw_shop(p) -> void:
	var r := shop_rect()
	var at_shop: bool = Items.near_shop(game, p)
	ui.draw_rect(r, Color(0.05, 0.06, 0.09, 0.93))
	ui.draw_rect(r, Color(1, 0.85, 0.4, 0.7), false, 3.0)
	text(r.position + Vector2(20, 40), "LOJA", 30, Color(1, 0.88, 0.45))
	ui.draw_circle(r.position + Vector2(130, 30), 9, Color(1.0, 0.8, 0.2))
	text(r.position + Vector2(146, 40), "%d" % int(p.gold), 24, Color(1.0, 0.88, 0.35))
	if shop_msg_t > 0.0:
		text(r.position + Vector2(220, 38), shop_msg, 18, Color(0.6, 1, 0.6) if shop_msg.begins_with("Comprou") else Color(1, 0.55, 0.5))
	elif not at_shop:
		text(r.position + Vector2(220, 38), "Volte à base para comprar", 18, Color(1, 0.55, 0.5))
	for i in Items.ORDER.size():
		var id: String = Items.ORDER[i]
		var it: Dictionary = Items.ITEMS[id]
		var tr := shop_tile(i)
		var why: String = Items.buy_block(game, p, id)
		var ok := why == ""
		var col: Color = it["col"]
		ui.draw_rect(tr, Color(0.12, 0.12, 0.16, 0.95))
		ui.draw_rect(Rect2(tr.position, Vector2(6, tr.size.y)), col)
		var ib := Rect2(tr.position + Vector2(12, 10), Vector2(44, 44))
		ui.draw_rect(ib, Color(col.darkened(0.3), 1.0 if ok else 0.5))
		ctext(ib.get_center(), it["short"], 15, Color(1, 1, 1, 1.0 if ok else 0.6))
		text(tr.position + Vector2(64, 26), it["name"], 15, Color(1, 1, 1, 1.0 if ok else 0.6), HORIZONTAL_ALIGNMENT_LEFT, tr.size.x - 70)
		text(tr.position + Vector2(64, 48), "%d" % it["cost"], 17, Color(1, 0.85, 0.35) if p.gold >= it["cost"] else Color(0.8, 0.4, 0.35))
		if why != "" and why != "ouro" and why != "volte à base":
			text(tr.position + Vector2(64, 48), why, 14, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, tr.size.x - 76)
		text(tr.position + Vector2(12, tr.size.y - 10), it["desc"], 12, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, tr.size.x - 20)
		ui.draw_rect(tr, Color(col, 0.8 if ok else 0.25), false, 2.0)
		if pressed_flash.has("shop%d" % i):
			ui.draw_rect(tr, Color(1, 1, 1, 0.3))
	for i in Items.SLOTS:
		var sr := shop_slot(i)
		item_box(sr, p.items[i], p)
		if sell_mode and p.items[i] != null:
			ui.draw_rect(sr.grow(2), Color(1, 0.4, 0.35, 0.9), false, 2.5)
			var e = p.items[i]
			ctext(sr.get_center() + Vector2(0, -sr.size.y / 2 - 10), "+%d" % (int(Items.ITEMS[e["id"]]["cost"] * Items.SELL_BACK) * e["n"]), 13, Color(1, 0.85, 0.35))
	var vr := sell_rect()
	ui.draw_rect(vr, Color(0.6, 0.2, 0.15, 0.95) if sell_mode else Color(0.25, 0.25, 0.3, 0.95))
	ui.draw_rect(vr, Color(1, 1, 1, 0.6), false, 2.0)
	ctext(vr.get_center(), "VENDER" if not sell_mode else "toque item", 18, Color.WHITE)
	var cr := close_rect()
	ui.draw_rect(cr, Color(0.2, 0.35, 0.6, 0.95))
	ui.draw_rect(cr, Color(1, 1, 1, 0.7), false, 2.0)
	ctext(cr.get_center(), "FECHAR", 20, Color.WHITE)
