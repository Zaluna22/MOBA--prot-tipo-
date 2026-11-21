extends SceneTree
## Builds the Dota-style towers (Radiant: white stone guardian with blue glow and gold masks;
## Dire: dark basalt with red glow and bone horns) as single meshes with 3 materials.
## Run: godot --headless -s res://tools/build_towers.gd

var rng := RandomNumberGenerator.new()


func noise3(p: Vector3) -> float:
	return sin(p.x * 3.1 + p.y * 1.7) * 0.5 + sin(p.z * 2.7 - p.y * 2.3) * 0.35 + sin((p.x + p.z) * 5.3 + p.y * 4.1) * 0.15


## Revolved profile [(r, y)], squashed in z, with chunky stone noise and a painted height gradient.
func lathe(st: SurfaceTool, prof: Array, segs: int, zs: float, c_lo: Color, c_hi: Color, bump: float) -> void:
	var ymax: float = prof[prof.size() - 1].y
	var rows: Array = []
	for pr in prof:
		var row: Array = []
		for i in segs + 1:
			var a := TAU * float(i % segs) / segs
			var dir := Vector3(sin(a), 0, cos(a))
			var r: float = pr.x
			var p := Vector3(dir.x * r, pr.y, dir.z * r * zs)
			if r > 0.01:
				var n := noise3(p * 1.3) * bump
				p += Vector3(dir.x, 0, dir.z * zs) * n
			row.append(p)
		rows.append(row)
	for j in prof.size() - 1:
		for i in segs:
			var q := [rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]]
			for k in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = q[k]
				var t: float = clampf(v.y / ymax, 0.0, 1.0)
				var c: Color = c_lo.lerp(c_hi, t) * (0.93 + 0.07 * noise3(v * 4.0))
				c.a = 1.0
				st.set_color(c)
				st.add_vertex(v)


## A curved panel hugging the body between two angles/heights (used for the glowing chest plates).
func patch(st: SurfaceTool, r_at: Callable, a0: float, a1: float, y0: float, y1: float, zs: float, off: float, c: Color) -> void:
	var na := 8
	var ny := 6
	var pts := []
	for j in ny + 1:
		var y := lerpf(y0, y1, float(j) / ny)
		var row := []
		var shrink := (1.0 - sin(PI * float(j) / ny)) * 0.22
		for i in na + 1:
			var a := deg_to_rad(lerpf(a0 + (a1 - a0) * shrink, a1 - (a1 - a0) * shrink, float(i) / na))
			var r: float = r_at.call(y) + off
			row.append(Vector3(sin(a) * r, y, cos(a) * r * zs))
		pts.append(row)
	for j in ny:
		for i in na:
			var q := [pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i]]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(c)
				st.add_vertex(q[k])


## Append a primitive mesh (box, cylinder, torus...) transformed, with a flat color.
func prim(st: SurfaceTool, m: PrimitiveMesh, xf: Transform3D, c: Color) -> void:
	var arr := m.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for k in idx.size():
		var v: Vector3 = xf * verts[idx[k]]
		var cc := c * (0.94 + 0.06 * noise3(v * 3.0))
		cc.a = 1.0
		st.set_color(cc)
		st.add_vertex(v)


func box(sx: float, sy: float, sz: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(sx, sy, sz)
	return b


func cyl(top: float, bot: float, h: float, segs := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


func torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 24
	t.ring_segments = 6
	return t


func xf(pos: Vector3, rot_deg := Vector3.ZERO, sc := Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(rot_deg * PI / 180.0).scaled(sc)
	return Transform3D(b, pos)


func finish(st: SurfaceTool, mat: Material, mesh: ArrayMesh) -> void:
	st.generate_normals()
	st.set_material(mat)
	st.commit(mesh)


func build(dire: bool) -> Node3D:
	rng.seed = 7 if dire else 3
	var stone_lo := Color(0.58, 0.58, 0.56) if not dire else Color(0.09, 0.07, 0.08)
	var stone_hi := Color(0.93, 0.92, 0.86) if not dire else Color(0.30, 0.24, 0.24)
	var glow := Color(0.35, 0.85, 1.0) if not dire else Color(1.0, 0.32, 0.08)
	var gold := Color(0.95, 0.72, 0.25) if not dire else Color(0.62, 0.22, 0.12)
	var bone := Color(0.86, 0.8, 0.66)
	var zs := 0.82
	# body profile (radius, height): narrow waist, broad shoulders, neck, head
	var prof := [Vector2(0.80, 0.50), Vector2(0.86, 0.95), Vector2(0.98, 1.55), Vector2(1.06, 1.62),
		Vector2(1.12, 2.15), Vector2(1.28, 2.75), Vector2(1.34, 2.82), Vector2(1.44, 3.40), Vector2(1.40, 3.95),
		Vector2(1.22, 4.45), Vector2(0.92, 4.85), Vector2(0.70, 5.05), Vector2(0.74, 5.20), Vector2(0.82, 5.65),
		Vector2(0.74, 6.10), Vector2(0.50, 6.40), Vector2(0.0, 6.52)]
	if dire:
		prof = [Vector2(0.84, 0.50), Vector2(0.80, 1.00), Vector2(1.00, 1.60), Vector2(1.14, 1.66),
			Vector2(1.10, 2.20), Vector2(1.34, 2.80), Vector2(1.52, 3.45), Vector2(1.50, 3.90),
			Vector2(1.20, 4.45), Vector2(0.86, 4.85), Vector2(0.66, 5.05), Vector2(0.80, 5.30), Vector2(0.86, 5.70),
			Vector2(0.66, 6.15), Vector2(0.30, 6.45), Vector2(0.0, 6.55)]
	var r_at := func(y: float) -> float:
		for i in prof.size() - 1:
			if y >= prof[i].y and y <= prof[i + 1].y:
				return lerpf(prof[i].x, prof[i + 1].x, (y - prof[i].y) / (prof[i + 1].y - prof[i].y))
		return 0.5

	var s_stone := SurfaceTool.new(); s_stone.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s_glow := SurfaceTool.new(); s_glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s_gold := SurfaceTool.new(); s_gold.begin(Mesh.PRIMITIVE_TRIANGLES)

	# pedestal: two octagonal slabs
	var ped := Color(0.72, 0.71, 0.68) if not dire else Color(0.16, 0.13, 0.13)
	prim(s_stone, cyl(1.72, 1.88, 0.30, 8), xf(Vector3(0, 0.15, 0), Vector3(0, 22.5, 0)), ped * 0.85)
	prim(s_stone, cyl(1.42, 1.62, 0.22, 8), xf(Vector3(0, 0.41, 0), Vector3(0, 22.5, 0)), ped)
	prim(s_glow, cyl(1.64, 1.64, 0.04, 8), xf(Vector3(0, 0.31, 0), Vector3(0, 22.5, 0)), glow)

	lathe(s_stone, prof, 20, zs, stone_lo, stone_hi, 0.07)

	# glowing bands where the stone plates meet
	for y in [1.58, 2.78, 4.05, 5.12]:
		var r: float = r_at.call(y) + 0.03
		prim(s_glow, torus(r - 0.07, r + 0.02), xf(Vector3(0, y, 0), Vector3.ZERO, Vector3(1, 0.7, zs)), glow)
	# glowing chest/side plates (left and right of the masks), framed by the stone
	for sgn in [-1.0, 1.0]:
		patch(s_glow, r_at, 24.0 * sgn, 64.0 * sgn, 3.02, 3.85, zs, 0.035, glow * 0.8)
		patch(s_glow, r_at, 34.0 * sgn, 58.0 * sgn, 1.85, 2.50, zs, 0.09, glow * 0.6)
		patch(s_glow, r_at, 30.0 * sgn, 52.0 * sgn, 5.35, 5.85, zs, 0.03, glow * 0.7)

	# stacked masks on the front (gold for Radiant, bronze skulls for Dire) + the face
	for m in [[1.20, 0.34], [2.25, 0.36], [3.35, 0.40], [5.62, 0.50]]:
		var y: float = m[0]
		var w: float = m[1]
		var zf: float = r_at.call(y) * zs + 0.04
		var sp := SphereMesh.new()
		sp.radius = 0.5
		sp.height = 1.0
		sp.radial_segments = 10
		sp.rings = 6
		prim(s_gold, sp, xf(Vector3(0, y, zf), Vector3.ZERO, Vector3(w, w * 1.4, w * 0.5)), gold)
		prim(s_gold, box(w * 1.1, w * 0.16, w * 0.3), xf(Vector3(0, y + w * 0.38, zf + w * 0.1)), gold * 1.1)
		prim(s_gold, cyl(0.0, w * 0.13, w * 0.42, 4), xf(Vector3(0, y + w * 0.02, zf + w * 0.25), Vector3(75, 0, 0)), gold * 0.8)
		prim(s_stone, box(w * 0.5, w * 0.07, 0.05), xf(Vector3(0, y - w * 0.32, zf + w * 0.22)), Color(0.15, 0.1, 0.05))

	if not dire:
		# fan crown of stone blades with glowing spines
		for i in 9:
			var ang := -84.0 + i * 21.0
			var len := 1.65 - absf(ang) / 84.0 * 0.45
			var rot := Vector3(-32, 0, ang)
			var b := Basis.from_euler(rot * PI / 180.0)
			var base := Vector3(0, 6.18, -0.22)
			var center := base + b * Vector3(0, len * 0.5, 0)
			prim(s_stone, box(0.30 + 0.1 * (len - 1.2), len, 0.10), Transform3D(b, center), stone_hi)
			prim(s_glow, box(0.06, len * 0.8, 0.03), Transform3D(b, center + b * Vector3(0, 0, 0.055)), glow)
		prim(s_stone, torus(0.30, 0.62), xf(Vector3(0, 6.2, -0.2), Vector3(70, 0, 0), Vector3(1, 1, 0.5)), stone_hi)
	else:
		# bone horns on the head and spikes on the shoulders
		for sgn in [-1.0, 1.0]:
			prim(s_stone, cyl(0.0, 0.17, 1.30, 6), xf(Vector3(0.45 * sgn, 6.55, -0.05), Vector3(-10, 0, -32 * sgn)), bone)
			prim(s_stone, cyl(0.0, 0.10, 0.70, 6), xf(Vector3(0.78 * sgn, 7.05, -0.05), Vector3(-5, 0, 10 * sgn)), bone)
			for k in 3:
				var y := 3.2 + k * 0.45
				var r: float = r_at.call(y)
				prim(s_stone, cyl(0.0, 0.16, 0.95 - k * 0.15, 6), xf(Vector3((r + 0.25) * sgn, y + 0.15, -0.1 + k * 0.1), Vector3(0, 0, -62 * sgn)), bone)
		prim(s_stone, cyl(0.0, 0.14, 0.9, 6), xf(Vector3(0, 6.8, -0.1), Vector3(-15, 0, 0)), bone)

	var mesh := ArrayMesh.new()
	var m_stone := StandardMaterial3D.new()
	m_stone.vertex_color_use_as_albedo = true
	m_stone.roughness = 0.85
	var m_glow := StandardMaterial3D.new()
	m_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_glow.vertex_color_use_as_albedo = true
	m_glow.albedo_color = Color(1.6, 1.6, 1.6)
	var m_gold := StandardMaterial3D.new()
	m_gold.vertex_color_use_as_albedo = true
	m_gold.metallic = 0.6
	m_gold.roughness = 0.35
	m_gold.emission_enabled = true
	m_gold.emission = gold * 0.25
	finish(s_stone, m_stone, mesh)
	finish(s_glow, m_glow, mesh)
	finish(s_gold, m_gold, mesh)

	var root := Node3D.new()
	root.name = "TowerDire" if dire else "TowerRadiant"
	var mi := MeshInstance3D.new()
	mi.name = "Tower"
	mi.mesh = mesh
	root.add_child(mi)
	mi.owner = root
	return root


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/towers")
	for dire in [false, true]:
		var root := build(dire)
		var ps := PackedScene.new()
		ps.pack(root)
		var path := "res://assets/towers/tower_%s.scn" % ("dire" if dire else "radiant")
		var err := ResourceSaver.save(ps, path)
		var am: ArrayMesh = root.get_child(0).mesh
		var tris := 0
		for s in am.get_surface_count():
			tris += am.surface_get_array_len(s) / 3
		print(path, " err=", err, " tris=", tris, " aabb=", am.get_aabb())
		root.free()
	quit()
