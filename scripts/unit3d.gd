extends Node3D
## Generic 3D unit: hero, creep (melee/ranged), tower or base (ancient).
## Gameplay runs on the ground plane: Vector2(x, z).

enum Kind { HERO, CREEP, RANGED, TOWER, BASE }

const Items := preload("res://scripts/items.gd")
const TEAM_COLORS := [Color(0.3, 0.6, 1.0), Color(1.0, 0.3, 0.22), Color(1.0, 0.82, 0.3)]

var game
var team := 0
var in_brush := -1
var concealed := false
var vis := [true, true]  # seen by team 0 / team 1 (fog of war)
var reveal_t := 0.0
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
# --- loja (items)
var items: Array = [null, null, null, null, null, null]
var item_ms := 0.0
var item_as := 0.0
var item_cdr := 0.0
var item_ls := 0.0
var blink_lock := 0.0
var bkb_t := 0.0
var potion_t := 0.0
var tp_t := 0.0
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
var dash_dmg := true
var ult_t := -1.0
var ult_pos := Vector2.ZERO
var move_input := Vector2.ZERO
# Stage 4: per-hero kits and status effects
var kit := "elfo"
var stun_t := 0.0
var slow_t := 0.0
var armor_t := 0.0
var ls_t := 0.0
var hot_t := 0.0
var range_t := 0.0
var base_range := 1.0

const KITS := {
	"elfo": {"names": ["NOVA", "PISCAR", "ESCUDO", "METEORO"], "cd": [6.0, 8.0, 14.0, 45.0], "col": Color(0.45, 0.75, 1.0)},
	"elfa": {"names": ["FLECHAS", "ROLAR", "ÁGUIA", "FLECHA SAGRADA"], "cd": [7.0, 7.0, 14.0, 40.0], "col": Color(0.55, 1.0, 0.55)},
	"cavaleiro": {"names": ["ESCUDADA", "INVESTIDA", "BASTIÃO", "JULGAMENTO"], "cd": [8.0, 9.0, 16.0, 50.0], "col": Color(1.0, 0.92, 0.55)},
	"orc": {"names": ["TERREMOTO", "SALTO", "SEDE", "ESMAGAR"], "cd": [7.0, 9.0, 15.0, 45.0], "col": Color(0.95, 0.4, 0.25)},
	"orca": {"names": ["RAIO", "ESPÍRITO", "CURA", "TEMPESTADE"], "cd": [6.0, 8.0, 16.0, 45.0], "col": Color(0.6, 0.55, 1.0)},
	"barbaro": {"names": ["REDEMOINHO", "SALTO", "FÚRIA", "MACHADO"], "cd": [6.0, 9.0, 15.0, 42.0], "col": Color(1.0, 0.65, 0.2)},
	"acougueiro": {"names": ["GANCHO", "PODRIDÃO", "ESCUDO DE CARNE", "DESMEMBRAR"], "cd": [13.0, 1.0, 14.0, 40.0], "col": Color(0.9, 0.3, 0.28)},
}
## Skills that use drag-to-aim on the button (others cast on press).
const AIMED := {
	"elfo": [false, true, false, true], "elfa": [true, true, false, true], "cavaleiro": [false, true, false, false],
	"orc": [false, true, false, true], "orca": [false, true, false, true], "barbaro": [false, true, false, true],
	"acougueiro": [true, false, false, true],
}
const HOOK_RANGE := 11.0
const HOOK_SPEED := 30.0
const HOOK_BACK := 24.0

# Açougueiro: hook + devour
var hook_state := 0  # 0 idle, 1 flying out, 2 pulling back
var hook_pos := Vector2.ZERO
var hook_dir := Vector2.ZERO
var hook_len := 0.0
var hook_victim = null
var hook_chain: MultiMeshInstance3D
var hook_head: MeshInstance3D
var dev_t := 0.0
var dev_target = null
var aim_override := Vector2.ZERO
var rot_on := false
var rot_ring: MeshInstance3D
var rot_fx_t := 0.0
var flesh := 0  # Pilha de Carne stacks
const ROT_R := 3.2


func skill_range(i: int) -> float:
	if kit == "acougueiro":
		return [HOOK_RANGE, 0.0, 0.0, 3.5][i]
	if i == 1:
		return 6.5 if (kit == "elfo" or kit == "orca") else 6.0
	if i == 3:
		return 15.0 if kit == "elfa" else 4.5
	if i == 0 and kit == "elfa":
		return 4.5
	return 0.0


func set_kit(k: String) -> void:
	kit = k
	cd_max = KITS[k]["cd"].duplicate()
	base_range = atk_range


func skill_names() -> Array:
	return KITS[kit]["names"]


func kit_color() -> Color:
	return KITS[kit]["col"]
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
			hit_height = 3.0; bar_height = 8.6
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
	model.scale = cfg.get("scale_v", Vector3.ONE * cfg["scale"])
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
		sm.radius = 0.32 if kind == Kind.TOWER else 0.8
		sm.height = sm.radius * 2.6
		sm.radial_segments = 6
		sm.rings = 3
		crystal.mesh = sm
		crystal.material_override = game.fx.glow_mat(Color(team_color(), 0.95), 2.2)
		crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		crystal.position.y = 8.1 if kind == Kind.TOWER else 10.6
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
	return t != null and is_instance_valid(t) and not t.dead and t.team != team and not t.invulnerable and (team > 1 or t.vis[team])


func atk_speed_mult() -> float:
	var m := 1.0
	if buff_t > 0:
		m *= 1.6
	if ls_t > 0:
		m *= 1.35
	if range_t > 0:
		m *= 1.3
	return m * (1.0 + item_as)


func move_speed() -> float:
	var m := 1.35 if buff_t > 0 else 1.0
	if slow_t > 0:
		m *= 0.55
	return speed * m * (1.0 + item_ms)


func stun(t: float) -> void:
	if kind == Kind.TOWER or kind == Kind.BASE or dead or bkb_t > 0:
		return
	stun_t = max(stun_t, t)
	tp_t = 0.0
	hook_cancel()
	dev_t = 0.0
	if game.fx != null:
		game.fx.add_text(position, "ATORDOADO", Color(1, 1, 0.6))


func slow(t: float) -> void:
	if is_mobile() and bkb_t <= 0:
		slow_t = max(slow_t, t)


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
	slow_t -= delta
	if stun_t > 0:
		stun_t -= delta
		if kind == Kind.HERO:
			for i in 4:
				cds[i] = max(0.0, cds[i] - delta)
		return
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


func take_damage(amount: float, src, pure := false) -> void:
	if dead or invulnerable:
		return
	if src != null and is_instance_valid(src) and src.kind == Kind.HERO:
		src.reveal_t = 1.5
		src.concealed = false
	if (kind == Kind.TOWER or kind == Kind.BASE) and src != null and is_instance_valid(src) and src.kind == Kind.HERO:
		amount *= 0.6
	if armor_t > 0 and not pure:
		amount *= 0.3 if kit == "acougueiro" else 0.5
	if bkb_t > 0 and not pure:
		amount *= 0.6
	if src != null and is_instance_valid(src) and src.kind == Kind.HERO and src.item_ls > 0 and not src.dead:
		src.hp = min(src.max_hp, src.hp + amount * src.item_ls)
	if src != null and is_instance_valid(src) and src.kind == Kind.HERO and src.ls_t > 0 and not src.dead:
		src.hp = min(src.max_hp, src.hp + amount * 0.35)
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
		if src.team != team:
			Items.on_hero_damage(game, self)
	if hp <= 0:
		hp = 0
		die(src)


func die(src) -> void:
	dead = true
	hook_cancel()
	dev_t = 0.0
	set_rot(false)
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
	armor_t -= delta
	ls_t -= delta
	if range_t > 0:
		range_t -= delta
		atk_range = base_range + 2.5 if range_t > 0 else base_range
	if hot_t > 0:
		hot_t -= delta
		hp = min(max_hp, hp + max_hp * 0.05 * delta)
		for a in game.heroes:
			if a != self and a.team == team and not a.dead and a.dist_to(self) < 6.0:
				a.hp = min(a.max_hp, a.hp + a.max_hp * 0.04 * delta)
	hp = min(max_hp, hp + regen * delta)
	Items.tick(game, self, delta)
	if p2().distance_to(game.fountain_pos(team)) < game.FOUNTAIN_R:
		hp = min(max_hp, hp + max_hp * 0.12 * delta)
	if ult_t >= 0:
		ult_t -= delta
		if ult_t < 0:
			ult_land()
	if hook_state != 0:
		hook_tick(delta)
	if rot_on:
		rot_tick(delta)
	if dev_t > 0:
		devour_tick(delta)
		return
	if dash_t > 0:
		dash_tick(delta)
		return
	if is_bot:
		bot_ai(delta)
	else:
		player_ai(delta)


func player_ai(delta: float) -> void:
	if move_input.length() > 0.15:
		if tp_t > 0:
			tp_t = 0.0
			game.fx.add_text(position, "TP cancelado", Color(1, 0.5, 0.5))
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
	var foe = game.nearest_enemy_hero(self, 12.0)
	Items.bot_think(game, self, foe)
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
			if foe != null and dist_to(foe) < 5.0 and cds[1] <= 0 and kit != "acougueiro":
				facing = (home - p2()).normalized()
				cast(1)
			elif foe != null and dist_to(foe) < 3.4 and cds[0] <= 0 and kit != "acougueiro":
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
	if kit == "acougueiro" and butcher_skills(foe):
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
		elif cds[3] <= 0 and level >= 3 and dist_to(foe) < (3.0 if kit == "acougueiro" else 6.5):
			facing = (foe.p2() - p2()).normalized()
			cast(3)
			react_t = 0.5
		elif cds[1] <= 0 and kit != "acougueiro" and foe.hp_frac() < 0.4 and dist_to(foe) > 3.0 and not game.is_unsafe(self, foe.p2()):
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
	if kind != Kind.HERO or dead or cds[i] > 0 or dash_t > 0 or stun_t > 0 or dev_t > 0:
		aim_override = Vector2.ZERO
		return false
	if i == 3 and level < 3:
		return false
	cds[i] = cd_max[i] * (1.0 - item_cdr)
	var c := kit_color()
	var lv := float(level)
	var aim := _aim_dir()
	match i:
		0:
			_cast_q(c, lv, aim)
		1:
			_cast_w(c, lv, aim)
		2:
			_cast_e(c, lv)
		3:
			_cast_r(c, lv, aim)
	return true


func _aim_dir() -> Vector2:
	if aim_override.length() > 0.01:
		var a := aim_override.normalized()
		aim_override = Vector2.ZERO
		return a
	var d := move_input if move_input.length() > 0.15 else facing
	if not is_bot and move_input.length() <= 0.15 and target != null and is_instance_valid(target) and not target.dead:
		d = target.p2() - p2()
	if is_bot and target != null and is_instance_valid(target) and not target.dead:
		d = target.p2() - p2()
	if d.length() < 0.01:
		d = facing
	return d.normalized()


func _hit_area(center: Vector2, r: float, dmg_v: float) -> Array:
	var hit: Array = game.enemies_near(center, team, r)
	for e in hit:
		e.take_damage(dmg_v, self)
	return hit


func _dash(d: Vector2, t: float, dmg_hit := true) -> void:
	dash_dir = d
	face(d)
	dash_t = t
	dash_hit = []
	dash_dmg = dmg_hit
	game.fx.add_ring(position, 1.2, Color(0.85, 0.95, 1.0, 0.8), 0.4, 1.5)
	play("dash", 1.6, true)


func _blink(d: Vector2, dist: float, c: Color) -> void:
	face(d)
	game.fx.add_flash(position + Vector3(0, 1.0, 0), 1.4, c, 0.3)
	game.fx.add_ring(position, 1.4, c, 0.35, 1.2)
	var dest: Vector2 = game.clamp_world(p2() + d * dist)
	set_p2(dest)
	game.fx.add_flash(position + Vector3(0, 1.0, 0), 1.6, c, 0.35)
	game.fx.add_ring(position, 1.6, c, 0.4, 1.4)
	play("dash", 1.6, true)
	lock_t = 0.15


func _cast_q(c: Color, lv: float, aim: Vector2) -> void:
	match kit:
		"acougueiro":
			hook_throw(aim)
		"elfo", "barbaro":
			var r := 3.6
			play("spin", 1.6, true)
			lock_t = 0.45
			game.fx.add_nova(position, r, c)
			_hit_area(p2(), r, 110.0 + 22.0 * lv)
		"elfa":
			var at: Vector2 = game.clamp_world(p2() + aim * 4.5)
			play("ult", 1.8, true)
			lock_t = 0.35
			face(aim)
			var p := Vector3(at.x, 0, at.y)
			game.fx.add_ring(p, 3.2, c, 0.6, 0.0)
			for k in 4:
				var o := Vector2(randf_range(-2, 2), randf_range(-2, 2))
				game.fx.add_spark(p + Vector3(o.x, 0.6, o.y), c, 0.7)
			for e in _hit_area(at, 3.2, 95.0 + 20.0 * lv):
				e.slow(2.0)
		"cavaleiro":
			var r := 2.8
			play("spin", 1.6, true)
			lock_t = 0.4
			game.fx.add_nova(position, r, c)
			game.shake(0.15)
			for e in _hit_area(p2(), r, 80.0 + 16.0 * lv):
				e.stun(1.1)
		"orc":
			var r := 4.0
			play("ult", 1.6, true)
			lock_t = 0.45
			game.fx.add_nova(position, r, c)
			game.fx.add_ring(position, r, Color(0.6, 0.45, 0.3), 0.6, 0.2)
			game.shake(0.2)
			for e in _hit_area(p2(), r, 90.0 + 18.0 * lv):
				e.slow(2.5)
		"orca":
			# chain lightning: up to 3 enemies, each jump from the last
			play("ult", 1.8, true)
			lock_t = 0.3
			var from := p2()
			var hit: Array = []
			var d := 115.0 + 22.0 * lv
			for k in 3:
				var best = null
				for e in game.enemies_near(from, team, 6.0 if k == 0 else 4.5):
					if e in hit:
						continue
					if best == null or e.p2().distance_to(from) < best.p2().distance_to(from):
						best = e
				if best == null:
					break
				hit.append(best)
				game.fx.add_beam(best.position, 0.5, c, 0.3)
				game.fx.add_flash(best.position + Vector3(0, 1.0, 0), 1.0, c, 0.25)
				best.take_damage(d, self)
				d *= 0.8
				from = best.p2()
			if hit.is_empty():
				cds[0] = 1.0


func _cast_w(c: Color, lv: float, aim: Vector2) -> void:
	match kit:
		"acougueiro":
			set_rot(not rot_on)
		"elfo":
			_blink(aim, 6.5, c)
		"orca":
			_blink(aim, 6.0, c)
			armor_t = max(armor_t, 1.5)
		"elfa":
			_dash(aim, 0.22, false)
			buff_t = max(buff_t, 1.5)
		_:
			_dash(aim, 0.28, true)


func _cast_e(c: Color, lv: float) -> void:
	lock_t = 0.35
	match kit:
		"acougueiro":
			armor_t = 4.0 + 0.2 * lv
			play("cheer", 1.6, true)
			game.fx.add_aura(self, armor_t, Color(0.95, 0.35, 0.3))
			game.fx.add_flash(position + Vector3(0, 1.2, 0), 1.6, Color(1.0, 0.45, 0.35), 0.3)
			game.fx.add_text(position, "ESCUDO DE CARNE!", Color(1, 0.6, 0.5))
		"elfo":
			armor_t = 4.0
			hp = min(max_hp, hp + max_hp * 0.08)
			play("cheer", 1.8, true)
			game.fx.add_aura(self, 4.0, c)
			game.fx.add_text(position, "ESCUDO!", c.lightened(0.3))
		"elfa":
			range_t = 6.0
			atk_range = base_range + 2.5
			play("cheer", 1.8, true)
			game.fx.add_aura(self, 6.0, c)
			game.fx.add_text(position, "OLHO DE ÁGUIA!", c.lightened(0.3))
		"cavaleiro":
			armor_t = 5.0
			hp = min(max_hp, hp + max_hp * 0.1)
			play("cheer", 1.8, true)
			game.fx.add_aura(self, 5.0, c)
			game.fx.add_text(position, "BASTIÃO!", c)
			for e in game.enemies_near(p2(), team, 5.0):
				if e.kind == Kind.HERO or e.kind == Kind.CREEP or e.kind == Kind.RANGED:
					e.target = self
		"orc":
			ls_t = 6.0
			play("cheer", 1.8, true)
			game.fx.add_aura(self, 6.0, Color(0.9, 0.15, 0.15))
			game.fx.add_text(position, "SEDE DE SANGUE!", Color(1, 0.35, 0.3))
		"orca":
			hot_t = 5.0
			play("cheer", 1.8, true)
			game.fx.add_aura(self, 5.0, Color(0.4, 1.0, 0.6))
			game.fx.add_ring(position, 6.0, Color(0.4, 1.0, 0.6), 0.8, 0.0)
			game.fx.add_text(position, "CURA!", Color(0.5, 1, 0.6))
		_:
			buff_t = 5.0
			hp = min(max_hp, hp + max_hp * 0.12)
			play("cheer", 1.8, true)
			game.fx.add_aura(self, buff_t, Color(1.0, 0.7, 0.2))
			game.fx.add_flash(position + Vector3(0, 1.0, 0), 1.6, Color(1.0, 0.8, 0.3), 0.3)
			game.fx.add_text(position, "FÚRIA!", Color(1, 0.85, 0.3))


func _cast_r(c: Color, lv: float, aim: Vector2) -> void:
	face(aim)
	match kit:
		"acougueiro":
			# grab the closest enemy in front and chew on it: stun + damage over time, heals
			var at: Vector2 = p2() + aim * 1.5
			var best = null
			for e in game.enemies_near(at, team, 2.6):
				if not (e.kind == Kind.HERO or e.kind == Kind.CREEP or e.kind == Kind.RANGED):
					continue
				var sc: float = e.p2().distance_to(at) - (2.0 if e.kind == Kind.HERO else 0.0)
				if best == null or sc < best[0]:
					best = [sc, e]
			if best == null:
				cds[3] = 1.0
				game.fx.add_text(position, "NINGUÉM PERTO", Color(1, 1, 1, 0.8))
				return
			dev_target = best[1]
			dev_t = 2.4
			face(dev_target.p2() - p2())
			play("ult", 1.0, true)
			game.fx.add_flash(dev_target.position + Vector3(0, 1.0, 0), 1.6, Color(0.8, 0.05, 0.05), 0.4)
			game.fx.add_text(dev_target.position, "DESMEMBRAR!", Color(1, 0.3, 0.3))
			game.shake(0.25)
		"elfo", "orca":
			ult_pos = game.clamp_world(p2() + aim * 3.5)
			ult_t = 0.7
			lock_t = 0.7
			play("ult", 1.2, true)
			if kit == "elfo":
				game.fx.add_meteor(Vector3(ult_pos.x, 0, ult_pos.y), ult_t, 5.0)
			else:
				game.fx.add_ring(Vector3(ult_pos.x, 0, ult_pos.y), 5.0, c, ult_t, 0.0)
		"elfa":
			# long piercing arrow along the aim line
			play("ult", 1.4, true)
			lock_t = 0.4
			var hit: Array = []
			var s := 1.5
			while s <= 15.0:
				var q: Vector2 = p2() + aim * s
				if s < 14.0:
					game.fx.add_spark(Vector3(q.x, 1.1, q.y), c.lightened(0.4), 0.9)
				for e in game.enemies_near(q, team, 1.6):
					if not e in hit:
						hit.append(e)
						e.take_damage(240.0 + 40.0 * lv, self)
						e.stun(0.8)
				s += 1.5
			game.fx.add_flash(position + Vector3(aim.x * 2, 1.1, aim.y * 2), 1.8, c, 0.3)
		"cavaleiro":
			play("ult", 1.2, true)
			lock_t = 0.5
			game.fx.add_beam(position, 2.4, c, 0.7)
			game.fx.add_nova(position, 5.0, c, 0.6)
			game.shake(0.3)
			_hit_area(p2(), 5.0, 200.0 + 35.0 * lv)
			for a in game.heroes:
				if a.team == team and not a.dead and a.dist_to(self) < 7.0:
					a.hp = min(a.max_hp, a.hp + a.max_hp * 0.3)
					game.fx.add_flash(a.position + Vector3(0, 1.2, 0), 1.2, Color(1, 1, 0.7), 0.4)
		"orc":
			play("ult", 1.3, true)
			lock_t = 0.5
			var at: Vector2 = game.clamp_world(p2() + aim * 2.5)
			var p := Vector3(at.x, 0, at.y)
			game.fx.add_nova(p, 5.5, c, 0.6)
			game.fx.add_ring(p, 5.5, Color(0.55, 0.4, 0.3), 0.7, 0.1)
			for k in 3:
				var ang := TAU * k / 3.0
				game.fx.add_fire(p + Vector3(cos(ang), 0, sin(ang)) * 2.0, 1.1, 0.6)
			game.shake(0.4)
			for e in _hit_area(at, 5.5, 220.0 + 40.0 * lv):
				e.stun(1.3)
		"barbaro":
			# huge cleave in front
			play("spin", 1.3, true)
			lock_t = 0.45
			var at: Vector2 = game.clamp_world(p2() + aim * 3.0)
			var p := Vector3(at.x, 0, at.y)
			game.fx.add_nova(p, 4.2, c, 0.5)
			game.fx.add_flash(p + Vector3(0, 1.0, 0), 2.2, c, 0.3)
			game.shake(0.35)
			for e in _hit_area(at, 4.2, 300.0 + 45.0 * lv):
				e.slow(2.0)


func dash_tick(delta: float) -> void:
	dash_t -= delta
	var step := dash_dir * 26.0 * delta
	set_p2(game.clamp_world(p2() + step))
	game.fx.add_spark(position + Vector3(0, 0.8, 0), team_color().lightened(0.5), 0.4)
	for e in (game.enemies_near(p2(), team, 1.4) if dash_dmg else []):
		if not e in dash_hit:
			dash_hit.append(e)
			e.take_damage(80.0 + 16.0 * level, self)
	if dash_t <= 0:
		play("idle")


func ult_land() -> void:
	var p := Vector3(ult_pos.x, 0, ult_pos.y)
	var col := Color(1.0, 0.55, 0.2) if kit != "orca" else kit_color()
	game.fx.add_nova(p, 5.0, col, 0.6)
	game.fx.add_flash(p + Vector3(0, 1.5, 0), 2.6, col, 0.3)
	if kit == "orca":
		for i in 3:
			var a := TAU * i / 3.0 + randf()
			game.fx.add_beam(p + Vector3(cos(a), 0, sin(a)) * 2.0, 0.6, col, 0.35)
	else:
		for i in 3:
			var a := TAU * i / 3.0 + randf()
			game.fx.add_fire(p + Vector3(cos(a), 0, sin(a)) * 1.8, 1.3, 0.7)
	game.shake(0.35)
	for e in game.enemies_near(ult_pos, team, 5.0):
		e.take_damage(260.0 + 45.0 * level, self)
		if kit == "orca":
			e.slow(2.5)


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
	stun_t = 0.0
	slow_t = 0.0
	potion_t = 0.0
	tp_t = 0.0
	bkb_t = 0.0
	set_p2(game.spawn_pos(team))
	atk_timer = 0
	add_to_group("units")
	play("idle", 1.0, true)


func reset_creep() -> void:
	dead = false
	hp = max_hp
	stun_t = 0.0
	slow_t = 0.0
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


# ---------------------------------------------------------------- Açougueiro hook
func hook_throw(aim: Vector2) -> void:
	face(aim)
	hook_dir = aim.normalized()
	hook_len = 0.6
	hook_pos = p2() + hook_dir * hook_len
	hook_victim = null
	hook_state = 1
	lock_t = 0.3
	if game.autotest:
		print("  HOOK THROW t=%d by=%s" % [game.game_time, hero_name])
	play("hook", 1.6, true)
	_hook_visual(true)


func hook_cancel() -> void:
	if hook_state == 0:
		return
	hook_state = 0
	hook_victim = null
	_hook_visual(false)


## First living unit (any team, not structures) touching the hook between a and b.
func _hook_hit(a: Vector2, b: Vector2):
	var best = null
	var bt := INF
	var ab := b - a
	var l2 := ab.length_squared()
	for o in game.units:
		if o == self or o.dead or not o.is_mobile() or o.invulnerable:
			continue
		var op: Vector2 = o.p2()
		var t: float = clamp((op - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0001 else 0.0
		var r: float = o.radius + 0.45
		if op.distance_squared_to(a + ab * t) < r * r and t < bt:
			bt = t
			best = o
	return best


func hook_tick(delta: float) -> void:
	var me := p2()
	if hook_state == 1:
		var prev := hook_pos
		hook_len = min(HOOK_RANGE, hook_len + HOOK_SPEED * delta)
		hook_pos = me + hook_dir * hook_len
		var hit = _hook_hit(prev, hook_pos)
		if hit != null:
			hook_victim = hit
			if game.autotest:
				print("  HOOK HIT t=%d by=%s victim_kind=%d ally=%s" % [game.game_time, hero_name, hit.kind, hit.team == team])
			hook_pos = hit.p2()
			hook_state = 2
			var hp3 := Vector3(hook_pos.x, hit.hit_height, hook_pos.y)
			if hit.team != team:
				hit.take_damage(120.0 + 25.0 * level, self, true)
				game.fx.add_flash(hp3, 1.3, Color(0.9, 0.1, 0.1), 0.3)
				game.fx.add_text(hit.position, "FISGADO!", Color(1, 0.45, 0.35))
				game.shake(0.15)
			else:
				game.fx.add_flash(hp3, 1.3, Color(0.5, 1.0, 0.6), 0.3)
				game.fx.add_text(hit.position, "RESGATE!", Color(0.6, 1, 0.6))
			if hit.kind == Kind.HERO:
				hit.dash_t = 0.0
				hit.hook_cancel()
		elif hook_len >= HOOK_RANGE:
			hook_state = 2
	elif hook_state == 2:
		var v = hook_victim
		if v != null and (not is_instance_valid(v) or v.dead):
			v = null
			hook_victim = null
		var d := me - hook_pos
		var stop: float = radius + (v.radius if v != null else 0.0) + 0.25
		var step := HOOK_BACK * delta
		if d.length() <= stop + step:
			if v != null:
				v.set_p2(game.clamp_world(me - d.normalized() * stop) if d.length() > 0.01 else v.p2())
				if v.team != team:
					v.stun(0.5)
			hook_state = 0
			hook_victim = null
			_hook_visual(false)
			return
		hook_pos += d.normalized() * step
		if v != null:
			v.set_p2(game.clamp_world(hook_pos))
			v.stun_t = max(v.stun_t, 0.12)
			v.face(d)
	_hook_draw()


func _hook_visual(on: bool) -> void:
	if on and hook_chain == null:
		var link := TorusMesh.new()
		link.inner_radius = 0.07
		link.outer_radius = 0.15
		link.rings = 6
		link.ring_segments = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.42, 0.42, 0.45)
		mat.metallic = 0.7
		mat.roughness = 0.35
		link.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = link
		mm.instance_count = 72
		hook_chain = MultiMeshInstance3D.new()
		hook_chain.multimesh = mm
		hook_chain.top_level = true
		hook_chain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(hook_chain)
		hook_head = MeshInstance3D.new()
		var hm := TorusMesh.new()
		hm.inner_radius = 0.22
		hm.outer_radius = 0.38
		hm.rings = 8
		hm.ring_segments = 5
		var hmat := mat.duplicate()
		hmat.albedo_color = Color(0.7, 0.68, 0.66)
		hm.material = hmat
		hook_head.mesh = hm
		var tip := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.22, 0.45, 0.08)
		pm.material = hmat
		tip.mesh = pm
		tip.position = Vector3(0.3, 0.0, 0.18)
		tip.rotation_degrees = Vector3(90, 0, 0)
		hook_head.add_child(tip)
		hook_head.top_level = true
		hook_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(hook_head)
	if hook_chain != null:
		hook_chain.visible = on
		hook_head.visible = on
		if on:
			_hook_draw()


func _hook_draw() -> void:
	if hook_chain == null:
		return
	var a := Vector3(position.x, 1.25, position.z) + Vector3(facing.x, 0, facing.y) * 0.5
	var b := Vector3(hook_pos.x, 1.0, hook_pos.y)
	var d := b - a
	var l := d.length()
	var fwd := d / l if l > 0.01 else Vector3(facing.x, 0, facing.y)
	var side := fwd.cross(Vector3.UP).normalized()
	var up := side.cross(fwd).normalized()
	var mm := hook_chain.multimesh
	var n: int = mini(mm.instance_count, int(l / 0.24) + 1)
	mm.visible_instance_count = n
	for i in n:
		var p := a + fwd * (0.24 * i)
		var bs := Basis(fwd * 1.5, up, side) if i % 2 == 0 else Basis(fwd * 1.5, side, -up)
		mm.set_instance_transform(i, Transform3D(bs, p))
	hook_head.global_transform = Transform3D(Basis(fwd, side, -up), b + fwd * 0.2)


func devour_tick(delta: float) -> void:
	dev_t -= delta
	var t = dev_target
	if t == null or not is_instance_valid(t) or t.dead or dist_to(t) > 4.5 or (not is_bot and move_input.length() > 0.6):
		dev_t = 0.0
		dev_target = null
		play("idle")
		return
	face(t.p2() - p2())
	t.stun_t = max(t.stun_t, 0.15)
	var d: float = (115.0 + 20.0 * level) * delta
	t.take_damage(d, self)
	hp = min(max_hp, hp + d * 0.5)
	if int(dev_t * 10.0) % 4 == 0 and int((dev_t + delta) * 10.0) % 4 != 0:
		game.fx.add_spark(t.position + Vector3(0, t.hit_height, 0), Color(0.85, 0.05, 0.05), 0.6)
		play("attack", 1.4, true)
	if dev_t <= 0:
		dev_target = null
		play("idle")


## Bot Açougueiro: hook (clear line) an enemy hero or a dying ally, rot when enemies are close,
## flesh shield when hurt in a fight, dismember an adjacent hero. Always handles its own skills.
func butcher_skills(foe) -> bool:
	var close: Array = game.enemies_near(p2(), team, ROT_R)
	var want_rot := false
	for e in close:
		if e.kind == Kind.HERO or (e.team != 2 and close.size() >= 2) or jungle_camp != null:
			want_rot = true
	if hp_frac() < 0.25:
		want_rot = false
	if want_rot != rot_on and cds[1] <= 0:
		cast(1)
		react_t = 0.2
		return true
	if foe != null and dist_to(foe) < 6.0 and cds[2] <= 0 and hp_frac() < 0.7:
		cast(2)
		react_t = 0.3
		return true
	if foe != null and cds[3] <= 0 and level >= 3 and dist_to(foe) < 3.0:
		aim_override = (foe.p2() - p2()).normalized()
		cast(3)
		react_t = 0.5
		return true
	if cds[0] > 0 or hook_state != 0:
		return true
	var cand = null
	if foe != null:
		var d := dist_to(foe)
		if d > 3.0 and d < HOOK_RANGE - 0.5 and (foe.hp_frac() < 0.7 or hp_frac() > 0.5):
			cand = foe
	if cand == null:
		for a in game.heroes:
			if a != self and a.team == team and not a.dead and a.hp_frac() < 0.25 and dist_to(a) > 4.0 and dist_to(a) < HOOK_RANGE - 0.5 \
					and game.heroes_near(a.p2(), 1 - team, 6.0) > 0:
				cand = a
				break
	if cand == null:
		return true
	var aim: Vector2 = cand.p2() - p2()
	if cand.cur_anim == cand.anims.get("run", "-"):
		aim += cand.facing * cand.move_speed() * aim.length() / HOOK_SPEED * 0.8
	var first = _hook_hit(p2() + aim.normalized() * 0.6, p2() + aim.normalized() * min(aim.length() + 1.0, HOOK_RANGE))
	if first != cand:
		return true
	aim_override = aim.normalized()
	if cast(0):
		react_t = 0.4
	return true


# ---------------------------------------------------------------- Açougueiro rot + flesh heap
func set_rot(on: bool) -> void:
	rot_on = on
	if on and rot_ring == null:
		rot_ring = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2, 2)
		rot_ring.mesh = pm
		rot_ring.material_override = game.fx.ground_ring_mat(Color(0.45, 0.85, 0.2, 0.75), 0.22, 0.12)
		rot_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rot_ring.scale = Vector3(ROT_R, 1, ROT_R)
		rot_ring.position.y = 0.07
		add_child(rot_ring)
	if rot_ring != null:
		rot_ring.visible = on
	if on and game.fx != null:
		game.fx.add_text(position, "PODRIDÃO", Color(0.6, 1, 0.35))


func rot_tick(delta: float) -> void:
	var d: float = (30.0 + 6.0 * level) * delta
	for e in game.enemies_near(p2(), team, ROT_R):
		if e.kind == Kind.TOWER or e.kind == Kind.BASE:
			continue
		e.take_damage(d, self)
		e.slow(0.3)
	hp = max(1.0, hp - 8.0 * delta)
	rot_fx_t -= delta
	if rot_fx_t <= 0:
		rot_fx_t = 0.35
		var a := randf() * TAU
		game.fx.add_spark(position + Vector3(cos(a) * 1.6, 0.5, sin(a) * 1.6), Color(0.5, 0.9, 0.2), 0.7)
	if rot_ring != null:
		rot_ring.rotation.y += delta * 0.8


## Pilha de Carne: an enemy hero dying near the butcher (or by his hand) feeds him for good.
func flesh_feed() -> void:
	flesh += 1
	if game.autotest:
		print("  FLESH %s stacks=%d" % [hero_name, flesh + 0])
	max_hp += 40
	hp += 40
	dmg += 4
	game.fx.add_text(position, "PILHA DE CARNE +1", Color(1, 0.75, 0.4))
	game.fx.add_ring(position, 1.6, Color(1.0, 0.6, 0.3), 0.6, 1.0)
