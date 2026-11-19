extends Node3D
## 3D visual effects: projectiles, rings, novas, beams, sparks.

var game
var items: Array = []
var torus_mesh: TorusMesh
var disc_mesh: CylinderMesh
var sphere_mesh: SphereMesh
var beam_mesh: CylinderMesh


func _ready() -> void:
	torus_mesh = TorusMesh.new()
	torus_mesh.inner_radius = 0.9
	torus_mesh.outer_radius = 1.0
	torus_mesh.rings = 32
	torus_mesh.ring_segments = 6
	disc_mesh = CylinderMesh.new()
	disc_mesh.top_radius = 1.0
	disc_mesh.bottom_radius = 1.0
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 32
	sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.5
	sphere_mesh.height = 1.0
	sphere_mesh.radial_segments = 12
	sphere_mesh.rings = 6
	beam_mesh = CylinderMesh.new()
	beam_mesh.top_radius = 1.0
	beam_mesh.bottom_radius = 1.0
	beam_mesh.height = 1.0
	beam_mesh.radial_segments = 20
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false


static func glow_mat(c: Color, energy := 1.3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c.r * energy, c.g * energy, c.b * energy, c.a)
	m.no_depth_test = false
	return m


var pool: Array = []


## Effects reuse pooled MeshInstances (and their materials) instead of
## allocating new nodes every shot.
func _spawn(mesh: Mesh, c: Color, energy := 1.3) -> MeshInstance3D:
	var mi: MeshInstance3D
	if pool.size() > 0:
		mi = pool.pop_back()
		mi.visible = true
		mi.scale = Vector3.ONE
		var m: StandardMaterial3D = mi.material_override
		m.albedo_color = Color(c.r * energy, c.g * energy, c.b * energy, c.a)
	else:
		mi = MeshInstance3D.new()
		mi.material_override = glow_mat(c, energy)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	mi.mesh = mesh
	return mi


func add_ring(p: Vector3, r: float, c: Color, dur := 0.35, grow := 0.3) -> void:
	var mi := _spawn(torus_mesh, c)
	mi.position = p + Vector3(0, 0.08, 0)
	items.append({"type": "ring", "node": mi, "r": r, "t": 0.0, "dur": dur, "grow": grow, "c": c})


func add_nova(p: Vector3, r: float, c: Color, dur := 0.45) -> void:
	add_ring(p, r, c, dur, 0.0)
	var mi := _spawn(disc_mesh, Color(c, 0.15), 1.2)
	mi.position = p + Vector3(0, 0.06, 0)
	items.append({"type": "disc", "node": mi, "r": r, "t": 0.0, "dur": dur, "c": Color(c, 0.15)})
	var rr := _spawn(torus_mesh, c)
	rr.position = p + Vector3(0, 0.1, 0)
	items.append({"type": "expand", "node": rr, "r": r, "t": 0.0, "dur": dur * 0.8, "c": c})


func add_spark(p: Vector3, c: Color, size := 0.5) -> void:
	var mi := _spawn(sphere_mesh, c, 2.5)
	mi.position = p
	items.append({"type": "spark", "node": mi, "s": size, "t": 0.0, "dur": 0.18, "c": c})


func add_beam(p: Vector3, r: float, c: Color, dur := 0.6) -> void:
	var mi := _spawn(beam_mesh, Color(c, 0.6), 2.5)
	mi.position = p + Vector3(0, 6, 0)
	items.append({"type": "beam", "node": mi, "r": r, "t": 0.0, "dur": dur, "c": Color(c, 0.6)})


func add_projectile(from: Vector3, target, src, dmg: float, c: Color, speed := 14.0, size := 0.32) -> void:
	var mi := _spawn(sphere_mesh, c, 2.5)
	mi.position = from
	mi.scale = Vector3.ONE * size
	items.append({"type": "proj", "node": mi, "target": target, "src": src, "dmg": dmg, "speed": speed, "c": c, "t": 0.0, "dur": 5.0})


func add_text(p: Vector3, text: String, c: Color) -> void:
	game.hud_texts.append({"p": p, "text": text, "c": c, "t": 0.0, "dur": 1.2})


func _process(delta: float) -> void:
	var keep: Array = []
	for it in items:
		it["t"] += delta
		var k: float = it["t"] / it["dur"]
		var node: MeshInstance3D = it["node"]
		var done: bool = k >= 1.0
		match it["type"]:
			"ring":
				var s: float = it["r"] * (1.0 + k * it["grow"])
				node.scale = Vector3(s, 1.0, s)
				_fade(node, it["c"], 1.0 - k)
			"disc":
				node.scale = Vector3(it["r"], 1.0, it["r"])
				_fade(node, it["c"], 1.0 - k)
			"expand":
				var s2: float = max(0.05, it["r"] * k)
				node.scale = Vector3(s2, 2.0, s2)
				_fade(node, it["c"], 1.0 - k * 0.6)
			"spark":
				node.scale = Vector3.ONE * it["s"] * (1.0 + k)
				_fade(node, it["c"], 1.0 - k)
			"beam":
				var w: float = it["r"] * (1.0 - k * 0.7)
				node.scale = Vector3(w, 12.0, w)
				_fade(node, it["c"], 1.0 - k)
			"proj":
				var tgt = it["target"]
				if tgt == null or not is_instance_valid(tgt) or tgt.dead:
					done = true
				else:
					var aim: Vector3 = tgt.global_position + Vector3(0, tgt.hit_height, 0)
					var d: Vector3 = aim - node.position
					var step: float = it["speed"] * delta
					if d.length() <= step + 0.2:
						done = true
						add_spark(aim, it["c"], 0.6)
						tgt.take_damage(it["dmg"], it["src"] if is_instance_valid(it["src"]) else null)
					else:
						node.position += d.normalized() * step
		if done:
			node.visible = false
			pool.append(node)
		else:
			keep.append(it)
	items = keep


func _fade(node: MeshInstance3D, c: Color, a: float) -> void:
	var m: StandardMaterial3D = node.material_override
	var e: float = 1.3
	m.albedo_color = Color(c.r * e, c.g * e, c.b * e, clamp(c.a * a, 0.0, 1.0))
