extends Node3D
## MOBA prototype 3D: one lane, player hero vs bot hero, creep waves, towers, bases.

const Unit := preload("res://scripts/unit3d.gd")
const FxScript := preload("res://scripts/fx3d.gd")
const HudScript := preload("res://scripts/hud.gd")

const LANE_LEN := 100.0
const LANE_HALF := 6.0
const FOUNTAIN_R := 11.0
const WAVE_INTERVAL := 30.0
const RIVER_X := 50.0

var cfgs := {}
var heroes: Array = [null, null]
var player
var bot
var bases: Array = [null, null]
var towers: Array = [[], []]
var fx
var hud
var cam: Camera3D
var cam_focus := Vector3.ZERO
var shake_t := 0.0
var wave_timer := 3.0
var wave_count := 0
var game_time := 0.0
var game_over := false
var autotest := false
var shot_mode := ""
var hud_texts: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	autotest = "--autotest" in args
	for a in args:
		if a.begins_with("--shot="):
			shot_mode = a.substr(7)
	load_configs()
	fx = FxScript.new()
	fx.game = self
	fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(fx)
	build_world()

	bases[0] = make_unit(Unit.Kind.BASE, 0, Vector2(4.5, 0))
	bases[1] = make_unit(Unit.Kind.BASE, 1, Vector2(LANE_LEN - 4.5, 0))
	var tpos := [[Vector2(34, -3.2), Vector2(18, 3.2)], [Vector2(LANE_LEN - 34, 3.2), Vector2(LANE_LEN - 18, -3.2)]]
	for team in 2:
		for i in 2:
			var t = make_unit(Unit.Kind.TOWER, team, tpos[team][i])
			t.tier = i + 1
			towers[team].append(t)

	player = make_unit(Unit.Kind.HERO, 0, spawn_pos(0), true)
	player.is_bot = autotest and not ("--afk" in args)
	player.hero_name = "Mago"
	bot = make_unit(Unit.Kind.HERO, 1, spawn_pos(1))
	bot.is_bot = true
	bot.hero_name = "Bárbaro"
	heroes = [player, bot]

	cam = Camera3D.new()
	cam.fov = 42.0
	cam.far = 200.0
	add_child(cam)
	cam.make_current()
	cam_focus = player.position
	update_camera(1.0)

	hud = HudScript.new()
	hud.game = self
	add_child(hud)
	update_invulnerability()
	if autotest:
		Engine.time_scale = 4.0
	if shot_mode != "":
		setup_shot()


func load_configs() -> void:
	var hero_anims := {"idle": "Idle", "run": "Running_A", "attack": "1H_Melee_Attack_Chop", "death": "Death_A",
		"spin": "2H_Melee_Attack_Spin", "dash": "Dodge_Forward", "cheer": "Cheer", "ult": "2H_Melee_Attack_Chop"}
	var mage_anims := hero_anims.duplicate()
	mage_anims["attack"] = "Spellcast_Shoot"
	mage_anims["ult"] = "Spellcast_Raise"
	var barb_anims := hero_anims.duplicate()
	barb_anims["attack"] = "2H_Melee_Attack_Chop"
	barb_anims["idle"] = "2H_Melee_Idle"
	cfgs["hero0"] = {"scene": load("res://assets/chars/Mage.glb"), "scale": 1.0,
		"hide": ["Spellbook", "Spellbook_open", "1H_Wand"], "anims": mage_anims}
	cfgs["hero1"] = {"scene": load("res://assets/chars/Barbarian.glb"), "scale": 1.05,
		"hide": ["1H_Axe_Offhand", "Barbarian_Round_Shield", "1H_Axe", "Mug"], "anims": barb_anims}
	cfgs["creep0"] = {"scene": load("res://assets/chars/Knight.glb"), "scale": 0.66,
		"hide": ["1H_Sword_Offhand", "Badge_Shield", "Rectangle_Shield", "Spike_Shield", "2H_Sword"],
		"anims": {"idle": "Idle", "run": "Running_A", "attack": "1H_Melee_Attack_Chop", "death": "Death_A"}}
	cfgs["creep1"] = {"scene": load("res://assets/chars/Skeleton_Minion.glb"), "scale": 0.74, "hide": [],
		"anims": {"idle": "Idle", "run": "Running_A", "attack": "Unarmed_Melee_Attack_Punch_A", "death": "Death_A"}}
	cfgs["ranged0"] = {"scene": load("res://assets/chars/Rogue.glb"), "scale": 0.66,
		"hide": ["Knife", "Knife_Offhand", "2H_Crossbow", "Throwable"],
		"anims": {"idle": "Idle", "run": "Running_A", "attack": "1H_Ranged_Shoot", "death": "Death_A"}}
	cfgs["ranged1"] = {"scene": load("res://assets/chars/Skeleton_Mage.glb"), "scale": 0.72, "hide": [],
		"anims": {"idle": "Idle", "run": "Running_A", "attack": "Spellcast_Shoot", "death": "Death_A"}}
	cfgs["tower0"] = {"scene": load("res://assets/env/building_tower_A_blue.gltf"), "scale": 3.1}
	cfgs["tower1"] = {"scene": load("res://assets/env/building_tower_A_red.gltf"), "scale": 3.1}
	cfgs["base0"] = {"scene": load("res://assets/env/building_castle_blue.gltf"), "scale": 2.4}
	cfgs["base1"] = {"scene": load("res://assets/env/building_castle_red.gltf"), "scale": 2.4}


func make_unit(kind: int, team: int, pos: Vector2, is_player := false):
	var u = Unit.new()
	u.game = self
	u.team = team
	u.kind = kind
	u.is_player = is_player
	u.position = Vector3(pos.x, 0, pos.y)
	u.process_mode = Node.PROCESS_MODE_PAUSABLE
	var key: String = ["hero", "creep", "ranged", "tower", "base"][kind] + str(team)
	add_child(u)
	u.setup(cfgs[key])
	u.add_to_group("units")
	if kind == Unit.Kind.TOWER or kind == Unit.Kind.BASE:
		u.model.rotation.y = PI / 6.0
	return u


func spawn_pos(team: int) -> Vector2:
	return Vector2(9.0 if team == 0 else LANE_LEN - 9.0, 0)


func clamp_world(p: Vector2) -> Vector2:
	return Vector2(clamp(p.x, 1.0, LANE_LEN - 1.0), clamp(p.y, -LANE_HALF - 0.5, LANE_HALF + 0.5))


# ---------------------------------------------------------------- world
func noise_tex(c1: Color, c2: Color, freq: float, seed_v: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 4
	var g := Gradient.new()
	g.set_color(0, c1)
	g.set_color(1, c2)
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	t.color_ramp = g
	return t


func plane(size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.13, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.18, 0.16)
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_bias = 0.05
	add_child(sun)

	# grass
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = noise_tex(Color(0.13, 0.27, 0.12), Color(0.24, 0.42, 0.17), 0.02, 3)
	gm.uv1_scale = Vector3(14, 8, 1)
	gm.roughness = 1.0
	plane(Vector2(LANE_LEN + 80, 90), Vector3(LANE_LEN / 2, 0, 0), gm)
	# lane (two halves, bridge in the middle)
	var lm := StandardMaterial3D.new()
	lm.albedo_texture = noise_tex(Color(0.33, 0.26, 0.18), Color(0.5, 0.41, 0.29), 0.03, 9)
	lm.uv1_scale = Vector3(10, 1.3, 1)
	lm.roughness = 0.95
	var half := RIVER_X - 3.5
	plane(Vector2(half, LANE_HALF * 2 + 1.0), Vector3(half / 2, 0.02, 0), lm)
	plane(Vector2(half, LANE_HALF * 2 + 1.0), Vector3(LANE_LEN - half / 2, 0.02, 0), lm)
	# river
	var rm := StandardMaterial3D.new()
	rm.albedo_texture = noise_tex(Color(0.1, 0.3, 0.5), Color(0.25, 0.55, 0.75), 0.05, 21)
	rm.uv1_scale = Vector3(1, 6, 1)
	rm.metallic = 0.3
	rm.roughness = 0.15
	rm.emission_enabled = true
	rm.emission = Color(0.05, 0.12, 0.2)
	var river := plane(Vector2(7.0, 90), Vector3(RIVER_X, 0.01, 0), rm)
	river.set_meta("water", true)
	# bridge
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = noise_tex(Color(0.33, 0.22, 0.13), Color(0.48, 0.33, 0.2), 0.12, 5)
	wood.uv1_scale = Vector3(1, 4, 1)
	for i in 9:
		var plank := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.75, 0.18, LANE_HALF * 2 + 0.6)
		plank.mesh = bm
		plank.material_override = wood
		plank.position = Vector3(RIVER_X - 3.5 + 0.4 + i * 0.78, 0.06, 0)
		add_child(plank)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.45, 0.48)
	stone.roughness = 0.9
	for side in [-1, 1]:
		var rail := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(7.4, 0.6, 0.4)
		rail.mesh = rb
		rail.material_override = stone
		rail.position = Vector3(RIVER_X, 0.3, side * (LANE_HALF + 0.5))
		add_child(rail)
		for px in [RIVER_X - 3.7, RIVER_X + 3.7]:
			var post := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(0.8, 1.4, 0.8)
			post.mesh = pb
			post.material_override = stone
			post.position = Vector3(px, 0.7, side * (LANE_HALF + 0.5))
			add_child(post)
			var torch := OmniLight3D.new()
			torch.light_color = Color(1.0, 0.6, 0.25)
			torch.light_energy = 1.4
			torch.omni_range = 5.0
			torch.position = post.position + Vector3(0, 1.1, 0)
			add_child(torch)
			fx.add_child(_flame(torch.position))
	# fountains
	for team in 2:
		var fm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = FOUNTAIN_R
		cm.bottom_radius = FOUNTAIN_R
		cm.height = 0.02
		cm.radial_segments = 48
		fm.mesh = cm
		fm.material_override = FxScript.glow_mat(Color(Unit.TEAM_COLORS[team], 0.12), 1.0)
		fm.position = Vector3(4.5 if team == 0 else LANE_LEN - 4.5, 0.035, 0)
		add_child(fm)
	scatter_props()


func _flame(p: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.5
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = FxScript.glow_mat(Color(1.0, 0.55, 0.15, 0.95), 3.0)
	mi.position = p - Vector3(0, 0.3, 0)
	return mi


func first_mesh(path: String) -> Array:
	var n: Node = load(path).instantiate()
	var out: Array = []
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D()
		var x: Node = mi
		while x != n and x != null:
			t = x.transform * t
			x = x.get_parent()
		out.append([mi.mesh, t])
	n.free()
	return out


func multimesh(path: String, xforms: Array) -> void:
	for part in first_mesh(path):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i] * part[1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


func scatter_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var groups := {
		"res://assets/env/trees_A_large.gltf": [], "res://assets/env/trees_B_large.gltf": [],
		"res://assets/env/trees_A_medium.gltf": [], "res://assets/env/tree_single_A.gltf": [],
		"res://assets/env/tree_single_B.gltf": [], "res://assets/env/rock_single_A.gltf": [],
		"res://assets/env/rock_single_B.gltf": [], "res://assets/env/rock_single_C.gltf": []}
	var keys := groups.keys()
	var x := -14.0
	while x < LANE_LEN + 14.0:
		for side in [-1, 1]:
			var z: float = side * rng.randf_range(LANE_HALF + 2.8, LANE_HALF + 5.0)
			for row in 3:
				if abs(x - RIVER_X) < 5.0:
					continue
				var k: String = keys[rng.randi_range(0, 4)]
				var s := rng.randf_range(2.6, 3.6) if k.contains("trees_") else rng.randf_range(3.6, 5.0)
				var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x + rng.randf_range(-1.5, 1.5), 0, z + side * row * 6.0))
				groups[k].append(t)
		x += rng.randf_range(3.0, 4.6)
	# rocks along the lane edge
	x = 2.0
	while x < LANE_LEN - 2.0:
		if abs(x - RIVER_X) > 4.5:
			for side in [-1, 1]:
				if rng.randf() < 0.55:
					var k: String = keys[rng.randi_range(5, 7)]
					var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(4.0, 7.0)), Vector3(x, 0, side * (LANE_HALF + 1.2 + rng.randf() * 0.8)))
					groups[k].append(t)
		x += rng.randf_range(2.0, 4.0)
	for k in groups:
		if groups[k].size() > 0:
			multimesh(k, groups[k])


# ---------------------------------------------------------------- loop
func _physics_process(delta: float) -> void:
	var portrait: bool = hud.is_portrait()
	if not game_over and shot_mode == "":
		get_tree().paused = portrait
	if game_over or (portrait and shot_mode == ""):
		return
	game_time += delta
	wave_timer -= delta
	if wave_timer <= 0:
		spawn_wave()
		wave_timer = WAVE_INTERVAL
	for h in heroes:
		h.gold += 1.5 * delta
	separation()
	if autotest and int(game_time * 60) % 1800 == 0:
		print("t=%d blue_towers=%d red_towers=%d baseHP=%d/%d p_lvl=%d bot_lvl=%d kills=%d/%d units=%d" % [game_time, towers[0].size(), towers[1].size(), bases[0].hp, bases[1].hp, player.level, bot.level, player.kills, bot.kills, get_tree().get_nodes_in_group("units").size()])
		if game_time > 1500:
			print("TIMEOUT")
			get_tree().quit()


func _process(delta: float) -> void:
	update_camera(delta)
	var keep: Array = []
	for t in hud_texts:
		t["t"] += delta
		if t["t"] < t["dur"]:
			keep.append(t)
	hud_texts = keep


func update_camera(delta: float) -> void:
	if cam == null:
		return
	var goal: Vector3 = player.position if not player.dead else Vector3(spawn_pos(0).x, 0, 0)
	goal.z = clamp(goal.z, -2.0, 2.0)
	cam_focus = cam_focus.lerp(goal, clamp(delta * 6.0, 0.0, 1.0))
	var off := Vector3(0, 14.0, 9.2)
	var sh := Vector3.ZERO
	if shake_t > 0:
		shake_t -= delta
		sh = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * shake_t * 0.8
	cam.position = cam_focus + off + sh
	cam.look_at(cam_focus + sh + Vector3(0, 0.5, 0), Vector3.UP)


func shake(t: float) -> void:
	shake_t = max(shake_t, t)


func spawn_wave() -> void:
	wave_count += 1
	var melee := 3 + (1 if wave_count >= 8 else 0)
	for team in 2:
		var d := 1.0 if team == 0 else -1.0
		var bx := 8.5 if team == 0 else LANE_LEN - 8.5
		for i in melee:
			var off := (i - (melee - 1) / 2.0) * 0.9
			var c = make_unit(Unit.Kind.CREEP, team, Vector2(bx - d * (i % 2) * 0.8, off))
			c.lane_offset = off
		var r = make_unit(Unit.Kind.RANGED, team, Vector2(bx - d * 2.0, 0))
		r.lane_offset = 0


func separation() -> void:
	var units := get_tree().get_nodes_in_group("units")
	var n := units.size()
	for i in n:
		var a = units[i]
		var am: bool = a.is_mobile()
		for j in range(i + 1, n):
			var b = units[j]
			var bm: bool = b.is_mobile()
			if not am and not bm:
				continue
			var diff: Vector2 = b.p2() - a.p2()
			var dist := diff.length()
			var min_d: float = a.radius + b.radius
			if dist >= min_d:
				continue
			if dist < 0.001:
				diff = Vector2(randf() - 0.5, randf() - 0.5)
				dist = diff.length()
			var push: Vector2 = diff / dist * (min_d - dist)
			if am and bm:
				a.set_p2(a.p2() - push * 0.5)
				b.set_p2(b.p2() + push * 0.5)
			elif am:
				a.set_p2(a.p2() - push)
			else:
				b.set_p2(b.p2() + push)


# ---------------------------------------------------------------- queries
func find_target(u, r: float, prefer_hero := false):
	var best = null
	var bd := INF
	for o in get_tree().get_nodes_in_group("units"):
		if o.dead or o.team == u.team or o.invulnerable:
			continue
		var d: float = u.p2().distance_to(o.p2()) - o.radius
		if prefer_hero and o.kind == Unit.Kind.HERO:
			d -= 1.5
		if d < r and d < bd:
			best = o
			bd = d
	return best


func enemies_near(pos: Vector2, team: int, r: float) -> Array:
	var out: Array = []
	for o in get_tree().get_nodes_in_group("units"):
		if o.dead or o.team == team or o.invulnerable:
			continue
		if pos.distance_to(o.p2()) - o.radius < r:
			out.append(o)
	return out


func allied_creeps_near(pos: Vector2, team: int, r: float) -> int:
	var n := 0
	for o in get_tree().get_nodes_in_group("units"):
		if o.dead or o.team != team:
			continue
		if (o.kind == Unit.Kind.CREEP or o.kind == Unit.Kind.RANGED) and pos.distance_to(o.p2()) < r:
			n += 1
	return n


func structure_pick(s):
	var best = null
	var bd := INF
	var hero = null
	for o in get_tree().get_nodes_in_group("units"):
		if o.dead or o.team == s.team or o.invulnerable or not o.is_mobile():
			continue
		var d: float = s.p2().distance_to(o.p2()) - o.radius
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
		if pos.distance_to(s.p2()) < s.atk_range + s.radius + u.radius + 0.8:
			if s.target == u:
				return true
			if allied_creeps_near(s.p2(), u.team, s.atk_range + 0.6) == 0:
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
		return best * d - d * 2.8
	var fx_best := -INF
	for t in towers[team]:
		fx_best = max(fx_best, t.position.x * d)
	if fx_best > -INF:
		return fx_best * d - d * 2.0
	return bases[team].position.x + d * 5.0


func call_tower_help(victim, attacker) -> void:
	for s in structures_of(victim.team):
		if s.dead:
			continue
		if s.dist_to(attacker) <= s.atk_range + attacker.radius:
			s.target = attacker


func update_invulnerability() -> void:
	for team in 2:
		var has_t1 := false
		for t in towers[team]:
			if t.tier == 1:
				has_t1 = true
		for t in towers[team]:
			t.invulnerable = t.tier == 2 and has_t1
		bases[team].invulnerable = towers[team].size() > 0


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
	fx.add_ring(h.position, 1.4, Color(1, 0.85, 0.3), 0.6, 1.0)
	fx.add_text(h.position, "+FORÇA", Color(1, 0.85, 0.3))


func on_unit_died(u, src) -> void:
	if src != null and is_instance_valid(src) and src.kind == Unit.Kind.HERO and src.team != u.team:
		src.gold += u.bounty
		if u.kind != Unit.Kind.HERO and src.is_player:
			fx.add_text(u.position, "+%d" % u.bounty, Color(1, 0.85, 0.2))
	for h in heroes:
		if h.team != u.team and not h.dead and h.dist_to(u) < 25.0:
			h.add_xp(u.xp_value)
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
			shake(0.4)
			update_invulnerability()
		Unit.Kind.BASE:
			shake(0.8)
			end_game(u.team == 1)


func end_game(won: bool) -> void:
	game_over = true
	if autotest:
		print("GAME OVER won=%s t=%d" % [won, game_time])
		get_tree().quit()
		return
	hud.show_end(won)
	get_tree().paused = true


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- screenshot test
func setup_shot() -> void:
	player.set_p2(Vector2(42, 0.5))
	cam_focus = player.position
	for i in 2:
		spawn_wave()
	var k := 0
	for o in get_tree().get_nodes_in_group("units"):
		if o.kind == Unit.Kind.CREEP or o.kind == Unit.Kind.RANGED:
			var base_x: float = 44.0 if o.team == 0 else 49.0
			o.set_p2(Vector2(base_x + (k % 3) * 0.9, -3.0 + (k % 7) * 1.0))
			k += 1
	bot.set_p2(Vector2(50.5, -1.5))
	update_camera(1.0)
	await get_tree().create_timer(1.2).timeout
	player.cast(0)
	await get_tree().create_timer(0.3).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/shot_%s.png" % shot_mode)
	print("SHOT SAVED")
	get_tree().quit()
