extends Node3D
## Stage 2: full MOBA map. Three lanes (top, mid, bot), river, jungle with neutral camps,
## bases in opposite corners and 3v3 heroes (player + 5 bots).
## Gameplay runs on the ground plane: Vector2(x, z). Blue base bottom-left, red base top-right.

const Unit := preload("res://scripts/unit3d.gd")
const FxScript := preload("res://scripts/fx3d.gd")
const HudScript := preload("res://scripts/hud.gd")
const ArtScript := preload("res://scripts/world_art.gd")

const MAP := 140.0
const FOUNTAIN_R := 9.0
const WAVE_INTERVAL := 30.0
const CAMP_RESPAWN := 60.0
const LANE_W := 9.0
const BASE_POS := [Vector2(17, 123), Vector2(123, 17)]
const FOUNTAIN_POS := [Vector2(7, 133), Vector2(133, 7)]
const LANE_NAMES := ["TOPO", "MEIO", "BAIXO"]
const CAMP_POS := [Vector2(33, 70), Vector2(70, 107), Vector2(70, 33), Vector2(107, 70)]
## [config key, lane] - first three are blue (index 0 = player), last three red
const ROSTER := [["elfo", 1], ["elfa", 2], ["cavaleiro", 0], ["orc", 1], ["orca", 0], ["acougueiro", 2]]

var lanes: Array = []
var lane_cum: Array = []
var lane_len: Array = []
var obstacles: Array = []
var obs_grid := {}
var astar: AStarGrid2D

var cfgs := {}
var heroes: Array = []
var player
var bases: Array = [null, null]
var towers: Array = [[], []]
var camps: Array = []
var team_kills := [0, 0]
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
var low_quality := false
var cam_zoom := 1.05
var units: Array = []
var merged_cache := {}
var creep_pool := {}
var cull_t := 0.0
var perf_acc := 0.0
var perf_n := 0
var prof := {}
var art
static var picked := ""
static var picking := true


func pf(k: String, t0: int) -> void:
	prof[k] = prof.get(k, 0) + Time.get_ticks_usec() - t0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	autotest = "--autotest" in args
	low_quality = OS.has_feature("web_ios") or OS.has_feature("web_android") or OS.has_feature("mobile") or "--mobile" in args
	if "--desktop" in args:
		low_quality = false
	apply_quality()
	for a in args:
		if a.begins_with("--hero="):
			picked = a.substr(7)
		if a.begins_with("--shot="):
			shot_mode = a.substr(7)
	build_lanes()
	build_obstacles()
	art = ArtScript.new(self)
	if "--bake" in args:
		art.bake()
		set_physics_process(false)
		set_process(false)
		get_tree().quit()
		return
	load_configs()
	fx = FxScript.new()
	fx.game = self
	fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(fx)
	build_world()

	for team in 2:
		bases[team] = make_unit(Unit.Kind.BASE, team, BASE_POS[team])
	for spot in art.tower_spots():
		var t = make_unit(Unit.Kind.TOWER, spot["team"], spot["pos"])
		t.tier = spot["tier"]
		t.lane = spot["lane"]
		t.lane_s = spot["s"]
		towers[spot["team"]].append(t)

	for team in 2:
		for st in structures_of(team):
			block_cells(st.p2(), st.radius + 0.7)
	if "--picktest" in args and picked == "":
		_picktest.call_deferred()
	elif "--picktest" in args:
		_picktest_after.call_deferred()
	if autotest or shot_mode != "" or "--bench" in args:
		picking = shot_mode == "pick"
	var roster: Array = ROSTER.duplicate(true)
	var found := false
	for j in roster.size():
		if roster[j][0] == picked:
			found = true
			if j != 0:
				roster[j][0] = roster[0][0]
				roster[0][0] = picked
	if picked != "" and not found and cfgs.has("hero_" + picked):
		roster[0][0] = picked
	for i in roster.size():
		var team := 0 if i < 3 else 1
		var key: String = "hero_" + roster[i][0]
		var h = make_unit(Unit.Kind.HERO, team, spawn_pos(team), i == 0, key)
		h.lane = ROSTER[i][1]
		h.hero_name = cfgs[key]["name"]
		h.set_kit(roster[i][0])
		h.is_bot = i != 0 or (autotest and not ("--afk" in args))
		heroes.append(h)
	player = heroes[0]
	for c in CAMP_POS:
		camps.append({"pos": c, "units": [], "t": 15.0})

	cam = Camera3D.new()
	cam.fov = 42.0
	cam.far = 120.0
	add_child(cam)
	cam.make_current()
	cam_focus = player.position
	update_camera(1.0)

	# soft vignette between the 3D view and the HUD
	var vl := CanvasLayer.new()
	vl.layer = 0
	var vg := Gradient.new()
	vg.set_color(0, Color(0, 0, 0, 0))
	vg.set_color(1, Color(0.0, 0.03, 0.04, 0.55))
	vg.add_point(0.62, Color(0, 0, 0, 0))
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.08, 1.08)
	vt.width = 128
	vt.height = 128
	var vr := TextureRect.new()
	vr.texture = vt
	vr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vr.stretch_mode = TextureRect.STRETCH_SCALE
	vr.set_anchors_preset(Control.PRESET_FULL_RECT)
	vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vl.add_child(vr)
	add_child(vl)
	hud = HudScript.new()
	hud.game = self
	add_child(hud)
	update_invulnerability()
	if autotest:
		Engine.time_scale = 4.0
	if shot_mode != "":
		setup_shot()
	if "--bench" in args:
		run_bench()


func load_configs() -> void:
	var hero_anims := {"idle": "Idle", "run": "Running_A", "attack": "1H_Melee_Attack_Chop", "death": "Death_A",
		"spin": "2H_Melee_Attack_Spin", "dash": "Dodge_Forward", "cheer": "Cheer", "ult": "2H_Melee_Attack_Chop"}
	var barb_anims := hero_anims.duplicate()
	barb_anims["attack"] = "2H_Melee_Attack_Chop"
	barb_anims["idle"] = "2H_Melee_Idle"
	var q_ranged := {"idle": "Idle", "run": "Jog_Fwd", "attack": "Spell_Simple_Shoot", "death": "Death01",
		"spin": "Spell_Simple_Shoot", "dash": "Roll", "cheer": "Spell_Simple_Enter", "ult": "Spell_Simple_Enter"}
	var q_melee := {"idle": "Sword_Idle", "run": "Sprint", "attack": "Sword_Attack", "death": "Death01",
		"spin": "Sword_Attack", "dash": "Roll", "cheer": "Punch_Cross", "ult": "Sword_Attack"}
	var ual: AnimationLibrary = load("res://assets/anims/ual_lib.res")
	var staff: PackedScene = load("res://assets/env/staff.gltf")
	var axe: PackedScene = load("res://assets/env/axe_2handed.gltf")
	var wpn_staff := [staff, "hand_r", Vector3(0, 0.05, 0), Vector3(0, 0, 90), 0.75]
	var wpn_axe := [axe, "hand_r", Vector3(0, 0.05, 0), Vector3(0, 0, 90), 0.75]
	cfgs["hero_elfo"] = {"name": "Elfo", "merge": true, "scene": load("res://assets/meshy/elfo.glb"), "scale": 1.7,
		"lib": ual, "weapon": wpn_staff, "anims": q_ranged,
		"stats": {"hp": 720, "dmg": 46, "range": 5.0, "cd": 0.85, "speed": 6.2}}
	cfgs["hero_elfa"] = {"name": "Elfa", "merge": true, "scene": load("res://assets/quaternius/Elf_Female.glb"), "scale": 1.7,
		"lib": ual, "weapon": wpn_staff, "anims": q_ranged,
		"stats": {"hp": 680, "dmg": 44, "range": 5.5, "cd": 0.85, "speed": 6.2}}
	cfgs["hero_cavaleiro"] = {"name": "Cavaleiro", "merge": true, "scene": load("res://assets/chars/Knight.glb"), "scale": 1.0,
		"hide": ["1H_Sword_Offhand", "Badge_Shield", "Rectangle_Shield", "Spike_Shield", "2H_Sword"], "anims": hero_anims,
		"stats": {"hp": 840, "dmg": 52, "range": 1.4, "cd": 0.95, "speed": 6.0}}
	cfgs["hero_orc"] = {"name": "Orc", "merge": true, "scene": load("res://assets/quaternius/Orc_Male.glb"), "scale": 1.8,
		"lib": ual, "weapon": wpn_axe, "anims": q_melee,
		"stats": {"hp": 820, "dmg": 56, "range": 1.4, "cd": 1.0, "speed": 6.0}}
	cfgs["hero_orca"] = {"name": "Orca", "merge": true, "scene": load("res://assets/quaternius/Orc_Female.glb"), "scale": 1.75,
		"lib": ual, "weapon": wpn_staff, "anims": q_ranged,
		"stats": {"hp": 700, "dmg": 45, "range": 5.0, "cd": 0.9, "speed": 6.2}}
	cfgs["hero_barbaro"] = {"name": "Bárbaro", "merge": true, "scene": load("res://assets/chars/Barbarian.glb"), "scale": 1.0,
		"hide": ["1H_Axe_Offhand", "Barbarian_Round_Shield", "1H_Axe", "Mug"], "anims": barb_anims,
		"stats": {"hp": 840, "dmg": 54, "range": 1.4, "cd": 1.0, "speed": 6.0}}
	# Açougueiro: Tripo model (decimated, rigged in-sandbox on the UAL skeleton; tools/rig_ac).
	var butcher_anims := {"idle": "Sword_Idle", "run": "Jog_Fwd", "attack": "Sword_Attack", "death": "Death01",
		"spin": "Sword_Attack", "dash": "Roll", "cheer": "Spell_Simple_Enter", "ult": "Punch_Cross", "hook": "Spell_Simple_Shoot"}
	cfgs["hero_acougueiro"] = {"name": "Açougueiro", "merge": true, "scene": load("res://assets/tripo/acougueiro.glb"), "scale": 1.45,
		"lib": ual, "anims": butcher_anims,
		"stats": {"hp": 950, "dmg": 58, "range": 1.5, "cd": 1.1, "speed": 5.8}}
	cfgs["creep0"] = {"merge": true, "scene": load("res://assets/chars/Knight.glb"), "scale": 0.66,
		"hide": ["1H_Sword_Offhand", "Badge_Shield", "Rectangle_Shield", "Spike_Shield", "2H_Sword"],
		"anims": {"idle": "Idle", "run": "Running_A", "attack": "1H_Melee_Attack_Chop", "death": "Death_A"}}
	cfgs["creep1"] = {"merge": true, "scene": load("res://assets/chars/Skeleton_Minion.glb"), "scale": 0.74, "hide": [],
		"anims": {"idle": "Idle", "run": "Running_A", "attack": "Unarmed_Melee_Attack_Punch_A", "death": "Death_A"}}
	cfgs["creep2"] = {"merge": true, "scene": load("res://assets/chars/Skeleton_Warrior.glb"), "scale": 0.95, "hide": [],
		"anims": {"idle": "Idle_Combat", "run": "Running_A", "attack": "Unarmed_Melee_Attack_Punch_A", "death": "Death_A"}}
	cfgs["ranged0"] = {"merge": true, "scene": load("res://assets/chars/Rogue.glb"), "scale": 0.66,
		"hide": ["Knife", "Knife_Offhand", "2H_Crossbow", "Throwable"],
		"anims": {"idle": "Idle", "run": "Running_A", "attack": "1H_Ranged_Shoot", "death": "Death_A"}}
	cfgs["ranged1"] = {"merge": true, "scene": load("res://assets/chars/Skeleton_Mage.glb"), "scale": 0.72, "hide": [],
		"anims": {"idle": "Idle", "run": "Running_A", "attack": "Spellcast_Shoot", "death": "Death_A"}}
	cfgs["ranged2"] = {"merge": true, "scene": load("res://assets/chars/Mage.glb"), "scale": 0.75, "hide": [],
		"anims": {"idle": "Idle", "run": "Running_A", "attack": "Spellcast_Shoot", "death": "Death_A"}}
	cfgs["tower0"] = {"scene": load("res://assets/env/building_tower_A_blue.gltf"), "scale": 3.1}
	cfgs["tower1"] = {"scene": load("res://assets/env/building_tower_A_red.gltf"), "scale": 3.1}
	cfgs["base0"] = {"scene": load("res://assets/env/building_castle_blue.gltf"), "scale": 2.4}
	cfgs["base1"] = {"scene": load("res://assets/env/building_castle_red.gltf"), "scale": 2.4}


func make_unit(kind: int, team: int, pos: Vector2, is_player := false, key := ""):
	if key == "":
		key = ["hero", "creep", "ranged", "tower", "base"][kind] + str(team)
	if creep_pool.has(key) and creep_pool[key].size() > 0:
		var r = creep_pool[key].pop_back()
		r.position = Vector3(pos.x, 0, pos.y)
		r.reset_creep()
		return r
	var u = Unit.new()
	u.game = self
	u.team = team
	u.kind = kind
	u.is_player = is_player
	u.position = Vector3(pos.x, 0, pos.y)
	u.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(u)
	u.setup(cfgs[key])
	u.add_to_group("units")
	if kind == Unit.Kind.TOWER or kind == Unit.Kind.BASE:
		u.model.rotation.y = PI / 6.0
	return u


func fountain_pos(team: int) -> Vector2:
	return FOUNTAIN_POS[team]


func spawn_pos(team: int) -> Vector2:
	return FOUNTAIN_POS[team] + Vector2(randf_range(-2, 2), randf_range(-2, 2))


func clamp_world(p: Vector2) -> Vector2:
	return Vector2(clamp(p.x, 1.5, MAP - 1.5), clamp(p.y, 1.5, MAP - 1.5))


# ---------------------------------------------------------------- lanes
func build_lanes() -> void:
	# control points (point-symmetric about the map centre), smoothed into gentle curves
	var ctrl := [
		[BASE_POS[0], Vector2(15, 106), Vector2(12, 70), Vector2(16, 26), Vector2(26, 16), Vector2(70, 12), Vector2(106, 15), BASE_POS[1]],
		[BASE_POS[0], Vector2(40, 97), Vector2(70, 70), Vector2(100, 43), BASE_POS[1]],
		[BASE_POS[0], Vector2(34, 125), Vector2(70, 128), Vector2(114, 124), Vector2(124, 114), Vector2(128, 70), Vector2(125, 34), BASE_POS[1]]]
	lanes = []
	for c in ctrl:
		lanes.append(_smooth(c))
	for l in lanes:
		var cum := PackedFloat32Array([0.0])
		for i in range(1, l.size()):
			cum.append(cum[i - 1] + l[i - 1].distance_to(l[i]))
		lane_cum.append(cum)
		lane_len.append(cum[cum.size() - 1])


## Catmull-Rom through the control points, sampled every ~2.5 units.
func _smooth(c: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in c.size() - 1:
		var p0: Vector2 = c[max(i - 1, 0)]
		var p1: Vector2 = c[i]
		var p2: Vector2 = c[i + 1]
		var p3: Vector2 = c[min(i + 2, c.size() - 1)]
		var n := int(max(1, ceil(p1.distance_to(p2) / 2.5)))
		for k in n:
			var t := float(k) / n
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(c[c.size() - 1])
	return out


# ---------------------------------------------------------------- river (meandering, point-symmetric)
## u along the river (0 at the map centre), v across it.
func river_uv(p: Vector2) -> Vector2:
	return Vector2((p.x + p.y) * 0.70710678 - MAP * 0.70710678, (p.x - p.y) * 0.70710678)


func river_off(u: float) -> float:
	return 7.0 * sin(u * 0.075) + 2.4 * sin(u * 0.19)


func river_hw(u: float) -> float:
	return 4.3 + 1.4 * cos(u * 0.12) + 0.5 * cos(u * 0.31)


## signed distance across the river centreline
func river_v(p: Vector2) -> float:
	var uv := river_uv(p)
	return uv.y - river_off(uv.x)


## 0 on the centreline, 1 at the bank
func river_depth(p: Vector2) -> float:
	var uv := river_uv(p)
	return abs(uv.y - river_off(uv.x)) / river_hw(uv.x)


func river_point(u: float, v: float = 0.0) -> Vector2:
	var vv := river_off(u) + v
	var c := MAP * 0.70710678
	return Vector2((u + c + vv) * 0.70710678, (u + c - vv) * 0.70710678)


func _seg(lane: int, s: float) -> int:
	var cum: PackedFloat32Array = lane_cum[lane]
	for i in range(1, cum.size()):
		if s <= cum[i]:
			return i - 1
	return cum.size() - 2


func lane_point(lane: int, s: float) -> Vector2:
	s = clamp(s, 0.0, lane_len[lane])
	var i := _seg(lane, s)
	var l: PackedVector2Array = lanes[lane]
	var cum: PackedFloat32Array = lane_cum[lane]
	var seg_len: float = cum[i + 1] - cum[i]
	return l[i].lerp(l[i + 1], (s - cum[i]) / max(seg_len, 0.001))


func lane_dir(lane: int, s: float) -> Vector2:
	var i := _seg(lane, clamp(s, 0.0, lane_len[lane]))
	var l: PackedVector2Array = lanes[lane]
	return (l[i + 1] - l[i]).normalized()


func lane_normal(lane: int, s: float) -> Vector2:
	return lane_dir(lane, s).orthogonal()


func lane_proj(lane: int, p: Vector2) -> float:
	var l: PackedVector2Array = lanes[lane]
	var cum: PackedFloat32Array = lane_cum[lane]
	var best := INF
	var best_s := 0.0
	for i in l.size() - 1:
		var a := l[i]
		var ab := l[i + 1] - a
		var t: float = clamp((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			best_s = cum[i] + t * ab.length()
	return best_s


func lane_dist(lane: int, p: Vector2) -> float:
	return p.distance_to(lane_point(lane, lane_proj(lane, p)))


func dist_to_lanes(p: Vector2) -> float:
	return min(lane_dist(0, p), min(lane_dist(1, p), lane_dist(2, p)))


func nearest_lane(p: Vector2) -> int:
	var best := 0
	for l in range(1, 3):
		if lane_dist(l, p) < lane_dist(best, p):
			best = l
	return best


# ---------------------------------------------------------------- jungle obstacles + pathfinding
func build_obstacles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var step := 7.0
	var gx := 4.0
	while gx < MAP - 3.0:
		var gz := 4.0
		while gz < MAP - 3.0:
			var p := Vector2(gx + rng.randf_range(-1.6, 1.6), gz + rng.randf_range(-1.6, 1.6))
			var keep := rng.randf() > 0.3
			gz += step
			if not keep or dist_to_lanes(p) < 7.5:
				continue
			if river_depth(p) < 1.5:
				continue  # river
			if p.distance_to(BASE_POS[0]) < 24.0 or p.distance_to(BASE_POS[1]) < 24.0:
				continue
			if p.distance_to(FOUNTAIN_POS[0]) < 16.0 or p.distance_to(FOUNTAIN_POS[1]) < 16.0:
				continue
			var near_camp := false
			for c in CAMP_POS:
				if p.distance_to(c) < 8.0:
					near_camp = true
			if near_camp:
				continue
			obstacles.append([p, rng.randf_range(1.5, 2.0)])
		gx += step
	for o in obstacles:
		var k := Vector2i(int(o[0].x / 10.0), int(o[0].y / 10.0))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var kk := k + Vector2i(dx, dz)
				if not obs_grid.has(kk):
					obs_grid[kk] = []
				obs_grid[kk].append(o)
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, int(MAP), int(MAP))
	astar.cell_size = Vector2(1, 1)
	astar.offset = Vector2(0.5, 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for o in obstacles:
		var c: Vector2 = o[0]
		var r: float = o[1] + 0.6
		for x in range(int(c.x - r) - 1, int(c.x + r) + 2):
			for z in range(int(c.y - r) - 1, int(c.y + r) + 2):
				if x < 0 or z < 0 or x >= int(MAP) or z >= int(MAP):
					continue
				if Vector2(x + 0.5, z + 0.5).distance_to(c) < r:
					astar.set_point_solid(Vector2i(x, z), true)


func block_cells(c: Vector2, r: float) -> void:
	for x in range(int(c.x - r) - 1, int(c.x + r) + 2):
		for z in range(int(c.y - r) - 1, int(c.y + r) + 2):
			if x < 0 or z < 0 or x >= int(MAP) or z >= int(MAP):
				continue
			if Vector2(x + 0.5, z + 0.5).distance_to(c) < r:
				astar.set_point_solid(Vector2i(x, z), true)


func open_cell(p: Vector2) -> Vector2i:
	var c := Vector2i(clamp(int(p.x), 0, int(MAP) - 1), clamp(int(p.y), 0, int(MAP) - 1))
	if not astar.is_point_solid(c):
		return c
	for r in range(1, 5):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var q := c + Vector2i(dx, dz)
				if astar.is_in_boundsv(q) and not astar.is_point_solid(q):
					return q
	return c


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	return astar.get_point_path(open_cell(from), open_cell(to), true)


func push_out(p: Vector2, r: float) -> Vector2:
	var k := Vector2i(int(p.x / 10.0), int(p.y / 10.0))
	if obs_grid.has(k):
		for o in obs_grid[k]:
			var d: Vector2 = p - o[0]
			var m: float = o[1] + r
			var l2 := d.length_squared()
			if l2 < m * m:
				if l2 < 0.0001:
					d = Vector2(1, 0)
				p = o[0] + d.normalized() * m
	return clamp_world(p)


# ---------------------------------------------------------------- world
func build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.1, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.64, 0.74)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = not low_quality
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.17, 0.18)
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = ArtScript.SUN_ROT
	sun.light_color = Color(1.0, 0.88, 0.72)
	sun.light_energy = 1.3
	sun.shadow_enabled = false
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_bias = 0.05
	add_child(sun)

	art.build_ground()
	# base plazas + fountains
	for team in 2:
		var fm := MeshInstance3D.new()
		var cm := PlaneMesh.new()
		cm.size = Vector2(FOUNTAIN_R * 2.0, FOUNTAIN_R * 2.0)
		fm.mesh = cm
		fm.material_override = FxScript.ground_ring_mat(Color(Unit.TEAM_COLORS[team], 0.5), 0.35, 0.04)
		fm.position = Vector3(FOUNTAIN_POS[team].x, 0.04, FOUNTAIN_POS[team].y)
		add_child(fm)
	scatter_props()
	art.build_decor()
	art.build_blobs()


func scatter_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var tree_keys := ["res://assets/env/trees_A_large.gltf", "res://assets/env/trees_B_large.gltf", "res://assets/env/trees_A_medium.gltf"]
	var rock_keys := ["res://assets/env/rock_single_A.gltf", "res://assets/env/rock_single_B.gltf", "res://assets/env/rock_single_C.gltf"]
	var groups := {}
	for k in tree_keys + rock_keys:
		groups[k] = []
	# jungle trees = the obstacles
	for o in obstacles:
		var k: String = tree_keys[rng.randi_range(0, 2)]
		var s: float = o[1] * 1.55
		groups[k].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(o[0].x, 0, o[0].y)))
	# thicken jungle clumps with decorative trees around each obstacle (no collision)
	var deco_keys := ["res://assets/env/trees_B_medium.gltf", "res://assets/env/tree_single_A.gltf", "res://assets/env/tree_single_B.gltf"]
	for k in deco_keys:
		groups[k] = []
	for o in obstacles:
		for n in 2:
			var dp: Vector2 = o[0] + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.6, 3.0)
			if dist_to_lanes(dp) < LANE_W * 0.5 + 2.2 or river_depth(dp) < 2.0:
				continue
			var near_camp := false
			for c in CAMP_POS:
				if dp.distance_to(c) < 6.0:
					near_camp = true
			if near_camp:
				continue
			groups[deco_keys[rng.randi_range(0, 2)]].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(2.0, 3.0)), Vector3(dp.x, 0, dp.y)))
	# border forest outside the playable square
	var t := -12.0
	while t < MAP + 12.0:
		for ring in 3:
			var d := 2.0 + ring * 4.5
			for p in [Vector2(t, -d), Vector2(t, MAP + d), Vector2(-d, t), Vector2(MAP + d, t)]:
				var k2: String = tree_keys[rng.randi_range(0, 1)]
				var jp: Vector2 = p + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
				groups[k2].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(3.0, 3.8)), Vector3(jp.x, 0, jp.y)))
		t += 5.0
	# a few rocks on lane edges
	for lane in 3:
		var s := 10.0
		while s < lane_len[lane] - 10.0:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var p: Vector2 = lane_point(lane, s) + lane_normal(lane, s) * side * (LANE_W / 2.0 + 1.0)
			if river_depth(p) > 1.4:
				groups[rock_keys[rng.randi_range(0, 2)]].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(3.5, 5.5)), Vector3(p.x, 0, p.y)))
			s += rng.randf_range(9.0, 16.0)
	for k in groups:
		if groups[k].size() > 0:
			multimesh(k, groups[k])


# ---------------------------------------------------------------- loop
func _physics_process(delta: float) -> void:
	var portrait: bool = hud.is_portrait()
	if not game_over and shot_mode == "":
		get_tree().paused = portrait or picking
	if picking and shot_mode == "":
		return
	if game_over or (portrait and shot_mode == ""):
		return
	refresh_units()
	game_time += delta
	wave_timer -= delta
	if wave_timer <= 0:
		spawn_wave()
		wave_timer = WAVE_INTERVAL
	for h in heroes:
		h.gold += 1.5 * delta
	update_camps(delta)
	var t0 := Time.get_ticks_usec()
	separation()
	pf("sep", t0)
	if autotest and int(game_time * 60) % 1800 == 0:
		var lv := []
		for h in heroes:
			lv.append(h.level)
		print("t=%d towers=%d/%d baseHP=%d/%d kills=%d/%d levels=%s units=%d cpu_ms=%.2f" % [game_time, towers[0].size(), towers[1].size(), bases[0].hp, bases[1].hp, team_kills[0], team_kills[1], str(lv), units.size(), perf_acc / max(perf_n, 1)])
		perf_acc = 0.0
		perf_n = 0
		print("   prof(ms total) ", prof.keys().map(func(k): return "%s=%d" % [k, prof[k] / 1000]))
		prof.clear()
		for h in heroes:
			print("   %s lane=%d pos=%s hp=%d dead=%s ret=%s tgt=%s camp=%s" % [h.hero_name, h.lane, str(h.p2().round()), h.hp, h.dead, h.retreating, (h.target.name if h.target != null and is_instance_valid(h.target) else "-"), h.jungle_camp != null])
		var cc := [[0, 0, 0], [0, 0, 0]]
		for o in units:
			if o.lane >= 0 and o.team < 2 and (o.kind == Unit.Kind.CREEP or o.kind == Unit.Kind.RANGED):
				cc[o.team][o.lane] += 1
		print("   creeps per lane blue=%s red=%s" % [str(cc[0]), str(cc[1])])
		if game_time > 2400:
			print("TIMEOUT")
			get_tree().quit()


func _process(delta: float) -> void:
	if autotest:
		perf_acc += (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		perf_n += 1
	update_camera(delta)
	var keep: Array = []
	for t in hud_texts:
		t["t"] += delta
		if t["t"] < t["dur"]:
			keep.append(t)
	hud_texts = keep
	cull_t -= delta
	if cull_t <= 0:
		cull_t = 0.4
		cull_animations()
	art.update_blobs()


## Units far from the camera stop animating (skinning + AnimationPlayer cost).
func cull_animations() -> void:
	var c := Vector2(cam_focus.x, cam_focus.z)
	for u in units:
		if u.anim == null:
			continue
		var on: bool = c.distance_squared_to(u.p2()) < 40.0 * 40.0
		if u.anim.active != on:
			u.anim.active = on


func update_camera(delta: float) -> void:
	if cam == null:
		return
	var goal: Vector3 = player.position
	if player.dead:
		var f := fountain_pos(0)
		goal = Vector3(f.x + 6, 0, f.y - 6)
	cam_focus = cam_focus.lerp(goal, clamp(delta * 6.0, 0.0, 1.0))
	var off := Vector3(0, 20.5, 8.6) * cam_zoom
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
	var melee := 2 + (1 if wave_count >= 6 else 0)
	if not low_quality:
		melee += 1
	for team in 2:
		for lane in 3:
			var s0: float = 6.0 if team == 0 else lane_len[lane] - 6.0
			var dirn := 1.0 if team == 0 else -1.0
			var nrm := lane_normal(lane, s0)
			for i in melee:
				var off := (i - (melee - 1) / 2.0) * 1.0
				var c = make_unit(Unit.Kind.CREEP, team, lane_point(lane, s0 - dirn * (i % 2) * 0.8) + nrm * off)
				c.lane = lane
				c.lane_s = s0
				c.lane_offset = off
			var r = make_unit(Unit.Kind.RANGED, team, lane_point(lane, s0 - dirn * 2.0))
			r.lane = lane
			r.lane_s = s0
			r.lane_offset = 0.0


func update_camps(delta: float) -> void:
	for c in camps:
		var alive := 0
		for u in c["units"]:
			if u.camp == c and not u.dead:
				alive += 1
		if c["units"].size() > 0 and alive == 0:
			c["units"] = []
			c["t"] = CAMP_RESPAWN
		if c["units"].is_empty():
			c["t"] -= delta
			if c["t"] <= 0:
				spawn_camp(c)


func spawn_camp(c: Dictionary) -> void:
	var p: Vector2 = c["pos"]
	var big = make_unit(Unit.Kind.CREEP, 2, p + Vector2(0.9, -0.3))
	var small = make_unit(Unit.Kind.RANGED, 2, p + Vector2(-1.2, 0.9))
	c["units"] = [big, small]
	for u in c["units"]:
		u.camp = c
		u.home_pos = u.p2()
		u.target = null


func camp_alive(c: Dictionary) -> bool:
	for u in c["units"]:
		if u.camp == c and not u.dead:
			return true
	return false


func refresh_units() -> void:
	units = get_tree().get_nodes_in_group("units")


## Unit-unit separation through a spatial hash, then trees/map edge.
func separation() -> void:
	var cell := 3.0
	var grid := {}
	var n := units.size()
	var pos := PackedVector2Array()
	pos.resize(n)
	for i in n:
		var u = units[i]
		var p := Vector2(u.position.x, u.position.z)
		pos[i] = p
		if u.dead:
			continue
		var k := Vector2i(int(p.x / cell), int(p.y / cell))
		if grid.has(k):
			grid[k].append(i)
		else:
			grid[k] = [i]
	for i in n:
		var a = units[i]
		if a.dead or not a.is_mobile():
			continue
		var pa := pos[i]
		var k := Vector2i(int(pa.x / cell), int(pa.y / cell))
		var ra: float = a.radius
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var kk := k + Vector2i(dx, dz)
				if not grid.has(kk):
					continue
				for j in grid[kk]:
					if j == i:
						continue
					var b = units[j]
					var diff: Vector2 = pa - pos[j]
					var min_d: float = ra + b.radius
					var d2 := diff.length_squared()
					if d2 >= min_d * min_d:
						continue
					var dist := sqrt(d2)
					if dist < 0.001:
						diff = Vector2(randf() - 0.5, randf() - 0.5)
						dist = diff.length()
					pa += diff / dist * (min_d - dist) * (0.5 if b.is_mobile() else 1.0)
		pa = push_out(pa, ra)
		a.position.x = pa.x
		a.position.z = pa.y


# ---------------------------------------------------------------- queries
func hostile(u, o) -> bool:
	if o.team == u.team:
		return false
	if o.team == 2 or u.team == 2:
		return u.kind == Unit.Kind.HERO or o.kind == Unit.Kind.HERO
	return true


func find_target(u, r: float, prefer_hero := false):
	var best = null
	var bd := INF
	var up: Vector2 = u.p2()
	for o in units:
		if o.dead or o.invulnerable or not hostile(u, o):
			continue
		var d: float = up.distance_to(o.p2()) - o.radius
		if prefer_hero and o.kind == Unit.Kind.HERO:
			d -= 1.5
		if d < r and d < bd:
			best = o
			bd = d
	return best


func enemies_near(pos: Vector2, team: int, r: float) -> Array:
	var out: Array = []
	for o in units:
		if o.dead or o.team == team or o.invulnerable:
			continue
		if pos.distance_to(o.p2()) - o.radius < r:
			out.append(o)
	return out


func heroes_near(pos: Vector2, team: int, r: float) -> int:
	var n := 0
	for h in heroes:
		if h.team == team and not h.dead and pos.distance_to(h.p2()) < r:
			n += 1
	return n


func nearest_enemy_hero(u, r: float):
	var best = null
	var bd := r
	for h in heroes:
		if h.team == u.team or h.dead:
			continue
		var d: float = u.dist_to(h)
		if d < bd:
			bd = d
			best = h
	return best


func allied_creeps_near(pos: Vector2, team: int, r: float) -> int:
	var n := 0
	for o in units:
		if o.dead or o.team != team:
			continue
		if (o.kind == Unit.Kind.CREEP or o.kind == Unit.Kind.RANGED) and pos.distance_to(o.p2()) < r:
			n += 1
	return n


func structure_pick(s):
	var best = null
	var bd := INF
	var hero = null
	for o in units:
		if o.dead or o.team == s.team or o.team == 2 or o.invulnerable or not o.is_mobile():
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


## Where a laning hero should stand: just behind its own creep front, or by its tower.
func lane_hold_point(team: int, lane: int) -> Vector2:
	var dirn := 1.0 if team == 0 else -1.0
	var best := -INF
	for o in units:
		if o.dead or o.team != team or o.lane != lane:
			continue
		if o.kind == Unit.Kind.CREEP or o.kind == Unit.Kind.RANGED:
			best = max(best, o.lane_s * dirn)
	var s: float
	if best > -INF:
		s = best * dirn - dirn * 3.0
	else:
		var tb := -INF
		for t in towers[team]:
			if t.lane == lane:
				tb = max(tb, t.lane_s * dirn)
		if tb > -INF:
			s = tb * dirn + dirn * 2.5
		else:
			s = (8.0 if team == 0 else lane_len[lane] - 8.0)
	return lane_point(lane, s) - lane_normal(lane, s) * dirn * 1.5


func enemy_creeps_in_lane(team: int, lane: int) -> int:
	var n := 0
	for o in units:
		if not o.dead and o.team == 1 - team and o.lane == lane and (o.kind == Unit.Kind.CREEP or o.kind == Unit.Kind.RANGED):
			n += 1
	return n


func call_tower_help(victim, attacker) -> void:
	if attacker.team == 2:
		return
	for s in structures_of(victim.team):
		if s.dead:
			continue
		if s.dist_to(attacker) <= s.atk_range + attacker.radius:
			s.target = attacker


## Tier-2 towers are protected until the tier-1 of their lane falls;
## the base is protected until one whole lane (both towers) is down.
func update_invulnerability() -> void:
	for team in 2:
		var lane_open := false
		for lane in 3:
			var has1 := false
			var has2 := false
			for t in towers[team]:
				if t.lane == lane:
					if t.tier == 1:
						has1 = true
					else:
						has2 = true
			for t in towers[team]:
				if t.lane == lane and t.tier == 2:
					t.invulnerable = has1
			if not has1 and not has2:
				lane_open = true
		bases[team].invulnerable = not lane_open


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
	if h.is_player or h.dist_to(player) < 20:
		fx.add_text(h.position, "+FORÇA", Color(1, 0.85, 0.3))


func on_unit_died(u, src) -> void:
	var killer = null
	if src != null and is_instance_valid(src) and src.kind == Unit.Kind.HERO and src.team != u.team:
		killer = src
		src.gold += u.bounty
		if u.kind != Unit.Kind.HERO and src.is_player:
			fx.add_text(u.position, "+%d" % u.bounty, Color(1, 0.85, 0.2))
	var xp_team := -1
	if killer != null:
		xp_team = killer.team
	elif u.team < 2:
		xp_team = 1 - u.team
	if xp_team >= 0:
		var near: Array = []
		for h in heroes:
			if h.team == xp_team and not h.dead and h.dist_to(u) < 14.0:
				near.append(h)
		for h in near:
			h.add_xp(u.xp_value * (1.0 if near.size() == 1 else 1.4 / near.size()))
	match u.kind:
		Unit.Kind.HERO:
			if src != null and is_instance_valid(src) and src.team < 2 and src.team != u.team:
				team_kills[src.team] += 1
				if src.kind == Unit.Kind.HERO:
					src.kills += 1
			u.bounty = 200 + 20 * u.level
			u.xp_value = 120 + 40 * u.level
			u.start_respawn()
			fx.add_text(u.position, "ABATIDO!", Color.WHITE)
			for h in heroes:
				if h.kit == "acougueiro" and h.team != u.team and not h.dead and (h == src or h.dist_to(u) < 12.0):
					h.flesh_feed()
		Unit.Kind.TOWER:
			if autotest:
				print("  TOWER DOWN t=%d team=%d lane=%d tier=%d by=%s" % [game_time, u.team, u.lane, u.tier, (src.name + "/" + str(src.kind) + "/" + str(src.team)) if src != null and is_instance_valid(src) else "?"])
			towers[u.team].erase(u)
			for h in heroes:
				if h.team != u.team:
					h.gold += 150
			if u.dist_to(player) < 30:
				shake(0.4)
			update_invulnerability()
		Unit.Kind.BASE:
			shake(0.8)
			end_game(u.team == 1)


func end_game(won: bool) -> void:
	game_over = true
	if autotest:
		print("GAME OVER won=%s t=%d kills=%d/%d" % [won, game_time, team_kills[0], team_kills[1]])
		get_tree().quit()
		return
	hud.show_end(won)
	get_tree().paused = true


func _picktest() -> void:
	await get_tree().create_timer(2.0, true).timeout
	print("PICKTEST pressing")
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.position = hud.pick_rect(3).get_center()
	Input.parse_input_event(ev)


func _picktest_after() -> void:
	await get_tree().create_timer(3.0, true).timeout
	print("PICKTEST alive hero=", player.hero_name, " picking=", picking, " paused=", get_tree().paused)
	get_tree().quit()


func pick_hero(k: String) -> void:
	picked = k
	picking = false
	restart()


func change_hero() -> void:
	picking = true
	restart()


var reloading := false


func restart() -> void:
	if reloading:
		return
	reloading = true
	get_viewport().set_input_as_handled()
	_do_reload.call_deferred()


func _do_reload() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- screenshot / benchmark
## Puts the player in a mid-lane fight near the river with 3 waves on screen.
func stage_fight(waves: int) -> void:
	var c := lane_point(1, lane_len[1] * 0.5)
	player.set_p2(c + Vector2(-3, 3))
	cam_focus = player.position
	for i in waves:
		spawn_wave()
	var k := 0
	for o in get_tree().get_nodes_in_group("units"):
		if (o.kind == Unit.Kind.CREEP or o.kind == Unit.Kind.RANGED) and o.lane == 1:
			var off := Vector2(-1, 1) * (2.5 if o.team == 0 else -2.5)
			o.set_p2(c + off + Vector2((k % 4) * 0.9, (k % 7) * 0.9 - 3.0))
			o.lane_s = lane_proj(1, o.p2())
			k += 1
	heroes[3].set_p2(c + Vector2(3, -3))


func setup_shot() -> void:
	if shot_mode == "close" or shot_mode == "skills":
		cam_zoom = 0.6
	if shot_mode == "far":
		cam_zoom = 3.2
	if shot_mode == "hook":
		cam_zoom = 0.75
	stage_fight(2)
	update_camera(1.0)
	await get_tree().create_timer(1.5).timeout
	if shot_mode == "hook":
		# enemy hero 8 m away in the open, then throw and record frames of the pull
		var foe = heroes[3]
		foe.is_bot = false
		var c: Vector2 = player.p2() + Vector2(-5.5, -5.5)
		for o in units:
			if o != player and o != foe and not o.dead and o.is_mobile() and o.p2().distance_to(player.p2()) < 12.0:
				o.set_p2(o.p2() + Vector2(9, 9))
		foe.set_p2(c)
		hud.help_time = 0.0
		for f0 in 4:
			await get_tree().create_timer(0.05).timeout
			get_viewport().get_texture().get_image().save_png("/tmp/hookpre_%02d.png" % f0)
		player.aim_override = (foe.p2() - player.p2()).normalized()
		player.cast(0)
		for f in 22:
			await get_tree().create_timer(0.045).timeout
			get_viewport().get_texture().get_image().save_png("/tmp/hook_%02d.png" % f)
		print("HOOK FRAMES SAVED dist=%.1f" % player.dist_to(foe))
		get_tree().quit()
		return
	if shot_mode == "skills":
		player.level = 3
		player.cast(2)
		await get_tree().create_timer(0.3).timeout
		player.facing = (heroes[3].p2() - player.p2()).normalized()
		player.cast(3 if not "--q" in OS.get_cmdline_user_args() else 0)
		await get_tree().create_timer(0.5 if player.kit == "elfo" or player.kit == "orca" else 0.12).timeout
	else:
		player.cast(0)
		await get_tree().create_timer(0.3).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/shot_%s.png" % shot_mode)
	print("SHOT SAVED")
	get_tree().quit()


func run_bench() -> void:
	player.is_bot = true
	stage_fight(3)
	await get_tree().create_timer(2.0).timeout
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var calls := 0.0
	var proc := 0.0
	var phys := 0.0
	while Time.get_ticks_usec() - t0 < 10000000:
		await get_tree().process_frame
		frames += 1
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var secs := (Time.get_ticks_usec() - t0) / 1000000.0
	print("BENCH fps=%.1f draw_calls=%.0f process_ms=%.2f physics_ms=%.2f units=%d" % [frames / secs, calls / frames, proc / frames * 1000.0, phys / frames * 1000.0, get_tree().get_nodes_in_group("units").size()])
	get_tree().quit()


func apply_quality() -> void:
	var vp := get_viewport()
	if low_quality:
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 0.65
	else:
		vp.msaa_3d = Viewport.MSAA_2X


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


func recycle(u) -> void:
	u.visible = false
	u.set_physics_process(false)
	var key: String = ["hero", "creep", "ranged", "tower", "base"][u.kind] + str(u.team)
	if not creep_pool.has(key):
		creep_pool[key] = []
	creep_pool[key].append(u)


# ---------------------------------------------------------------- mesh merging (fewer draw calls)
func merge_skinned(model: Node3D, cfg: Dictionary) -> void:
	var parts: Array = []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.skin != null and mi.transform.is_equal_approx(Transform3D()):
			parts.append(mi)
	if parts.size() < 2:
		return
	var key: String = cfg["scene"].resource_path + str(cfg.get("hide", []))
	if not merged_cache.has(key):
		var skin0: Skin = parts[0].skin
		var by_mat := {}
		for mi in parts:
			var sk: Skin = mi.skin
			if sk.get_bind_count() != skin0.get_bind_count():
				return
			for b in sk.get_bind_count():
				if sk.get_bind_bone(b) != skin0.get_bind_bone(b) or sk.get_bind_name(b) != skin0.get_bind_name(b):
					return
			var mat: Material = mi.get_active_material(0)
			if not by_mat.has(mat):
				by_mat[mat] = []
			by_mat[mat].append(mi)
		var am := ArrayMesh.new()
		for mat in by_mat:
			var st := SurfaceTool.new()
			for mi in by_mat[mat]:
				for si in mi.mesh.get_surface_count():
					st.append_from(mi.mesh, si, Transform3D())
			var arrays := st.commit_to_arrays()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			am.surface_set_material(am.get_surface_count() - 1, mat)
		merged_cache[key] = [am, skin0]
	var data: Array = merged_cache[key]
	var first: MeshInstance3D = parts[0]
	first.mesh = data[0]
	first.skin = data[1]
	for i in range(1, parts.size()):
		parts[i].get_parent().remove_child(parts[i])
		parts[i].free()
