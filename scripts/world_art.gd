extends RefCounted
## Stage 3 art pass: baked ("painted") terrain lighting, one-draw-call ground shader
## (grass, dirt shoulders, paved lanes and plazas, animated river), blob shadows,
## braziers, fences on the river crossings and themed props.
## Bake once with:  godot --headless -- --bake   (writes assets/baked/*.png)

const ORIGIN := Vector2(-30, -30)
const SIZE := 200.0
const N := 512
const SUN_ROT := Vector3(-50, -35, 0)
const BAKE_DIR := "res://assets/baked/"

var game
var blob_mm: MultiMesh


func _init(g) -> void:
	game = g


# ---------------------------------------------------------------- shared layout
func tower_spots() -> Array:
	var out: Array = []
	for team in 2:
		for lane in 3:
			var L: float = game.lane_len[lane]
			for tier in [1, 2]:
				var s: float = L * 0.38 if tier == 1 else 24.0
				if team == 1:
					s = L - s
				var side := 3.4 if tier == 1 else -3.4
				out.append({"team": team, "lane": lane, "tier": tier, "s": s,
					"pos": game.lane_point(lane, s) + game.lane_normal(lane, s) * side, "side": side})
	return out


func river_cross_s(lane: int) -> float:
	var prev := 0.0
	var s := 0.0
	var L: float = game.lane_len[lane]
	var p0: Vector2 = game.lane_point(lane, 0.0)
	prev = game.river_v(p0)
	while s < L:
		s += 0.5
		var p: Vector2 = game.lane_point(lane, s)
		var v: float = game.river_v(p)
		if sign(v) != sign(prev):
			return s
		prev = v
	return L * 0.5


func plaza_center(team: int) -> Vector2:
	return (game.BASE_POS[team] + game.FOUNTAIN_POS[team]) / 2.0


## Braziers: flanking each river crossing, beside each tower, at each base exit.
func brazier_points() -> Array:
	var out: Array = []
	var hw: float = game.LANE_W / 2.0 + 0.4
	for lane in 3:
		var sc := river_cross_s(lane)
		for ds in [-6.0, 6.0]:
			for side in [-1.0, 1.0]:
				out.append(game.lane_point(lane, sc + ds) + game.lane_normal(lane, sc + ds) * side * hw)
	for t in tower_spots():
		var s: float = t["s"]
		out.append(game.lane_point(t["lane"], s + 3.0) + game.lane_normal(t["lane"], s + 3.0) * sign(t["side"]) * hw)
	for team in 2:
		for lane in 3:
			var s: float = 13.0 if team == 0 else game.lane_len[lane] - 13.0
			for side in [-1.0, 1.0]:
				out.append(game.lane_point(lane, s) + game.lane_normal(lane, s) * side * hw)
	return out


## Stone fences along both lane edges across the river ([pos, yaw]).
func fence_points() -> Array:
	var out: Array = []
	return out  # Stage 4: fences removed (read as rubble); fords are paved instead
	var hw: float = game.LANE_W / 2.0 + 0.4
	for lane in 3:
		var sc := river_cross_s(lane)
		for ds in [-3.4, 0.0, 3.4]:
			var s: float = sc + ds
			var d: Vector2 = game.lane_dir(lane, s)
			for side in [-1.0, 1.0]:
				out.append([game.lane_point(lane, s) + game.lane_normal(lane, s) * side * hw, atan2(-d.y, d.x)])
	return out


# ---------------------------------------------------------------- bake
func sun_shadow_dir() -> Vector2:
	var b := Basis.from_euler(Vector3(deg_to_rad(SUN_ROT.x), deg_to_rad(SUN_ROT.y), 0))
	var l := -b.z
	return Vector2(l.x, l.z) / max(0.05, -l.y)


func bake() -> void:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BAKE_DIR))
	bake_tiles()
	var px := SIZE / N
	var jn := FastNoiseLite.new()
	jn.seed = 5
	jn.frequency = 0.12
	var splat := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var lr := PackedFloat32Array()
	var lg := PackedFloat32Array()
	var lb := PackedFloat32Array()
	var sh := PackedFloat32Array()
	lr.resize(N * N); lg.resize(N * N); lb.resize(N * N); sh.resize(N * N)
	var spots := tower_spots()
	var crossings: Array = []
	for lane in 3:
		crossings.append(game.lane_point(lane, river_cross_s(lane)))
	for j in N:
		for i in N:
			var p := ORIGIN + Vector2(i + 0.5, j + 0.5) * px
			var jit := jn.get_noise_2d(p.x, p.y)
			var dl: float = game.dist_to_lanes(p)
			var dirt := 1.0 - smoothstep(game.LANE_W * 0.5 - 0.4, game.LANE_W * 0.5 + 1.4, dl + jit * 0.9)
			var stone := 1.0 - smoothstep(3.0, 3.5, dl + jit * 0.25)
			for team in 2:
				var dp := p.distance_to(plaza_center(team))
				stone = max(stone, 1.0 - smoothstep(13.2, 14.4, dp + jit * 0.8))
				dirt = max(dirt, 1.0 - smoothstep(14.5, 17.5, dp + jit * 1.5))
			for t in spots:
				var dt: float = p.distance_to(t["pos"])
				stone = max(stone, 1.0 - smoothstep(2.6, 3.1, dt))
				dirt = max(dirt, 1.0 - smoothstep(3.2, 4.8, dt + jit))
			for c in game.CAMP_POS:
				dirt = max(dirt, 1.0 - smoothstep(4.0, 6.0, p.distance_to(c) + jit * 1.2))
			var uv: Vector2 = game.river_uv(p)
			var dr: float = abs(uv.y - game.river_off(uv.x))
			var rh: float = game.river_hw(uv.x)
			var water := 1.0 - smoothstep(rh - 0.9, rh + 0.7, dr + jit * 0.9)
			water *= 1.0 - stone * 0.9  # paved fords across the river
			var jungle := smoothstep(6.0, 16.0, dl) * (1.0 - dirt)
			# keep the alpha above 0 so the importer's alpha-border fix never touches RGB
			splat.set_pixel(i, j, Color(dirt, stone, water, 0.1 + 0.9 * jungle))
			# painted light: lanes a touch brighter and warmer, jungle cooler and dimmer
			var lit := 1.0 - smoothstep(4.0, 14.0, dl)
			var k := i + j * N
			lr[k] = lerp(0.78, 1.04, lit)
			lg[k] = lerp(0.86, 1.0, lit)
			lb[k] = lerp(0.98, 0.92, lit)
			sh[k] = 1.0
			# everything outside the playable square sinks into shade
			var out: float = max(max(-p.x, p.x - game.MAP), max(-p.y, p.y - game.MAP))
			sh[k] *= 1.0 - 0.55 * smoothstep(-6.0, 6.0, out)
			if water > 0.0:
				lb[k] += 0.08 * water
	# soft cast shadows (capsules stretched away from the sun)
	var sd := sun_shadow_dir()
	for o in game.obstacles:
		_shadow(sh, o[0], o[0] + sd * 4.8, o[1] * 1.35, 0.5)
	for t in spots:
		_shadow(sh, t["pos"], t["pos"] + sd * 7.5, 1.6, 0.55)
	for team in 2:
		_shadow(sh, game.BASE_POS[team], game.BASE_POS[team] + sd * 9.0, 3.8, 0.55)
	for f in fence_points():
		_shadow(sh, f[0], f[0] + sd * 0.8, 1.2, 0.25)
	for b in brazier_points():
		_shadow(sh, b, b + sd * 1.4, 0.6, 0.35)
	for c in game.CAMP_POS:
		_shadow(sh, c, c, 7.0, 0.12)
	# warm fire pools and team light at the fountains
	for b in brazier_points():
		_add_light(lr, lg, lb, b, 5.0, Color(1.0, 0.55, 0.2) * 0.75)
	for team in 2:
		var tc: Color = [Color(0.3, 0.6, 1.0), Color(1.0, 0.35, 0.3)][team]
		_add_light(lr, lg, lb, game.FOUNTAIN_POS[team], 12.0, tc * 0.45)
	for c in game.CAMP_POS:
		_add_light(lr, lg, lb, c, 6.0, Color(0.9, 0.75, 0.35) * 0.25)
	var light := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for j in N:
		for i in N:
			var k := i + j * N
			var s := sh[k]
			light.set_pixel(i, j, Color(clamp(lr[k] * s * 0.5, 0, 1), clamp(lg[k] * s * 0.5, 0, 1), clamp(lb[k] * s * 0.5, 0, 1), 1.0))
	splat.save_png(BAKE_DIR + "splat.png")
	light.save_png(BAKE_DIR + "light.png")
	print("BAKED in %d ms" % (Time.get_ticks_msec() - t0))


func _px(p: Vector2) -> Vector2:
	return (p - ORIGIN) / (SIZE / N)


func _shadow(sh: PackedFloat32Array, a: Vector2, b: Vector2, r: float, strength: float) -> void:
	var pa := _px(a)
	var pb := _px(b)
	var rp := r / (SIZE / N)
	var x0 := int(max(0, min(pa.x, pb.x) - rp * 2))
	var x1 := int(min(N - 1, max(pa.x, pb.x) + rp * 2))
	var y0 := int(max(0, min(pa.y, pb.y) - rp * 2))
	var y1 := int(min(N - 1, max(pa.y, pb.y) + rp * 2))
	var ab := pb - pa
	var len2: float = max(ab.length_squared(), 0.0001)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var q := Vector2(x, y)
			var t: float = clamp((q - pa).dot(ab) / len2, 0.0, 1.0)
			var d := q.distance_to(pa + ab * t) / rp
			if d < 1.6:
				var f := 1.0 - smoothstep(0.35, 1.6, d)
				var k := x + y * N
				sh[k] = min(sh[k], 1.0 - strength * f)


func _add_light(lr, lg, lb, c: Vector2, r: float, col: Color) -> void:
	var pc := _px(c)
	var rp := r / (SIZE / N)
	for y in range(int(max(0, pc.y - rp)), int(min(N - 1, pc.y + rp)) + 1):
		for x in range(int(max(0, pc.x - rp)), int(min(N - 1, pc.x + rp)) + 1):
			var d := Vector2(x, y).distance_to(pc) / rp
			if d < 1.0:
				var f := (1.0 - d) * (1.0 - d)
				var k := x + y * N
				lr[k] += col.r * f
				lg[k] += col.g * f
				lb[k] += col.b * f


## Detail tiles, one grayscale pattern per channel: R grass, G dirt, B paving stones, A soft noise.
func bake_tiles() -> void:
	var T := 256
	var g := FastNoiseLite.new()
	g.seed = 3; g.frequency = 0.09; g.fractal_octaves = 4
	var d := FastNoiseLite.new()
	d.seed = 9; d.frequency = 0.05; d.fractal_octaves = 5
	var c := FastNoiseLite.new()
	c.noise_type = FastNoiseLite.TYPE_CELLULAR
	c.seed = 4; c.frequency = 0.035; c.fractal_type = FastNoiseLite.FRACTAL_NONE
	c.cellular_jitter = 0.85
	c.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	var cv: FastNoiseLite = c.duplicate()
	cv.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var w := FastNoiseLite.new()
	w.seed = 21; w.frequency = 0.03; w.fractal_octaves = 3
	var gi := g.get_seamless_image(T, T)
	var di := d.get_seamless_image(T, T)
	var ci := c.get_seamless_image(T, T, false, false, 0.1, true)
	var vi := cv.get_seamless_image(T, T, false, false, 0.1, true)
	var wi := w.get_seamless_image(T, T)
	var img := Image.create(T, T, false, Image.FORMAT_RGBA8)
	for y in T:
		for x in T:
			var e := ci.get_pixel(x, y).r
			var st := (1.0 - smoothstep(0.88, 0.99, e)) * (0.65 + 0.35 * vi.get_pixel(x, y).r) * (0.85 + 0.15 * di.get_pixel(x, y).r)
			img.set_pixel(x, y, Color(gi.get_pixel(x, y).r, di.get_pixel(x, y).r, st, max(0.05, wi.get_pixel(x, y).r)))
	img.save_png(BAKE_DIR + "tiles.png")


# ---------------------------------------------------------------- runtime
func build_ground() -> void:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/terrain.gdshader")
	sm.set_shader_parameter("splat", load(BAKE_DIR + "splat.png"))
	sm.set_shader_parameter("light", load(BAKE_DIR + "light.png"))
	sm.set_shader_parameter("tiles", load(BAKE_DIR + "tiles.png"))
	sm.set_shader_parameter("origin", ORIGIN)
	sm.set_shader_parameter("size", SIZE)
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE, SIZE)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(ORIGIN.x + SIZE / 2, 0, ORIGIN.y + SIZE / 2)
	game.add_child(mi)


func xf(p: Vector2, s: float, yaw: float, y := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y))


func build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var E := "res://assets/env/"
	# braziers: stone pillar + bowl (2 multimeshes) and fire sprites (1 multimesh)
	var pts := brazier_points()
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.5, 0.5, 0.52)
	stone.roughness = 1.0
	var pillar := CylinderMesh.new()
	pillar.top_radius = 0.3; pillar.bottom_radius = 0.42; pillar.height = 1.3; pillar.radial_segments = 6; pillar.rings = 1
	pillar.material = stone
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.55; bowl.bottom_radius = 0.3; bowl.height = 0.3; bowl.radial_segments = 6; bowl.rings = 1
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.2, 0.17, 0.15)
	bowl.material = iron
	var fire_q := QuadMesh.new()
	fire_q.size = Vector2(2, 2)
	fire_q.material = game.fx.fx_mat(2, Color(1, 0.6, 0.2))
	var a1: Array = []
	var a2: Array = []
	var a3: Array = []
	for p in pts:
		a1.append(xf(p, 1.0, 0.0, 0.65))
		a2.append(xf(p, 1.0, 0.0, 1.42))
		a3.append(xf(p, 0.55, 0.0, 2.05))
	_mm(pillar, a1)
	_mm(bowl, a2)
	_mm(fire_q, a3)
	# stone fences across the river
	var fx: Array = []
	for f in fence_points():
		fx.append(xf(f[0], 2.3, f[1]))
	game.multimesh(E + "fence_stone_straight.gltf", fx)
	# team flags beside each tower
	var flags := [[], []]
	for t in tower_spots():
		var p: Vector2 = t["pos"] + game.lane_dir(t["lane"], t["s"]) * 2.4
		flags[t["team"]].append(xf(p, 8.0, rng.randf() * TAU))
	# base: barracks, well (fountain), tents, barrels, crates, weapon racks
	var groups := {}
	for k in ["barracks_blue", "barracks_red", "well_blue", "well_red", "tent", "barrel", "crate_A_big", "weaponrack", "waterlily_A", "waterplant_A", "rock_single_D", "trees_A_small"]:
		groups[k] = []
	for team in 2:
		var tn: String = ["blue", "red"][team]
		var corner := Vector2(0, game.MAP) if team == 0 else Vector2(game.MAP, 0)
		var pc := plaza_center(team)
		var away := (corner - pc).normalized()
		var perp := Vector2(-away.y, away.x)
		groups["barracks_" + tn].append(xf(pc + perp * 11.0 + away * 3.0, 3.6, atan2(away.x, away.y)))
		groups["barracks_" + tn].append(xf(pc - perp * 11.0 + away * 3.0, 3.6, atan2(away.x, away.y)))
		groups["well_" + tn].append(xf(game.FOUNTAIN_POS[team] + away * 3.0, 3.2, 0.3))
		for i in 6:
			var a := TAU * i / 6.0 + 0.4
			var p := pc + Vector2(cos(a), sin(a)) * 15.6
			if game.dist_to_lanes(p) < game.LANE_W * 0.5 + 1.0:
				continue
			var k2: String = ["barrel", "crate_A_big", "weaponrack"][i % 3]
			groups[k2].append(xf(p, 4.0, rng.randf() * TAU))
			groups["barrel"].append(xf(p + Vector2(1.1, 0.6), 3.6, rng.randf() * TAU))
		flags[team].append(xf(game.BASE_POS[team] + perp * 5.0, 10.0, 0.0))
		flags[team].append(xf(game.BASE_POS[team] - perp * 5.0, 10.0, 0.0))
	# neutral camps: a tent and supplies at the clearing edge
	for c in game.CAMP_POS:
		var away2: Vector2 = (c - Vector2(game.MAP / 2, game.MAP / 2)).normalized()
		if away2 == Vector2.ZERO:
			away2 = Vector2.RIGHT
		groups["tent"].append(xf(c + away2 * 4.6, 5.0, atan2(-away2.x, -away2.y)))
		groups["crate_A_big"].append(xf(c + away2.rotated(0.9) * 4.4, 4.5, rng.randf() * TAU))
		groups["barrel"].append(xf(c + away2.rotated(-0.9) * 4.4, 4.0, rng.randf() * TAU))
	# river life along the meander, away from the crossings
	var t := -105.0
	while t < 105.0:
		var on: Vector2 = game.river_point(t)
		var hw2: float = game.river_hw(t)
		var near_cross := false
		for lane in 3:
			if on.distance_to(game.lane_point(lane, river_cross_s(lane))) < 9.0:
				near_cross = true
		if not near_cross:
			var pv := rng.randf_range(-0.7, 0.7) * hw2
			groups["waterlily_A" if rng.randf() < 0.6 else "waterplant_A"].append(xf(game.river_point(t, pv), rng.randf_range(4.0, 6.0), rng.randf() * TAU, 0.02))
			if rng.randf() < 0.55:
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				groups["rock_single_D"].append(xf(game.river_point(t, side * (hw2 + 0.9)), rng.randf_range(3.5, 6.0), rng.randf() * TAU))
		t += rng.randf_range(3.5, 6.0)
	# bushes at the jungle edge of the lanes
	for lane in 3:
		var s := 8.0
		while s < game.lane_len[lane] - 8.0:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var p: Vector2 = game.lane_point(lane, s) + game.lane_normal(lane, s) * side * (game.LANE_W / 2.0 + 2.6)
			if game.river_depth(p) > 1.8 and p.distance_to(plaza_center(0)) > 18.0 and p.distance_to(plaza_center(1)) > 18.0:
				groups["trees_A_small"].append(xf(p, rng.randf_range(1.6, 2.2), rng.randf() * TAU))
			s += rng.randf_range(7.0, 12.0)
	game.multimesh(E + "flag_blue.gltf", flags[0])
	game.multimesh(E + "flag_red.gltf", flags[1])
	for k in groups:
		if groups[k].size() > 0:
			var path: String = E + ("building_" + k if k.begins_with("barracks") or k.begins_with("well") else k) + ".gltf"
			game.multimesh(path, groups[k])


func _mm(mesh: Mesh, xforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(mmi)


# ---------------------------------------------------------------- blob shadows
func build_blobs() -> void:
	var q := PlaneMesh.new()
	q.size = Vector2(2, 2)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/blob.gdshader")
	q.material = m
	blob_mm = MultiMesh.new()
	blob_mm.transform_format = MultiMesh.TRANSFORM_3D
	blob_mm.mesh = q
	blob_mm.instance_count = 160
	blob_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = blob_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 400.0
	game.add_child(mmi)


func update_blobs() -> void:
	var n := 0
	var c := Vector2(game.cam_focus.x, game.cam_focus.z)
	for u in game.units:
		if n >= 160:
			break
		if u.dead or not u.visible or u.kind >= 3:
			continue
		var p: Vector2 = u.p2()
		if c.distance_squared_to(p) > 40.0 * 40.0:
			continue
		var s: float = u.radius * (2.4 if u.kind == 0 else 2.0)
		blob_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(s, 1, s)), Vector3(p.x, 0.03, p.y)))
		n += 1
	blob_mm.visible_instance_count = n
