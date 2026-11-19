extends Node3D
## Generic 3D unit: hero, creep (melee/ranged), tower or base (ancient).
## Gameplay runs on the ground plane: Vector2(x, z).

enum Kind { HERO, CREEP, RANGED, TOWER, BASE }

const TEAM_COLORS := [Color(0.3, 0.6, 1.0), Color(1.0, 0.3, 0.22), Color(1.0, 0.82, 0.3)]

var game
var team := 0
var kind := Kind.CREEP
var max_hp := 100.0
var hp := 100.0
var dmg := 10.0
var atk_range := 1.0
var atk_cd := 1.0
var atk_timer := 0.0
var speed := 3.0
var radius := 0.4
var aggro_range := 8.0
var bounty := 20
var xp_value := 30
var regen := 0.0
var tier := 0
var invulnerable := false
var dead := false
var is_player := false
var is_bot := false
var target = null
var facing := Vector2(1, 0)
var lane_offset := 0.0
var hit_height := 1.0
var bar_height := 2.2
var ranged_attack := false
var hero_name := ""
var lane := -1
var lane_s := 0.0
var camp = null
var home_pos := Vector2.ZERO
var retarget_t := 0.0
var lane_goal := Vector2.ZERO

# bot hero brain
var path := PackedVector2Array()
var path_i := 0
var path_goal := Vector2(INF, INF)
var path_t := 0.0
var think_t := 0.0
var jungle_camp = null
var react_t := 0.0

# hit timing
var pending_hit = null
var pending_t := 0.0

# hero only
var level := 1
var xp := 0.0
var gold := 0.0
var upgrades := 0
var cds := [0.0, 0.0, 0.0, 0.0]
var cd_max := [6.0, 9.0, 15.0, 45.0]
var respawn_timer := 0.0
var retreating := false
var kills := 0
var deaths := 0
var buff_t := 0.0
var dash_t := 0.0
var dash_dir := Vector2.ZERO
var dash_hit: Array = []
var ult_t := -1.0
var ult_pos := Vector2.ZERO
var move_input := Vector2.ZERO
var attack_cmd := false
var lock_t := 0.0

# visuals
var model: Node3D
var anim: AnimationPlayer
var anims := {}
var cur_anim := ""
var ring: MeshInstance3D
var range_ring: MeshInstance3D
var crystal: MeshInstance3D
var corpse_t := 0.0


func p2() -> Vector2:
	return Vector2(position.x, position.z)


func set_p2(v: Vector2) -> void:
	position.x = v.x
	position.z = v.y


func dist_to(o) -> float:
	return p2().distance_to(o.p2())


func setup(cfg: Dictionary) -> void:
	match kind:
		Kind.HERO:
			max_hp = 720; dmg = 46; atk_range = 5.0; atk_cd = 0.85; speed = 6.2
			radius = 0.55; aggro_range = 0; bounty = 200; xp_value = 150; regen = 2.5
			hit_height = 1.0; bar_height = 2.4
		Kind.CREEP:
			max_hp = 300; dmg = 18; atk_range = 0.6; atk_cd = 1.0; speed = 3.0
			radius = 0.4; aggro_range = 8.0; bounty = 20; xp_value = 40
			hit_height = 0.7; bar_height = 1.6
		Kind.RANGED:
			max_hp = 220; dmg = 24; atk_range = 5.0; atk_cd = 1.3; speed = 3.0
			radius = 0.38; aggro_range = 8.0; bounty = 25; xp_value = 50
			hit_height = 0.7; bar_height = 1.6; ranged_attack = true
		Kind.TOWER:
			max_hp = 1700; dmg = 70; atk_range = 9.5; atk_cd = 1.0; speed = 0
			radius = 1.3; bounty = 150; xp_value = 100; ranged_attack = true
			hit_height = 3.0; bar_height = 7.6
		Kind.BASE:
			max_hp = 2200; dmg = 50; atk_range = 9.0; atk_cd = 1.0; speed = 0
			radius = 2.3; bounty = 0; xp_value = 0; ranged_attack = true
			hit_height = 4.0; bar_height = 11.0
	if team == 2:
		aggro_range = 0.0
		if kind == Kind.CREEP:
			max_hp = 520; dmg = 26; speed = 3.6; radius = 0.55; bounty = 45; xp_value = 70
		else:
			max_hp = 300; dmg = 22; speed = 3.6; bounty = 30; xp_value = 50
	if cfg.has("stats"):
		var st: Dictionary = cfg["stats"]
		max_hp = st["hp"]; dmg = st["dmg"]; atk_range = st["range"]; atk_cd = st["cd"]; speed = st["speed"]
	if kind == Kind.HERO:
		ranged_attack = atk_range > 2.0
	hp = max_hp
	facing = Vector2(1, 0) if team == 0 else Vector2(-1, 0)
	build_visual(cfg)


func build_visual(cfg: Dictionary) -> void:
	var scn: PackedScene = cfg["scene"]
	model = scn.instantiate()
	model.scale = Vector3.ONE * cfg["scale"]
	add_child(model)
	var shadows: bool = not game.low_quality and (kind == Kind.HERO or kind == Kind.TOWER or kind == Kind.BASE)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.name in cfg.get("hide", []):
			mi.get_parent().remove_child(mi)
			mi.free()
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if cfg.get("merge", false):
		game.merge_skinned(model, cfg)
	if cfg.has("lib"):
		var ap := AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		model.add_child(ap)
		ap.add_animation_library("", cfg["lib"])
	if cfg.has("weapon"):
		var w: Array = cfg["weapon"]
		var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var ba := BoneAttachment3D.new()
		ba.bone_name = w[1]
		sk.add_child(ba)
		var wn: Node3D = w[0].instantiate()
		wn.position = w[2]
		wn.rotation_degrees = w[3]
		wn.scale = Vector3.ONE * w[4]
		ba.add_child(wn)
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		anim = aps[0]
		anims = cfg.get("anims", {})
		for key in ["idle", "run"]:
			if anims.has(key) and anim.has_animation(anims[key]):
				anim.get_animation(anims[key]).loop_mode = Animation.LOOP_LINEAR
		play("idle")
	# team ring on the ground
	ring = MeshInstance3D.new()
	var tm := PlaneMesh.new()
	tm.size = Vector2(2, 2)
	ring.mesh = tm
	var c := team_color()
	if is_player:
		c = Color(0.45, 1.0, 0.45)
	ring.material_override = game.fx.ground_ring_mat(Color(c, 0.9))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rs: float = radius * (1.35 if kind == Kind.HERO else 1.2)
	ring.scale = Vector3(rs, 0.3, rs)
	ring.position.y = 0.05
	add_child(ring)
	if kind == Kind.CREEP or kind == Kind.RANGED:
		ring.visible = false
	if kind == Kind.TOWER or kind == Kind.BASE:
		ring.visible = false
		crystal = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.45 if kind == Kind.TOWER else 0.8
		sm.height = sm.radius * 2.6
		sm.radial_segments = 6
		sm.rings = 3
		crystal.mesh = sm
		crystal.material_override = game.fx.glow_mat(Color(team_color(), 0.95), 2.2)
		crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		crystal.position.y = 7.4 if kind == Kind.TOWER else 10.6
		add_child(crystal)
		range_ring = MeshInstance3D.new()
		range_ring.mesh = tm
		range_ring.material_override = game.fx.ground_ring_mat(Color(1.0, 0.25, 0.2, 0.6), 0.05, 0.03)
		range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var rr := atk_range + 0.5
		range_ring.scale = Vector3(rr, 0.2, rr)
		range_ring.position.y = 0.06
		range_ring.visible = false
		add_child(range_ring)


func play(key: String, speed_scale := 1.0, force := false) -> void:
	if anim == null or not anims.has(key):
		return
	var a: String = anims[key]
	if not anim.has_animation(a):
		return
	if a == cur_anim and not force:
		anim.speed_scale = speed_scale
		return
	cur_anim = a
	anim.play(a, 0.15)
	anim.speed_scale = speed_scale
	if force:
		anim.seek(0.0, true)


func team_color() -> Color:
	return TEAM_COLORS[team]


func is_mobile() -> bool:
	return kind == Kind.HERO or kind == Kind.CREEP or kind == Kind.RANGED


func is_valid_target(t) -> bool:
	return t != null and is_instance_valid(t) and not t.dead and t.team != team and not t.invulnerable


func atk_speed_mult() -> float:
	return 1.6 if buff_t > 0 else 1.0


func move_speed() -> float:
	return speed * (1.35 if buff_t > 0 else 1.0)


func _physics_process(delta: float) -> void:
	if game == null or game.game_over:
		return
	if dead:
		if corpse_t > 0:
			corpse_t -= delta
			if corpse_t <= 0:
				if kind == Kind.HERO:
					visible = false
				else:
					game.recycle(self)
		if kind == Kind.HERO:
			respawn_timer -= delta
			if respawn_timer <= 0:
				respawn()
		return
	atk_timer -= delta
	lock_t -= delta
	if pending_hit != null:
		pending_t -= delta
		if pending_t <= 0:
			var t = pending_hit
			pending_hit = null
			if is_valid_target(t) and dist_to(t) <= atk_range + radius + t.radius + 1.0:
				t.take_damage(dmg, self)
				game.fx.add_spark(t.position + Vector3(0, t.hit_height, 0), team_color().lightened(0.4), 0.35)
	var t0 := Time.get_ticks_usec()
	if kind == Kind.HERO:
		hero_tick(delta)
		game.pf("hero", t0)
	elif team == 2:
		neutral_ai(delta)
		game.pf("neutral", t0)
	elif kind == Kind.CREEP or kind == Kind.RANGED:
		creep_ai(delta)
		game.pf("creep", t0)
	else:
		structure_ai()
		game.pf("struct", t0)
		if range_ring != null:
			var pl = game.player
			range_ring.visible = team != pl.team and not pl.dead and dist_to(pl) < atk_range + 4.0
		if crystal != null:
			crystal.rotation.y += delta * 1.5


# ---------------------------------------------------------------- combat
func try_attack(t) -> bool:
	var reach: float = atk_range + radius + t.radius
	if dist_to(t) > reach:
		return false
	face(t.p2() - p2())
	if atk_timer <= 0 and lock_t <= 0:
		atk_timer = atk_cd / atk_speed_mult()
		if ranged_attack:
			var from := position + Vector3(0, hit_height + (0.6 if kind == Kind.HERO else 0.3), 0)
			if kind == Kind.TOWER:
				from = position + Vector3(0, 7.4, 0)
			elif kind == Kind.BASE:
				from = position + Vector3(0, 10.6, 0)
			var c := team_color().lightened(0.35)
			var sz := 0.5 if (kind == Kind.TOWER or kind == Kind.BASE) else 0.3
			var spd := 22.0 if (kind == Kind.TOWER or kind == Kind.BASE) else 16.0
			if kind == Kind.HERO:
				c = Color(0.6, 0.85, 1.0)
			game.fx.add_projectile(from, t, self, dmg, c, spd, sz)
		else:
			pending_hit = t
			pending_t = 0.25 / atk_speed_mult()
		play("attack", atk_speed_mult() * max(1.0, 1.0 / atk_cd), true)
	elif atk_timer < atk_cd * 0.4 and (cur_anim == anims.get("run", "")):
		play("idle")
	return true


func take_damage(amount: float, src) -> void:
	if dead or invulnerable:
		return
	if (kind == Kind.TOWER or kind == Kind.BASE) and src != null and is_instance_valid(src) and src.kind == Kind.HERO:
		amount *= 0.6
	hp -= amount
	if team == 2 and src != null and is_instance_valid(src) and not src.dead:
		if not is_valid_target(target):
			target = src
		if camp != null:
			for m in camp["units"]:
				if m.camp == camp and not m.dead and not m.is_valid_target(m.target):
					m.target = src
	if kind == Kind.HERO and src != null and is_instance_valid(src) and src.kind == Kind.HERO:
		game.call_tower_help(self, src)
	if hp <= 0:
		hp = 0
		die(src)


func die(src) -> void:
	dead = true
	pending_hit = null
	target = null
	ring.visible = false
	if range_ring != null:
		range_ring.visible = false
	remove_from_group("units")
	if kind == Kind.TOWER or kind == Kind.BASE:
		game.fx.add_nova(position, radius * 3.0, team_color())
		visible = false
	else:
		play("death", 1.0, true)
		corpse_t = 1.6
	game.on_unit_died(self, src)


func face(d: Vector2) -> void:
	if d.length_squared() < 0.0001:
		return
	facing = d.normalized()
	if model != null:
		var target_rot := atan2(facing.x, facing.y)
		model.rotation.y = lerp_angle(model.rotation.y, target_rot, 0.35)


func move_towards(p: Vector2, delta: float) -> bool:
	var d := p - p2()
	var l := d.length()
	if l < 0.08:
		return false
	face(d)
	set_p2(game.clamp_world(p2() + d / l * min(move_speed() * delta, l)))
	play("run", move_speed() / 4.5)
	return true


func move_dir(d: Vector2, delta: float) -> void:
	face(d)
	set_p2(game.clamp_world(p2() + d.normalized() * move_speed() * delta))
	play("run", move_speed() / 4.5)


func idle() -> void:
	if lock_t > 0:
		return
	if atk_timer < atk_cd * 0.5 / atk_speed_mult() or cur_anim == anims.get("run", ""):
		play("idle")


# ---------------------------------------------------------------- AI
func creep_ai(delta: float) -> void:
	retarget_t -= delta
	if retarget_t <= 0:
		retarget_t = 0.3
		if not is_valid_target(target) or dist_to(target) > aggro_range * 1.4:
			target = game.find_target(self, aggro_range)
		lane_s = game.lane_proj(lane, p2())
		var ahead: float = lane_s + (4.0 if team == 0 else -4.0)
		lane_goal = game.lane_point(lane, ahead) + game.lane_normal(lane, ahead) * lane_offset
	if is_valid_target(target):
		if not try_attack(target):
			move_towards(target.p2(), delta)
	else:
		target = null
		move_towards(lane_goal, delta)


func neutral_ai(delta: float) -> void:
	if is_valid_target(target) and target.p2().distance_to(home_pos) < 13.0:
		if not try_attack(target):
			move_towards(target.p2(), delta)
		return
	target = null
	if p2().distance_to(home_pos) > 0.6:
		move_towards(home_pos, delta)
		hp = min(max_hp, hp + max_hp * 0.25 * delta)
	else:
		hp = min(max_hp, hp + max_hp * 0.04 * delta)
		idle()


func structure_ai() -> void:
	if not is_valid_target(target) or dist_to(target) > atk_range + target.radius:
		target = game.structure_pick(self)
	if target != null:
		try_attack(target)


func hero_tick(delta: float) -> void:
	for i in 4:
		cds[i] = max(0.0, cds[i] - delta)
	buff_t -= delta
	hp = min(max_hp, hp + regen * delta)
	if p2().distance_to(game.fountain_pos(team)) < game.FOUNTAIN_R:
		hp = min(max_hp, hp + max_hp * 0.12 * delta)
	if ult_t >= 0:
		ult_t -= delta
		if ult_t < 0:
			ult_land()
	if dash_t > 0:
		dash_tick(delta)
		return
	if is_bot:
		bot_ai(delta)
	else:
		player_ai(delta)


func player_ai(delta: float) -> void:
	if move_input.length() > 0.15:
		target = null
		attack_cmd = false
		if lock_t <= 0:
			move_dir(move_input, delta)
		return
	if attack_cmd:
		attack_cmd = false
		var t = game.find_target(self, 9.0, true)
		if t != null:
			target = t
	if target != null:
		if is_valid_target(target) and dist_to(target) < 14.0:
			if not try_attack(target):
				move_towards(target.p2(), delta)
			return
		target = null
	var a = game.find_target(self, atk_range + radius, true)
	if a != null:
		try_attack(a)
	else:
		idle()


## Moves along an A* path through the jungle (straight line when close).
func nav_to(goal: Vector2, delta: float) -> bool:
	var d := p2().distance_to(goal)
	if d < 0.7:
		return false
	if d < 5.0:
		return move_towards(goal, delta)
	path_t -= delta
	if path.is_empty() or path_goal.distance_to(goal) > 3.0 or path_t <= 0:
		path = game.find_path(p2(), goal)
		path_i = 0
		path_goal = goal
		path_t = 2.0
	while path_i < path.size() and p2().distance_to(path[path_i]) < 1.3:
		path_i += 1
	if path_i >= path.size():
		return move_towards(goal, delta)
	return move_towards(path[min(path_i + 1, path.size() - 1)] if p2().distance_to(path[path_i]) < 2.0 else path[path_i], delta)


func hp_frac() -> float:
	return hp / max_hp


func bot_ai(delta: float) -> void:
	var home: Vector2 = game.fountain_pos(team)
	var dirn := 1.0 if team == 0 else -1.0
	if gold >= game.upgrade_cost(self) and (randf() < 0.02 or p2().distance_to(home) < game.FOUNTAIN_R):
		game.buy_upgrade(self)
	var foe = game.nearest_enemy_hero(self, 12.0)
	var allies_n: int = game.heroes_near(p2(), team, 11.0)
	var foes_n: int = game.heroes_near(p2(), 1 - team, 11.0)
	# --- retreat & regen
	if hp_frac() < 0.3 or (foes_n > allies_n and hp_frac() < 0.55):
		retreating = true
		jungle_camp = null
	if retreating:
		if hp_frac() >= 0.92:
			retreating = false
		else:
			if foe != null and dist_to(foe) < 5.0 and cds[1] <= 0:
				facing = (home - p2()).normalized()
				cast(1)
			elif foe != null and dist_to(foe) < 3.4 and cds[0] <= 0:
				cast(0)
			if not nav_to(home, delta):
				idle()
			return
	use_skills(foe)
	# --- don't stand under enemy towers without creeps
	if game.is_unsafe(self, p2()):
		var ls: float = game.lane_proj(lane, p2())
		nav_to(game.lane_point(lane, ls - dirn * 7.0), delta)
		return
	think_t -= delta
	if think_t <= 0:
		think_t = 0.25 + randf() * 0.15
		target = pick_bot_target(foe)
		if think_t > 0.35 and target == null:
			decide_roam()
	if is_valid_target(target) and not (target.kind == Kind.HERO and game.is_unsafe(self, target.p2())):
		if not try_attack(target):
			if target.p2().distance_to(p2()) < 6.0:
				move_towards(target.p2(), delta)
			else:
				nav_to(target.p2(), delta)
		return
	target = null
	if jungle_camp != null:
		if not game.camp_alive(jungle_camp):
			jungle_camp = null
		else:
			if not nav_to(jungle_camp["pos"], delta):
				idle()
			return
	if not nav_to(game.lane_hold_point(team, lane), delta):
		idle()


## Farm a nearby own-side jungle camp when the lane is quiet, or chase a weak enemy hero.
func decide_roam() -> void:
	if jungle_camp != null or hp_frac() < 0.6:
		return
	if game.enemy_creeps_in_lane(team, lane) > 0 and p2().distance_to(game.lane_hold_point(team, lane)) < 25.0:
		return
	var best = null
	var bd := 40.0
	for c in game.camps:
		var own_side: bool = (c["pos"].y > c["pos"].x) == (team == 0)
		if own_side and game.camp_alive(c) and p2().distance_to(c["pos"]) < bd:
			bd = p2().distance_to(c["pos"])
			best = c
	jungle_camp = best


func use_skills(foe) -> void:
	react_t -= get_physics_process_delta_time()
	if react_t > 0:
		return
	var near: Array = game.enemies_near(p2(), team, 3.6)
	var lane_near := 0
	for e in near:
		if e.team != 2 or jungle_camp != null:
			lane_near += 1
	if cds[0] <= 0 and (lane_near >= 3 or (foe != null and dist_to(foe) < 3.4)):
		cast(0)
		react_t = 0.4
		return
	if foe != null and dist_to(foe) < 8.0:
		var winning: bool = foe.hp_frac() < hp_frac() + 0.1 or foe.hp_frac() < 0.4
		if not winning:
			return
		if cds[2] <= 0 and dist_to(foe) < 6.0:
			cast(2)
			react_t = 0.3
		elif cds[3] <= 0 and level >= 3 and dist_to(foe) < 6.5:
			facing = (foe.p2() - p2()).normalized()
			cast(3)
			react_t = 0.5
		elif cds[1] <= 0 and foe.hp_frac() < 0.4 and dist_to(foe) > 3.0 and not game.is_unsafe(self, foe.p2()):
			facing = (foe.p2() - p2()).normalized()
			cast(1)
			react_t = 0.3
	elif cds[3] <= 0 and level >= 3:
		var spot: Vector2 = p2() + facing * 3.5
		if game.enemies_near(spot, team, 5.0).size() >= 5:
			cast(3)
			react_t = 0.5


func pick_bot_target(foe):
	var cands: Array = game.enemies_near(p2(), team, 9.0)
	if cands.is_empty():
		return null
	# go for the enemy hero when it is weak or we clearly win the trade
	if foe != null and dist_to(foe) < 9.0 and not game.is_unsafe(self, foe.p2()):
		if foe.hp_frac() < 0.4 or hp_frac() > foe.hp_frac() + 0.25:
			return foe
	# last hit
	var lh = null
	var low = null
	for c in cands:
		if c.kind != Kind.CREEP and c.kind != Kind.RANGED:
			continue
		if c.team == 2 and jungle_camp == null:
			continue
		if c.hp <= dmg * 1.15 and (lh == null or c.hp < lh.hp):
			lh = c
		if low == null or c.hp < low.hp:
			low = c
	if lh != null:
		return lh
	# harass the enemy hero in range when healthy
	if foe != null and dist_to(foe) <= atk_range + 1.5 and hp_frac() > 0.6 and not game.is_unsafe(self, foe.p2()):
		return foe
	if low != null:
		return low
	for c in cands:
		if (c.kind == Kind.TOWER or c.kind == Kind.BASE) and game.allied_creeps_near(c.p2(), team, c.atk_range + 0.6) > 0:
			return c
	return null


# ---------------------------------------------------------------- skills
func cast(i: int) -> bool:
	if kind != Kind.HERO or dead or cds[i] > 0 or dash_t > 0:
		return false
	if i == 3 and level < 3:
		return false
	cds[i] = cd_max[i]
	var c := team_color().lightened(0.35)
	match i:
		0: # Giro: spin AoE
			var r := 3.6
			play("spin", 1.6, true)
			lock_t = 0.45
			game.fx.add_nova(position, r, c)
			for e in game.enemies_near(p2(), team, r):
				e.take_damage(110.0 + 22.0 * level, self)
		1: # Investida: dash
			var dirv := move_input if move_input.length() > 0.15 else facing
			if not is_bot and target != null and is_instance_valid(target) and not target.dead and move_input.length() <= 0.15:
				dirv = target.p2() - p2()
			dash_dir = dirv.normalized()
			face(dash_dir)
			dash_t = 0.28
			dash_hit = []
			game.fx.add_ring(position, 1.2, Color(0.85, 0.95, 1.0, 0.8), 0.4, 1.5)
			play("dash", 1.6, true)
		2: # Grito de guerra: buff + heal
			buff_t = 5.0
			hp = min(max_hp, hp + max_hp * 0.12)
			play("cheer", 1.8, true)
			lock_t = 0.35
			game.fx.add_aura(self, buff_t, Color(1.0, 0.7, 0.2))
			game.fx.add_flash(position + Vector3(0, 1.0, 0), 1.6, Color(1.0, 0.8, 0.3), 0.3)
			game.fx.add_text(position, "FÚRIA!", Color(1, 0.85, 0.3))
		3: # Julgamento: delayed big AoE in front
			ult_pos = game.clamp_world(p2() + facing * 3.5)
			ult_t = 0.7
			lock_t = 0.7
			play("ult", 1.2, true)
			game.fx.add_meteor(Vector3(ult_pos.x, 0, ult_pos.y), ult_t, 5.0)
	return true


func dash_tick(delta: float) -> void:
	dash_t -= delta
	var step := dash_dir * 26.0 * delta
	set_p2(game.clamp_world(p2() + step))
	game.fx.add_spark(position + Vector3(0, 0.8, 0), team_color().lightened(0.5), 0.4)
	for e in game.enemies_near(p2(), team, 1.4):
		if not e in dash_hit:
			dash_hit.append(e)
			e.take_damage(80.0 + 16.0 * level, self)
	if dash_t <= 0:
		play("idle")


func ult_land() -> void:
	var p := Vector3(ult_pos.x, 0, ult_pos.y)
	game.fx.add_nova(p, 5.0, Color(1.0, 0.55, 0.2), 0.6)
	game.fx.add_flash(p + Vector3(0, 1.5, 0), 2.6, Color(1.0, 0.55, 0.2), 0.3)
	for i in 3:
		var a := TAU * i / 3.0 + randf()
		game.fx.add_fire(p + Vector3(cos(a), 0, sin(a)) * 1.8, 1.3, 0.7)
	game.shake(0.35)
	for e in game.enemies_near(ult_pos, team, 5.0):
		e.take_damage(260.0 + 45.0 * level, self)


func xp_to_next() -> float:
	return 100.0 + level * 60.0


func add_xp(v: float) -> void:
	if level >= 12:
		return
	xp += v
	while level < 12 and xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		max_hp += 80
		hp += 80
		dmg += 6
		game.fx.add_ring(position, 1.5, Color(1, 0.9, 0.3), 0.8, 1.0)
		game.fx.add_text(position, "NÍVEL %d" % level, Color(1, 0.9, 0.3))


func start_respawn() -> void:
	retreating = false
	buff_t = 0
	ult_t = -1
	dash_t = 0
	deaths += 1
	jungle_camp = null
	path = PackedVector2Array()
	respawn_timer = 4.0 + level * 2.0


func respawn() -> void:
	dead = false
	visible = true
	ring.visible = true
	hp = max_hp
	set_p2(game.spawn_pos(team))
	atk_timer = 0
	add_to_group("units")
	play("idle", 1.0, true)


func reset_creep() -> void:
	dead = false
	hp = max_hp
	target = null
	pending_hit = null
	atk_timer = 0.0
	corpse_t = 0.0
	visible = true
	facing = Vector2(1, 0) if team == 0 else Vector2(-1, 0)
	if model != null:
		model.rotation.y = atan2(facing.x, facing.y)
	retarget_t = 0.0
	set_physics_process(true)
	add_to_group("units")
	if anim != null:
		anim.active = true
	play("idle", 1.0, true)
