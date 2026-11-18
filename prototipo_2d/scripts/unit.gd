extends Node2D
## Generic unit: hero, creep (melee/ranged), tower or base (ancient).

enum Kind { HERO, CREEP, RANGED, TOWER, BASE }

const TEAM_COLORS := [Color(0.25, 0.55, 1.0), Color(1.0, 0.32, 0.25)]

var main
var team := 0
var kind := Kind.CREEP
var max_hp := 100.0
var hp := 100.0
var dmg := 10.0
var atk_range := 40.0
var atk_cd := 1.0
var atk_timer := 0.0
var speed := 100.0
var radius := 12.0
var aggro_range := 250.0
var bounty := 20
var xp_value := 30
var regen := 0.0
var tier := 0
var invulnerable := false
var dead := false
var is_player := false
var is_bot := false
var target = null
var move_target = null
var facing := Vector2.RIGHT
var flash := 0.0
var lane_offset := 0.0

# hero only
var level := 1
var xp := 0.0
var gold := 0.0
var upgrades := 0
var skill_cd := 8.0
var skill_timer := 0.0
var respawn_timer := 0.0
var retreating := false
var kills := 0


func setup() -> void:
	match kind:
		Kind.HERO:
			max_hp = 700; dmg = 45; atk_range = 170; atk_cd = 0.8; speed = 210
			radius = 18; aggro_range = 0; bounty = 200; xp_value = 150; regen = 2.5
			z_index = 3
		Kind.CREEP:
			max_hp = 300; dmg = 18; atk_range = 26; atk_cd = 1.0; speed = 95
			radius = 11; aggro_range = 260; bounty = 20; xp_value = 40
			z_index = 2
		Kind.RANGED:
			max_hp = 220; dmg = 24; atk_range = 170; atk_cd = 1.3; speed = 95
			radius = 10; aggro_range = 260; bounty = 25; xp_value = 50
			z_index = 2
		Kind.TOWER:
			max_hp = 1300; dmg = 60; atk_range = 320; atk_cd = 1.0; speed = 0
			radius = 28; aggro_range = 0; bounty = 150; xp_value = 100
			z_index = 1
		Kind.BASE:
			max_hp = 2200; dmg = 50; atk_range = 300; atk_cd = 1.0; speed = 0
			radius = 52; aggro_range = 0; bounty = 0; xp_value = 0
			z_index = 1
	hp = max_hp
	facing = Vector2.RIGHT if team == 0 else Vector2.LEFT


func dir() -> float:
	return 1.0 if team == 0 else -1.0


func is_mobile() -> bool:
	return kind == Kind.HERO or kind == Kind.CREEP or kind == Kind.RANGED


func team_color() -> Color:
	return TEAM_COLORS[team]


func is_valid_target(t) -> bool:
	return t != null and is_instance_valid(t) and not t.dead and t.team != team and not t.invulnerable


func _physics_process(delta: float) -> void:
	if main == null or main.game_over:
		return
	if flash > 0:
		flash -= delta
	if dead:
		if kind == Kind.HERO:
			respawn_timer -= delta
			if respawn_timer <= 0:
				respawn()
		return
	atk_timer -= delta
	if kind == Kind.HERO:
		skill_timer -= delta
		hp = min(max_hp, hp + regen * delta)
		if position.distance_to(main.bases[team].position) < main.FOUNTAIN_R:
			hp = min(max_hp, hp + max_hp * 0.12 * delta)
		if is_bot:
			bot_ai(delta)
		else:
			player_ai(delta)
	elif kind == Kind.CREEP or kind == Kind.RANGED:
		creep_ai(delta)
	else:
		structure_ai()
	queue_redraw()


# ---------------------------------------------------------------- combat
func try_attack(t) -> bool:
	var reach: float = atk_range + radius + t.radius
	if position.distance_to(t.position) > reach:
		return false
	facing = (t.position - position).normalized() if t.position != position else facing
	if atk_timer <= 0:
		atk_timer = atk_cd
		main.fx.add_shot(position, t.position, team_color().lightened(0.3), atk_range > 60)
		t.take_damage(dmg, self)
	return true


func take_damage(amount: float, src) -> void:
	if dead or invulnerable:
		return
	hp -= amount
	flash = 0.12
	if kind == Kind.HERO and src != null and is_instance_valid(src) and src.kind == Kind.HERO:
		main.call_tower_help(self, src)
	if hp <= 0:
		hp = 0
		dead = true
		main.on_unit_died(self, src)
	queue_redraw()


func move_towards(p: Vector2, delta: float) -> void:
	var d := p - position
	var l := d.length()
	if l < 2.0:
		return
	facing = d / l
	position += facing * min(speed * delta, l)
	position = main.clamp_world(position)


# ---------------------------------------------------------------- AI
func creep_ai(delta: float) -> void:
	if not is_valid_target(target) or position.distance_to(target.position) > aggro_range * 1.4:
		target = main.find_target(self, aggro_range)
	if target != null:
		if not try_attack(target):
			move_towards(target.position, delta)
	else:
		var goal_x: float = main.WORLD_W - 150.0 if team == 0 else 150.0
		move_towards(Vector2(goal_x, main.LANE_Y + lane_offset), delta)


func structure_ai() -> void:
	if not is_valid_target(target) or position.distance_to(target.position) > atk_range + target.radius:
		target = main.structure_pick(self)
	if target != null:
		try_attack(target)


func player_ai(delta: float) -> void:
	if target != null:
		if is_valid_target(target):
			if not try_attack(target):
				move_towards(target.position, delta)
			return
		target = null
	if move_target != null:
		move_towards(move_target, delta)
		if position.distance_to(move_target) < 4.0:
			move_target = null
		return
	var t = main.find_target(self, atk_range + radius)
	if t != null:
		try_attack(t)


func bot_ai(delta: float) -> void:
	var home: Vector2 = main.bases[team].position
	if hp < max_hp * 0.3:
		retreating = true
	if retreating:
		if hp >= max_hp * 0.9:
			retreating = false
		else:
			move_towards(home + Vector2(dir() * 110.0, 0), delta)
			return
	if gold >= main.upgrade_cost(self):
		main.buy_upgrade(self)
	if skill_timer <= 0:
		var near: Array = main.enemies_near(position, team, 200.0)
		var hero_in := false
		for e in near:
			if e.kind == Kind.HERO:
				hero_in = true
		if near.size() >= 3 or hero_in:
			cast_skill()
	if main.is_unsafe(self, position):
		move_towards(Vector2(position.x - dir() * 200.0, main.LANE_Y + 40.0 * dir()), delta)
		return
	var t = pick_bot_target()
	if t != null:
		if not try_attack(t):
			move_towards(t.position, delta)
		return
	var goal_x: float = main.front_x(team)
	move_towards(Vector2(goal_x, main.LANE_Y - 45.0 * dir()), delta)


func pick_bot_target():
	var cands: Array = main.enemies_near(position, team, 330.0)
	if cands.is_empty():
		return null
	var foe = main.heroes[1 - team]
	if foe in cands and (foe.hp < foe.max_hp * 0.45 or hp > foe.hp * 1.3):
		return foe
	if foe in cands and position.distance_to(foe.position) <= atk_range + radius * 2 and hp >= foe.hp * 0.75:
		return foe
	var best = null
	for c in cands:
		if c.kind == Kind.CREEP or c.kind == Kind.RANGED:
			if best == null or c.hp < best.hp:
				best = c
	if best != null:
		return best
	for c in cands:
		if (c.kind == Kind.TOWER or c.kind == Kind.BASE) and main.allied_creeps_near(c.position, team, c.atk_range + 20.0) > 0:
			return c
	if foe in cands and position.distance_to(foe.position) <= atk_range + radius * 2:
		return foe
	return null


# ---------------------------------------------------------------- hero stuff
func cast_skill() -> bool:
	if kind != Kind.HERO or dead or skill_timer > 0:
		return false
	var r := 210.0
	var amount := 140.0 + 20.0 * level
	main.fx.add_nova(position, r, team_color().lightened(0.4))
	for e in main.enemies_near(position, team, r):
		e.take_damage(amount, self)
	skill_timer = skill_cd
	return true


func xp_to_next() -> float:
	return 100.0 + level * 60.0


func add_xp(v: float) -> void:
	if level >= 10:
		return
	xp += v
	while level < 10 and xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		max_hp += 80
		hp += 80
		dmg += 6
		main.fx.add_text(position, "NÍVEL %d" % level, Color(1, 0.9, 0.3))


func start_respawn() -> void:
	dead = true
	visible = false
	target = null
	move_target = null
	retreating = false
	respawn_timer = 4.0 + level * 2.0


func respawn() -> void:
	dead = false
	visible = true
	hp = max_hp
	position = main.spawn_pos(team)
	atk_timer = 0


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	var c := team_color()
	if flash > 0:
		c = c.lerp(Color.WHITE, 0.6)
	match kind:
		Kind.TOWER:
			draw_arc(Vector2.ZERO, atk_range, 0, TAU, 64, Color(c, 0.13), 2.0)
			draw_rect(Rect2(-radius, -radius, radius * 2, radius * 2), c.darkened(0.45))
			draw_rect(Rect2(-radius + 6, -radius + 6, (radius - 6) * 2, (radius - 6) * 2), c)
			draw_circle(Vector2.ZERO, 8, c.lightened(0.5))
		Kind.BASE:
			var pts := PackedVector2Array()
			var pts2 := PackedVector2Array()
			for i in 8:
				var a := TAU * i / 8.0 + PI / 8.0
				pts.append(Vector2(cos(a), sin(a)) * radius)
				pts2.append(Vector2(cos(a), sin(a)) * radius * 0.65)
			draw_colored_polygon(pts, c.darkened(0.45))
			draw_colored_polygon(pts2, c)
			draw_circle(Vector2.ZERO, 12, c.lightened(0.6))
		Kind.HERO:
			draw_circle(Vector2.ZERO, radius, c)
			draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color.WHITE if is_player else Color.BLACK, 3.0)
			var tip := facing * (radius + 11)
			var tri := PackedVector2Array([tip, facing.rotated(2.3) * radius * 0.8, facing.rotated(-2.3) * radius * 0.8])
			draw_colored_polygon(tri, Color(1, 1, 1, 0.9))
		Kind.CREEP:
			draw_circle(Vector2.ZERO, radius, c)
			draw_arc(Vector2.ZERO, radius, 0, TAU, 20, c.darkened(0.5), 2.0)
		Kind.RANGED:
			var dia := PackedVector2Array([Vector2(0, -radius - 2), Vector2(radius + 2, 0), Vector2(0, radius + 2), Vector2(-radius - 2, 0)])
			draw_colored_polygon(dia, c)
	if invulnerable:
		draw_arc(Vector2.ZERO, radius + 8, 0, TAU, 32, Color(1, 1, 1, 0.45), 3.0)
	# HP bar
	var bw := 26.0
	match kind:
		Kind.HERO: bw = 54.0
		Kind.TOWER: bw = 66.0
		Kind.BASE: bw = 110.0
	var y := -radius - 14.0
	draw_rect(Rect2(-bw / 2 - 1, y - 1, bw + 2, 8), Color(0, 0, 0, 0.8))
	var hc := Color(0.25, 0.9, 0.3) if team == 0 else Color(0.95, 0.25, 0.2)
	if is_player:
		hc = Color(0.55, 1.0, 0.35)
	draw_rect(Rect2(-bw / 2, y, bw * clamp(hp / max_hp, 0.0, 1.0), 6), hc)
	if kind == Kind.HERO:
		draw_string(ThemeDB.fallback_font, Vector2(-bw / 2 - 20, y + 8), str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
