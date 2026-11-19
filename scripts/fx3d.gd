extends Node3D
## 3D visual effects drawn with one small shader (shaders/fx.gdshader) on pooled quads:
## ground rings/novas, glow sprites, fire sprites, light beams. No GPU particles, so the
## cost stays predictable on phones. MAX_ITEMS is the hard budget.

const FX_SHADER := preload("res://shaders/fx.gdshader")
const MAX_ITEMS := 56
const MAX_ITEMS_LOW := 36

var game
var items: Array = []
var flat_mesh: PlaneMesh
var quad_mesh: QuadMesh
var pool := {"flat": [], "quad": []}
static var noise: Texture2D


func _ready() -> void:
	flat_mesh = PlaneMesh.new()
	flat_mesh.size = Vector2(2, 2)
	quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(2, 2)


static func fx_mat(mode: int, c: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FX_SHADER
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("col", c)
	if noise == null:
		noise = load("res://assets/baked/tiles.png")
	m.set_shader_parameter("noise_tex", noise)
	return m


## Flat selection/aura ring for units and fountains.
static func ground_ring_mat(c: Color, fill := 0.12, width := 0.07) -> ShaderMaterial:
	var m := fx_mat(0, c)
	m.set_shader_parameter("ringr", 0.86)
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("fill", fill)
	return m


## Old unlit material, still used for tower crystals.
static func glow_mat(c: Color, energy := 1.3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c.r * energy, c.g * energy, c.b * energy, c.a)
	return m


func budget() -> int:
	return MAX_ITEMS_LOW if game.low_quality else MAX_ITEMS


func _spawn(kind: String, mode: int, c: Color) -> MeshInstance3D:
	var mi: MeshInstance3D
	if pool[kind].size() > 0:
		mi = pool[kind].pop_back()
		mi.visible = true
		mi.scale = Vector3.ONE
		mi.rotation = Vector3.ZERO
	else:
		mi = MeshInstance3D.new()
		mi.mesh = flat_mesh if kind == "flat" else quad_mesh
		mi.material_override = fx_mat(mode, c)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("kind", kind)
		add_child(mi)
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("alpha", 1.0)
	m.set_shader_parameter("ringr", 0.9)
	m.set_shader_parameter("width", 0.08)
	m.set_shader_parameter("swirl", 0.0)
	m.set_shader_parameter("fill", 0.0)
	return mi


func _item(d: Dictionary, optional := false) -> bool:
	if optional and items.size() >= budget():
		d["node"].visible = false
		pool[d["node"].get_meta("kind")].append(d["node"])
		return false
	d["t"] = 0.0
	items.append(d)
	return true


func full() -> bool:
	return items.size() >= budget()


func add_ring(p: Vector3, r: float, c: Color, dur := 0.35, grow := 0.3) -> void:
	if full():
		return
	var mi := _spawn("flat", 0, c)
	mi.position = p + Vector3(0, 0.07, 0)
	_item({"type": "ring", "node": mi, "r": r, "dur": dur, "grow": grow})


## Spinning shockwave: swirl disc expanding to r plus a bright flash in the middle.
func add_nova(p: Vector3, r: float, c: Color, dur := 0.45) -> void:
	var mi := _spawn("flat", 0, c)
	mi.position = p + Vector3(0, 0.08, 0)
	mi.scale = Vector3(r, 1, r)
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("swirl", 1.0)
	m.set_shader_parameter("fill", 0.3)
	m.set_shader_parameter("width", 0.06)
	_item({"type": "nova", "node": mi, "r": r, "dur": dur})
	add_flash(p + Vector3(0, 0.8, 0), r * 0.3, c, dur * 0.4)


func add_flash(p: Vector3, r: float, c: Color, dur := 0.25) -> void:
	if full():
		return
	var mi := _spawn("quad", 1, c)
	mi.position = p
	_item({"type": "flash", "node": mi, "r": r, "dur": dur})


func add_spark(p: Vector3, c: Color, size := 0.5) -> void:
	if full():
		return
	var mi := _spawn("quad", 1, c)
	mi.position = p
	_item({"type": "spark", "node": mi, "s": size, "dur": 0.2})


func add_beam(p: Vector3, r: float, c: Color, dur := 0.6) -> void:
	var mi := _spawn("quad", 3, c)
	mi.position = p + Vector3(0, 6, 0)
	_item({"type": "beam", "node": mi, "r": r, "dur": dur})


## Fúria: a golden swirl that follows the hero while the buff lasts.
func add_aura(u, dur: float, c: Color) -> void:
	var mi := _spawn("flat", 0, c)
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("swirl", 0.8)
	m.set_shader_parameter("fill", 0.25)
	m.set_shader_parameter("ringr", 0.8)
	_item({"type": "aura", "node": mi, "u": u, "r": u.radius * 2.2, "dur": dur})


## Meteoro: warning circle on the ground and a fireball falling onto it.
func add_meteor(p: Vector3, delay: float, r: float) -> void:
	var w := _spawn("flat", 0, Color(1.0, 0.45, 0.15))
	w.position = p + Vector3(0, 0.07, 0)
	w.scale = Vector3(r, 1, r)
	(w.material_override as ShaderMaterial).set_shader_parameter("fill", 0.35)
	_item({"type": "warn", "node": w, "dur": delay})
	var f := _spawn("quad", 2, Color(1, 0.6, 0.2))
	_item({"type": "fall", "node": f, "from": p + Vector3(-5, 18, 5), "to": p + Vector3(0, 1.2, 0), "dur": delay})
	var g := _spawn("quad", 1, Color(1.0, 0.4, 0.1, 0.7))
	_item({"type": "fall", "node": g, "from": p + Vector3(-5, 18, 5), "to": p + Vector3(0, 1.2, 0), "dur": delay, "glow": true})


## Short-lived flames bursting from an impact.
func add_fire(p: Vector3, size: float, dur := 0.6) -> void:
	if full():
		return
	var mi := _spawn("quad", 2, Color(1, 0.6, 0.2))
	mi.position = p + Vector3(0, size * 0.9, 0)
	_item({"type": "fire", "node": mi, "s": size, "dur": dur})


func add_projectile(from: Vector3, target, src, dmg: float, c: Color, speed := 14.0, size := 0.32) -> void:
	var mi := _spawn("quad", 1, c)
	mi.position = from
	mi.scale = Vector3.ONE * size * 1.6
	var tail: MeshInstance3D = null
	if not game.low_quality or size > 0.4:
		tail = _spawn("quad", 1, c)
		tail.position = from
		tail.scale = Vector3.ONE * size * 1.1
		(tail.material_override as ShaderMaterial).set_shader_parameter("alpha", 0.45)
	items.append({"type": "proj", "node": mi, "tail": tail, "target": target, "src": src, "dmg": dmg, "speed": speed, "c": c, "t": 0.0, "dur": 5.0, "size": size})


func add_text(p: Vector3, text: String, c: Color) -> void:
	game.hud_texts.append({"p": p, "text": text, "c": c, "t": 0.0, "dur": 1.2})


func _release(node: MeshInstance3D) -> void:
	node.visible = false
	pool[node.get_meta("kind")].append(node)


func _process(delta: float) -> void:
	var keep: Array = []
	for it in items:
		it["t"] += delta
		var k: float = it["t"] / it["dur"]
		var node: MeshInstance3D = it["node"]
		var m: ShaderMaterial = node.material_override
		var done: bool = k >= 1.0
		match it["type"]:
			"ring":
				var s: float = it["r"] * (1.0 + k * it["grow"])
				node.scale = Vector3(s, 1.0, s)
				m.set_shader_parameter("alpha", 1.0 - k)
			"nova":
				var e: float = 1.0 - pow(1.0 - min(k * 1.4, 1.0), 3.0)
				m.set_shader_parameter("ringr", 0.15 + 0.8 * e)
				m.set_shader_parameter("alpha", 1.0 - k * k)
				node.rotation.y = -k * 2.5
			"flash":
				node.scale = Vector3.ONE * it["r"] * (0.6 + k)
				m.set_shader_parameter("alpha", 1.0 - k)
			"spark":
				node.scale = Vector3.ONE * it["s"] * (1.2 + k)
				m.set_shader_parameter("alpha", 1.0 - k)
			"beam":
				var w: float = it["r"] * (1.0 - k * 0.7)
				node.scale = Vector3(w, 6.0, w)
				m.set_shader_parameter("alpha", 1.0 - k)
			"aura":
				var u = it["u"]
				if u == null or not is_instance_valid(u) or u.dead:
					done = true
				else:
					node.position = u.position + Vector3(0, 0.09, 0)
					node.scale = Vector3.ONE * it["r"]
					node.rotation.y += delta * 3.0
					m.set_shader_parameter("alpha", (0.7 + 0.3 * sin(it["t"] * 9.0)) * min(1.0, (1.0 - k) * 4.0))
			"warn":
				m.set_shader_parameter("alpha", 0.5 + 0.5 * sin(it["t"] * 22.0))
				m.set_shader_parameter("ringr", 0.95 - 0.1 * k)
			"fall":
				node.position = it["from"].lerp(it["to"], k * k)
				node.scale = Vector3.ONE * (1.7 if it.get("glow", false) else 1.5)
			"fire":
				node.scale = Vector3.ONE * it["s"] * (1.0 - k * 0.5)
				m.set_shader_parameter("alpha", 1.0 - k * k)
			"proj":
				var tgt = it["target"]
				if tgt == null or not is_instance_valid(tgt) or tgt.dead:
					done = true
				else:
					var aim: Vector3 = tgt.global_position + Vector3(0, tgt.hit_height, 0)
					var d: Vector3 = aim - node.position
					var step: float = it["speed"] * delta
					if it["tail"] != null:
						it["tail"].position = it["tail"].position.lerp(node.position, 0.45)
					if d.length() <= step + 0.2:
						done = true
						add_spark(aim, it["c"], 0.7 if it["size"] < 0.4 else 1.1)
						tgt.take_damage(it["dmg"], it["src"] if is_instance_valid(it["src"]) else null)
					else:
						node.position += d.normalized() * step
		if done:
			_release(node)
			if it.get("tail") != null:
				_release(it["tail"])
		else:
			keep.append(it)
	items = keep
