extends Node2D
## MOBA prototype: one lane, player hero vs bot hero, creep waves, towers, bases.

const Unit := preload("res://scripts/unit.gd")
const FxScript := preload("res://scripts/fx.gd")
const MinimapScript := preload("res://scripts/minimap.gd")

var WORLD_W := 3200.0
var WORLD_H := 720.0
var LANE_Y := 360.0
var FOUNTAIN_R := 380.0
var WAVE_INTERVAL := 30.0

var heroes: Array = [null, null]
var player
var bot
var bases: Array = [null, null]
var towers: Array = [[], []]
var fx
var cam: Camera2D
var wave_timer := 3.0
var wave_count := 0
var game_time := 0.0
var game_over := false
var autotest := false

var trees: Array = []

# input
var move_finger := -1
var press_pos := Vector2.ZERO
var drag_active := false
var mouse_down := false

# hud
var hud: CanvasLayer
var lbl_info: Label
var lbl_respawn: Label
var lbl_help: Label
var lbl_wave: Label
var btn_skill: Button
var btn_upgrade: Button
var btn_restart: Button
var rotate_overlay: ColorRect
var end_panel: ColorRect
var end_label: Label
var minimap
var help_time := 9.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	autotest = "--autotest" in OS.get_cmdline_user_args()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 140:
		var x := rng.randf_range(0, WORLD_W)
		var y := rng.randf_range(10, 225) if rng.randf() < 0.5 else rng.randf_range(495, 710)
		if abs(x - WORLD_W / 2) < 90:
			continue
		trees.append(Vector3(x, y, rng.randf_range(14, 30)))

	fx = FxScript.new()
	fx.z_index = 50
	fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(fx)

	bases[0] = make_unit(Unit.Kind.BASE, 0, Vector2(160, LANE_Y))
	bases[1] = make_unit(Unit.Kind.BASE, 1, Vector2(WORLD_W - 160, LANE_Y))
	var tpos := [[Vector2(1150, LANE_Y - 75), Vector2(640, LANE_Y + 75)], [Vector2(WORLD_W - 1150, LANE_Y + 75), Vector2(WORLD_W - 640, LANE_Y - 75)]]
	for team in 2:
		for i in 2:
			var t = make_unit(Unit.Kind.TOWER, team, tpos[team][i])
			t.tier = i + 1
			towers[team].append(t)

	player = make_unit(Unit.Kind.HERO, 0, spawn_pos(0))
	player.is_player = true
	player.is_bot = autotest and not ("--afk" in OS.get_cmdline_user_args())
	bot = make_unit(Unit.Kind.HERO, 1, spawn_pos(1))
	bot.is_bot = true
	heroes = [player, bot]

	cam = Camera2D.new()
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(WORLD_W)
	cam.limit_bottom = int(WORLD_H)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	add_child(cam)
	cam.make_current()
	cam.position = player.position

	build_hud()
	update_invulnerability()
	if autotest:
		Engine.time_scale = 4.0
		pass


func make_unit(kind: int, team: int, pos: Vector2):
	var u = Unit.new()
	u.main = self
	u.team = team
	u.kind = kind
	u.position = pos
	u.process_mode = Node.PROCESS_MODE_PAUSABLE
	u.setup()
	add_child(u)
	u.add_to_group("units")
	return u


func spawn_pos(team: int) -> Vector2:
	return Vector2(300 if team == 0 else WORLD_W - 300, LANE_Y)


func clamp_world(p: Vector2) -> Vector2:
	return Vector2(clamp(p.x, 20, WORLD_W - 20), clamp(p.y, 240, WORLD_H - 240))


func camera_rect() -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	var c := cam.get_screen_center_position()
	return Rect2(c - vs / 2, vs)


# ---------------------------------------------------------------- loop
func _physics_process(delta: float) -> void:
	var portrait := is_portrait()
	rotate_overlay.visible = portrait
	if not game_over:
		get_tree().paused = portrait
	if game_over or portrait:
		return
	game_time += delta
	wave_timer -= delta
	if wave_timer <= 0:
		spawn_wave()
		wave_timer = WAVE_INTERVAL
	for h in heroes:
		h.gold += 1.5 * delta
	separation()
	if player.dead:
		cam.position = spawn_pos(0)
	else:
		cam.position = player.position
	if autotest and int(game_time * 60) % 1800 == 0:
		print("t=%d blue_towers=%d red_towers=%d baseHP=%d/%d p_lvl=%d bot_lvl=%d kills=%d/%d units=%d" % [game_time, towers[0].size(), towers[1].size(), bases[0].hp, bases[1].hp, player.level, bot.level, player.kills, bot.kills, get_tree().get_nodes_in_group("units").size()])
		if game_time > 1500:
			print("TIMEOUT")
			get_tree().quit()


func _process(delta: float) -> void:
	update_hud(delta)


func is_portrait() -> bool:
	var s := get_viewport().get_visible_rect().size
	return s.y > s.x * 1.05


func spawn_wave() -> void:
	wave_count += 1
	var melee := 3 + (1 if wave_count >= 8 else 0)
	for team in 2:
		var d := 1.0 if team == 0 else -1.0
		var bx := 270.0 if team == 0 else WORLD_W - 270.0
		for i in melee:
			var c = make_unit(Unit.Kind.CREEP, team, Vector2(bx - d * (i % 2) * 24, LANE_Y + (i - (melee - 1) / 2.0) * 24))
			c.lane_offset = (i - (melee - 1) / 2.0) * 22
		var r = make_unit(Unit.Kind.RANGED, team, Vector2(bx - d * 60, LANE_Y))
		r.lane_offset = 0


func separation() -> void:
	var units := get_tree().get_nodes_in_group("units")
	var n := units.size()
	for i in n:
		var a = units[i]
		if a.dead:
			continue
		var am: bool = a.is_mobile()
		for j in range(i + 1, n):
			var b = units[j]
			if b.dead:
				continue
			var bm: bool = b.is_mobile()
			if not am and not bm:
				continue
			var diff: Vector2 = b.position - a.position
			var dist := diff.length()
			var min_d: float = a.radius + b.radius
			if dist >= min_d:
				continue
			if dist < 0.01:
				diff = Vector2(randf() - 0.5, randf() - 0.5)
				dist = diff.length()
			var push: Vector2 = diff / dist * (min_d - dist)
			if am and bm:
				a.position -= push * 0.5
				b.position += push * 0.5
			elif am:
				a.position -= push
			else:
				b.position += push


# ---------------------------------------------------------------- queries
func find_target(u, r: float):
	var best = null
	var bd := INF
	for o in get_tree().get_nodes_in_group("units"):
		if o.dead or o.team == u.team or o.invulnerable:
			continue
		var d: float = u.position.distance_to(o.position) - o.radius
		if d < r and d < bd:
			best = o
			bd = d
	return best


func enemies_near(pos: Vector2, team: int, r: float) -> Array:
	var out: Array = []
	for o in get_tree().get_nodes_in_group("units"):
		if o.dead or o.team == team or o.invulnerable:
			continue
		if pos.distance_to(o.position) - o.radius < r:
			out.append(o)
	return out


func allied_creeps_near(pos: Vector2, team: int, r: float) -> int:
	var n := 0
	for o in get_tree().get_nodes_in_group("units"):
		if o.dead or o.team != team:
			continue
		if (o.kind == Unit.Kind.CREEP or o.kind == Unit.Kind.RANGED) and pos.distance_to(o.position) < r:
			n += 1
	return n


func structure_pick(s):
	var best = null
	var bd := INF
	var hero = null
	for o in get_tree().get_nodes_in_group("units"):
		if o.dead or o.team == s.team or o.invulnerable or not o.is_mobile():
			continue
		var d: float = s.position.distance_to(o.position) - o.radius
		if d > s.atk_range:
			continue
		if o.kind == Unit.Kind.HERO:
			hero = o
		elif d < bd:
			best = o
			bd = d
	return best if best != null else hero


func structures_of(team: int) -> Array:
	var out: Array = towers[team].duplicate()
	if bases[team] != null and not bases[team].dead:
		out.append(bases[team])
	return out


func is_unsafe(u, pos: Vector2) -> bool:
	for s in structures_of(1 - u.team):
		if s.dead:
			continue
		if pos.distance_to(s.position) < s.atk_range + s.radius + u.radius + 25:
			if s.target == u:
				return true
			if allied_creeps_near(s.position, u.team, s.atk_range + 20) == 0:
				return true
	return false


func front_x(team: int) -> float:
	var d := 1.0 if team == 0 else -1.0
	var best := -INF
	for o in get_tree().get_nodes_in_group("units"):
		if o.dead or o.team != team:
			continue
		if o.kind == Unit.Kind.CREEP or o.kind == Unit.Kind.RANGED:
			best = max(best, o.position.x * d)
	if best > -INF:
		return best * d - d * 90.0
	var ts: Array = towers[team]
	var fx_best := -INF
	for t in ts:
		fx_best = max(fx_best, t.position.x * d)
	if fx_best > -INF:
		return fx_best * d - d * 60.0
	return bases[team].position.x + d * 150.0


func call_tower_help(victim, attacker) -> void:
	for s in structures_of(victim.team):
		if s.dead:
			continue
		if s.position.distance_to(attacker.position) <= s.atk_range + attacker.radius:
			s.target = attacker


func update_invulnerability() -> void:
	for team in 2:
		var has_t1 := false
		for t in towers[team]:
			if t.tier == 1:
				has_t1 = true
		for t in towers[team]:
			t.invulnerable = t.tier == 2 and has_t1
			t.queue_redraw()
		bases[team].invulnerable = towers[team].size() > 0
		bases[team].queue_redraw()


func upgrade_cost(h) -> int:
	return 150 + 60 * h.upgrades


func buy_upgrade(h) -> void:
	var cost := upgrade_cost(h)
	if h.gold < cost or h.dead:
		return
	h.gold -= cost
	h.upgrades += 1
	h.dmg += 8
	h.max_hp += 60
	h.hp += 60
	fx.add_text(h.position, "+FORÇA", Color(1, 0.85, 0.3))


func on_unit_died(u, src) -> void:
	if src != null and is_instance_valid(src) and src.kind == Unit.Kind.HERO and src.team != u.team:
		src.gold += u.bounty
		if u.kind != Unit.Kind.HERO and src.is_player:
			fx.add_text(u.position, "+%d" % u.bounty, Color(1, 0.85, 0.2))
	for h in heroes:
		if h.team != u.team and not h.dead and h.position.distance_to(u.position) < 800:
			h.add_xp(u.xp_value)
	fx.add_ring(u.position, u.radius * 1.5, u.team_color(), 0.35)
	match u.kind:
		Unit.Kind.HERO:
			if src != null and is_instance_valid(src) and src.kind == Unit.Kind.HERO:
				src.kills += 1
			u.bounty = 200 + 20 * u.level
			u.xp_value = 120 + 40 * u.level
			u.start_respawn()
			fx.add_text(u.position, "ABATIDO!", Color.WHITE)
		Unit.Kind.TOWER:
			towers[u.team].erase(u)
			for h in heroes:
				if h.team != u.team:
					h.gold += 150
			u.remove_from_group("units")
			u.queue_free()
			update_invulnerability()
		Unit.Kind.BASE:
			end_game(u.team == 1)
		_:
			u.remove_from_group("units")
			u.queue_free()


func end_game(won: bool) -> void:
	game_over = true
	if autotest:
		print("GAME OVER won=%s t=%d" % [won, game_time])
		get_tree().quit()
		return
	end_label.text = "VITÓRIA!" if won else "DERROTA"
	end_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0) if won else Color(1.0, 0.45, 0.4))
	end_panel.visible = true
	get_tree().paused = true


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func cast_player_skill() -> void:
	if game_over:
		return
	player.cast_skill()


func player_upgrade() -> void:
	if game_over:
		return
	buy_upgrade(player)


# ---------------------------------------------------------------- input
func screen_to_world(p: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * p


func command_at(wp: Vector2, allow_target: bool) -> void:
	if player.dead or game_over:
		return
	help_time = min(help_time, 1.0)
	if allow_target:
		var best = null
		var bd := INF
		for o in get_tree().get_nodes_in_group("units"):
			if o.dead or o.team == 0 or o.invulnerable:
				continue
			var d: float = wp.distance_to(o.position)
			if d < o.radius + 35 and d < bd:
				best = o
				bd = d
		if best != null:
			player.target = best
			player.move_target = null
			fx.add_ring(best.position, best.radius + 10, Color(1, 0.3, 0.3), 0.3)
			return
	player.target = null
	player.move_target = clamp_world(wp)
	if allow_target:
		fx.add_ring(player.move_target, 12, Color(0.6, 1, 0.6), 0.3)


func touch_on_button(pos: Vector2) -> bool:
	for b in [btn_skill, btn_upgrade, btn_restart]:
		if b.is_visible_in_tree() and b.get_global_rect().grow(10).has_point(pos):
			b.pressed.emit()
			return true
	return false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if touch_on_button(event.position):
				get_viewport().set_input_as_handled()
				return
			if game_over or rotate_overlay.visible:
				return
			move_finger = event.index
			press_pos = event.position
			drag_active = false
			command_at(screen_to_world(event.position), true)
		elif event.index == move_finger:
			move_finger = -1
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == move_finger:
			if drag_active or event.position.distance_to(press_pos) > 25:
				drag_active = true
				command_at(screen_to_world(event.position), false)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not game_over:
			mouse_down = true
			press_pos = event.position
			drag_active = false
			command_at(screen_to_world(event.position), true)
		else:
			mouse_down = false
	elif event is InputEventMouseMotion and mouse_down:
		if drag_active or event.position.distance_to(press_pos) > 25:
			drag_active = true
			command_at(screen_to_world(event.position), false)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q or event.keycode == KEY_SPACE:
			cast_player_skill()
		elif event.keycode == KEY_W:
			player_upgrade()


# ---------------------------------------------------------------- HUD
func style_label(l: Label, size: int) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 7)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


func make_button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	return b


func anchor_br(c: Control, l: float, t: float, r: float, bt: float) -> void:
	c.anchor_left = 1; c.anchor_top = 1; c.anchor_right = 1; c.anchor_bottom = 1
	c.offset_left = l; c.offset_top = t; c.offset_right = r; c.offset_bottom = bt


func build_hud() -> void:
	hud = CanvasLayer.new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	lbl_info = Label.new()
	style_label(lbl_info, 24)
	lbl_info.position = Vector2(18, 10)
	root.add_child(lbl_info)

	lbl_wave = Label.new()
	style_label(lbl_wave, 20)
	lbl_wave.position = Vector2(18, 44)
	root.add_child(lbl_wave)

	minimap = MinimapScript.new()
	minimap.main = self
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.anchor_left = 0.5; minimap.anchor_right = 0.5
	minimap.offset_left = -220; minimap.offset_right = 220
	minimap.offset_top = 10; minimap.offset_bottom = 50
	root.add_child(minimap)

	btn_skill = make_button("ONDA", 30)
	anchor_br(btn_skill, -200, -200, -36, -36)
	btn_skill.pressed.connect(cast_player_skill)
	root.add_child(btn_skill)

	btn_upgrade = make_button("+FORÇA", 22)
	anchor_br(btn_upgrade, -200, -300, -36, -220)
	btn_upgrade.pressed.connect(player_upgrade)
	root.add_child(btn_upgrade)

	lbl_respawn = Label.new()
	style_label(lbl_respawn, 44)
	lbl_respawn.set_anchors_preset(Control.PRESET_CENTER)
	lbl_respawn.offset_left = -300; lbl_respawn.offset_right = 300
	lbl_respawn.offset_top = -120; lbl_respawn.offset_bottom = -60
	lbl_respawn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(lbl_respawn)

	lbl_help = Label.new()
	style_label(lbl_help, 22)
	lbl_help.anchor_left = 0; lbl_help.anchor_right = 1; lbl_help.anchor_top = 1; lbl_help.anchor_bottom = 1
	lbl_help.offset_left = 20; lbl_help.offset_right = -230; lbl_help.offset_top = -120; lbl_help.offset_bottom = -20
	lbl_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_help.text = "Toque ou arraste para mover. Toque num inimigo para atacar (o herói também ataca sozinho). ONDA = dano em área. Destrua as torres e a base vermelha!"
	root.add_child(lbl_help)

	end_panel = ColorRect.new()
	end_panel.color = Color(0, 0, 0, 0.72)
	end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_panel.visible = false
	root.add_child(end_panel)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.offset_left = -220; vb.offset_right = 220; vb.offset_top = -110; vb.offset_bottom = 110
	vb.add_theme_constant_override("separation", 24)
	end_panel.add_child(vb)
	end_label = Label.new()
	style_label(end_label, 72)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(end_label)
	btn_restart = make_button("Jogar de novo", 32)
	btn_restart.custom_minimum_size = Vector2(320, 80)
	btn_restart.pressed.connect(restart)
	vb.add_child(btn_restart)

	rotate_overlay = ColorRect.new()
	rotate_overlay.color = Color(0.05, 0.07, 0.1, 0.96)
	rotate_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	rotate_overlay.visible = false
	root.add_child(rotate_overlay)
	var rl := Label.new()
	style_label(rl, 40)
	rl.set_anchors_preset(Control.PRESET_FULL_RECT)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rl.text = "Gire o celular\npara a horizontal\n\n( ↻ )"
	rotate_overlay.add_child(rl)


func update_hud(delta: float) -> void:
	if player == null or lbl_info == null:
		return
	var mins := int(game_time) / 60
	var secs := int(game_time) % 60
	lbl_info.text = "Ouro %d   Nível %d   Abates %d x %d   %02d:%02d" % [int(player.gold), player.level, player.kills, bot.kills, mins, secs]
	lbl_wave.text = "Próxima onda em %ds" % ceil(wave_timer)
	if player.skill_timer > 0:
		btn_skill.text = "ONDA\n%d" % ceil(player.skill_timer)
		btn_skill.modulate = Color(1, 1, 1, 0.5)
	else:
		btn_skill.text = "ONDA"
		btn_skill.modulate = Color(1, 1, 1, 1)
	var cost := upgrade_cost(player)
	btn_upgrade.text = "+FORÇA %dg" % cost
	btn_upgrade.modulate = Color(1, 1, 1, 1) if player.gold >= cost else Color(1, 1, 1, 0.45)
	if player.dead:
		lbl_respawn.text = "Renascendo em %d" % ceil(player.respawn_timer)
		lbl_respawn.visible = true
	else:
		lbl_respawn.visible = false
	if not get_tree().paused:
		help_time -= delta
	lbl_help.visible = help_time > 0
	lbl_help.modulate.a = clamp(help_time, 0.0, 1.0)


# ---------------------------------------------------------------- map
func _draw() -> void:
	draw_rect(Rect2(0, 0, WORLD_W, WORLD_H), Color(0.15, 0.3, 0.16))
	# river
	draw_rect(Rect2(WORLD_W / 2 - 70, 0, 140, WORLD_H), Color(0.18, 0.42, 0.68))
	# lane
	draw_rect(Rect2(0, LANE_Y - 115, WORLD_W, 230), Color(0.47, 0.39, 0.27))
	draw_rect(Rect2(0, LANE_Y - 115, WORLD_W, 5), Color(0.33, 0.27, 0.18))
	draw_rect(Rect2(0, LANE_Y + 110, WORLD_W, 5), Color(0.33, 0.27, 0.18))
	# bridge planks
	for i in 8:
		draw_line(Vector2(WORLD_W / 2 - 70 + i * 20, LANE_Y - 112), Vector2(WORLD_W / 2 - 70 + i * 20, LANE_Y + 110), Color(0.38, 0.3, 0.2), 2)
	# fountains
	draw_circle(bases[0].position, FOUNTAIN_R, Color(0.25, 0.55, 1.0, 0.1))
	draw_circle(bases[1].position, FOUNTAIN_R, Color(1.0, 0.32, 0.25, 0.1))
	for t in trees:
		draw_circle(Vector2(t.x, t.y + 4), t.z, Color(0.05, 0.12, 0.06, 0.6))
		draw_circle(Vector2(t.x, t.y), t.z, Color(0.1, 0.24, 0.11))
		draw_circle(Vector2(t.x - t.z * 0.25, t.y - t.z * 0.25), t.z * 0.55, Color(0.16, 0.36, 0.17))
