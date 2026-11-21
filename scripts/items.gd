extends RefCounted
## Loja: item data + buy/sell/use logic. Heroes carry 6 slots (Dictionary {"id", "n", "cd"} or null).

const SLOTS := 6
const SHOP_R := 13.0  # buy/sell only this close to your own fountain
const SELL_BACK := 0.5

## stat keys: dmg, hp, regen, ms (move-speed mult), as (attack-speed mult), cdr (skill cd reduction), ls (life steal), armor (damage taken reduction)
const ITEMS := {
	"botas": {"name": "Botas", "short": "BOT", "cost": 300, "col": Color(0.75, 0.55, 0.3), "stats": {"ms": 0.25},
		"desc": "+25% velocidade"},
	"pocao": {"name": "Poção", "short": "POÇ", "cost": 60, "col": Color(0.9, 0.3, 0.35), "consumable": true, "max": 5,
		"active": true, "cd": 1.0, "desc": "Cura 300 em 8s"},
	"tp": {"name": "TP", "short": "TP", "cost": 100, "col": Color(0.4, 0.75, 1.0), "consumable": true, "max": 3,
		"active": true, "cd": 1.0, "desc": "Volta à base em 3s"},
	"sentinela": {"name": "Sentinela", "short": "SEN", "cost": 75, "col": Color(1.0, 0.9, 0.3), "consumable": true, "max": 3,
		"active": true, "cd": 1.0, "desc": "Revela o mato por 90s"},
	"espada": {"name": "Espada Longa", "short": "ESP", "cost": 450, "col": Color(0.8, 0.85, 0.95), "stats": {"dmg": 15},
		"desc": "+15 de dano"},
	"coracao": {"name": "Coração Troll", "short": "COR", "cost": 500, "col": Color(0.4, 0.85, 0.4), "stats": {"hp": 250, "regen": 4.0},
		"desc": "+250 vida, +4 regen"},
	"luvas": {"name": "Luvas Pressa", "short": "LUV", "cost": 450, "col": Color(1.0, 0.65, 0.25), "stats": {"as": 0.2},
		"desc": "+20% vel. de ataque"},
	"blink": {"name": "Adaga Blink", "short": "BLK", "cost": 1400, "col": Color(0.55, 0.8, 1.0), "active": true, "cd": 14.0,
		"desc": "Teleporte de 8m"},
	"cetro": {"name": "Cetro Arcano", "short": "CET", "cost": 1600, "col": Color(0.3, 0.5, 1.0), "stats": {"cdr": 0.25, "hp": 150},
		"desc": "-25% recarga, +150 vida"},
	"bkb": {"name": "Machado Negro", "short": "BKB", "cost": 1800, "col": Color(0.25, 0.22, 0.2), "active": true, "cd": 40.0,
		"desc": "Imune a controle por 5s"},
	"satanico": {"name": "Satânico", "short": "SAT", "cost": 1700, "col": Color(0.75, 0.1, 0.15), "stats": {"dmg": 20, "ls": 0.2},
		"desc": "+20 dano, 20% roubo vida"},
}
const ORDER := ["botas", "pocao", "tp", "sentinela", "espada", "coracao", "luvas", "blink", "cetro", "bkb", "satanico"]

## Bot shopping routes (ranged kits vs. melee kits).
const ROUTE_RANGED := ["pocao", "botas", "espada", "luvas", "cetro", "satanico"]
const ROUTE_MELEE := ["pocao", "botas", "coracao", "espada", "bkb", "blink"]
const RANGED_KITS := ["elfo", "elfa", "orca"]
## Assassina: attack speed + damage carry (lifesteal fits the crits), BKB late.
const ROUTE_CARRY := ["pocao", "botas", "luvas", "espada", "satanico", "bkb"]


static func near_shop(game, h) -> bool:
	return h.p2().distance_to(game.fountain_pos(h.team)) < SHOP_R


static func slot_of(h, id: String) -> int:
	for i in SLOTS:
		if h.items[i] != null and h.items[i]["id"] == id:
			return i
	return -1


static func free_slot(h) -> int:
	for i in SLOTS:
		if h.items[i] == null:
			return i
	return -1


## Why the hero can't buy it right now ("" = can buy).
static func buy_block(game, h, id: String) -> String:
	var it: Dictionary = ITEMS[id]
	if h.dead:
		return "morto"
	if not h.is_bot and not near_shop(game, h):
		return "volte à base"
	if h.gold < it["cost"]:
		return "ouro"
	if it.get("consumable", false):
		var s := slot_of(h, id)
		if s >= 0:
			return "máx" if h.items[s]["n"] >= it["max"] else ""
	elif slot_of(h, id) >= 0:
		return "já tem"
	if free_slot(h) < 0:
		return "cheio"
	return ""


static func buy(game, h, id: String) -> bool:
	if buy_block(game, h, id) != "":
		return false
	var it: Dictionary = ITEMS[id]
	h.gold -= it["cost"]
	var s := slot_of(h, id) if it.get("consumable", false) else -1
	if s >= 0:
		h.items[s]["n"] += 1
	else:
		h.items[free_slot(h)] = {"id": id, "n": 1, "cd": 0.0}
		_apply(h, it.get("stats", {}), 1.0)
	if h.is_player or h.dist_to(game.player) < 20:
		game.fx.add_text(h.position, it["name"], Color(1, 0.85, 0.3))
	return true


static func sell(game, h, slot: int) -> bool:
	var e = h.items[slot]
	if e == null or (not h.is_bot and not near_shop(game, h)):
		return false
	var it: Dictionary = ITEMS[e["id"]]
	h.gold += int(it["cost"] * SELL_BACK) * e["n"]
	_apply(h, it.get("stats", {}), -1.0)
	h.items[slot] = null
	return true


static func _apply(h, st: Dictionary, k: float) -> void:
	h.dmg += st.get("dmg", 0.0) * k
	var hp_add: float = st.get("hp", 0.0) * k
	h.max_hp += hp_add
	h.hp = clamp(h.hp + hp_add, 1.0, h.max_hp)
	h.regen += st.get("regen", 0.0) * k
	h.item_ms += st.get("ms", 0.0) * k
	h.item_as += st.get("as", 0.0) * k
	h.item_cdr += st.get("cdr", 0.0) * k
	h.item_ls += st.get("ls", 0.0) * k


static func tick(game, h, delta: float) -> void:
	for e in h.items:
		if e != null and e["cd"] > 0:
			e["cd"] = max(0.0, e["cd"] - delta)
	h.blink_lock = max(0.0, h.blink_lock - delta)
	if h.bkb_t > 0:
		h.bkb_t -= delta
	if h.potion_t > 0:
		h.potion_t -= delta
		h.hp = min(h.max_hp, h.hp + 300.0 / 8.0 * delta)
	if h.tp_t > 0:
		h.tp_t -= delta
		if h.tp_t <= 0:
			h.set_p2(game.spawn_pos(h.team))
			h.path = PackedVector2Array()
			h.target = null
			game.fx.add_ring(h.position, 2.0, Color(0.4, 0.75, 1.0), 0.6, 1.5)


## Called when a hero takes damage from an enemy hero.
static func on_hero_damage(game, h) -> void:
	h.blink_lock = 3.0
	if h.potion_t > 0:
		h.potion_t = 0.0
		if h.is_player:
			game.fx.add_text(h.position, "poção cortada", Color(1, 0.5, 0.5))
	if h.tp_t > 0:
		h.tp_t = 0.0
		if h.is_player:
			game.fx.add_text(h.position, "TP cancelado", Color(1, 0.5, 0.5))


static func use(game, h, slot: int) -> bool:
	var e = h.items[slot]
	if e == null or h.dead or h.stun_t > 0 or e["cd"] > 0:
		return false
	var it: Dictionary = ITEMS[e["id"]]
	if not it.get("active", false):
		return false
	match e["id"]:
		"pocao":
			if h.hp >= h.max_hp - 1.0 or h.potion_t > 0:
				return false
			h.potion_t = 8.0
			game.fx.add_aura(h, 8.0, Color(0.9, 0.3, 0.35))
		"tp":
			if h.tp_t > 0 or near_shop(game, h):
				return false
			h.tp_t = 3.0
			game.fx.add_aura(h, 3.0, Color(0.4, 0.75, 1.0))
			if h.is_player:
				game.fx.add_text(h.position, "TP...", Color(0.6, 0.85, 1.0))
		"sentinela":
			game.place_ward(h.team, h.p2() + h.facing * 2.0)
		"blink":
			if h.blink_lock > 0:
				if h.is_player:
					game.fx.add_text(h.position, "Blink travado", Color(1, 0.6, 0.6))
				return false
			var d: Vector2 = h.move_input if h.move_input.length() > 0.15 else h.facing
			if h.aim_override.length() > 0.01:
				d = h.aim_override
				h.aim_override = Vector2.ZERO
			h.hook_cancel()
			h._blink(d.normalized(), 8.0, Color(0.55, 0.8, 1.0))
			h.set_p2(game.push_out(h.p2(), h.radius))
			h.tp_t = 0.0
		"bkb":
			h.bkb_t = 5.0
			h.stun_t = 0.0
			h.slow_t = 0.0
			game.fx.add_aura(h, 5.0, Color(1.0, 0.85, 0.3))
			game.fx.add_text(h.position, "IMUNE", Color(1, 0.85, 0.3))
	e["cd"] = it.get("cd", 1.0)
	if it.get("consumable", false):
		e["n"] -= 1
		if e["n"] <= 0:
			h.items[slot] = null
	return true


## Bots: buy along their route when at base (or 2% chance elsewhere, like a courier),
## use potion / BKB / TP when it makes sense.
static func bot_think(game, h, foe) -> void:
	var at_home := near_shop(game, h)
	if at_home or randf() < 0.02:
		var route: Array = ROUTE_CARRY if h.kit == "assassina" else (ROUTE_RANGED if h.kit in RANGED_KITS else ROUTE_MELEE)
		for id in route:
			if id == "pocao":
				if slot_of(h, "pocao") < 0 and h.gold >= 60:
					buy(game, h, "pocao")
				continue
			if slot_of(h, id) < 0:
				buy(game, h, id)
				break  # save up for the next one in order
	var s := slot_of(h, "pocao")
	if s >= 0 and h.hp_frac() < 0.5 and h.potion_t <= 0 and (foe == null or h.dist_to(foe) > 7.0):
		use(game, h, s)
	s = slot_of(h, "bkb")
	if s >= 0 and foe != null and h.dist_to(foe) < 6.0 and game.heroes_near(h.p2(), 1 - h.team, 9.0) >= 2:
		use(game, h, s)
