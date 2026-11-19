extends SceneTree
## Extracts the clips the game uses from Quaternius' Universal Animation Library (CC0)
## into a small AnimationLibrary resource. Run: godot --headless -s res://tools/build_anim_lib.gd
const WANT := ["Idle", "Jog_Fwd", "Sprint", "Sword_Idle", "Sword_Attack", "Spell_Simple_Shoot", "Spell_Simple_Enter",
	"Punch_Cross", "Punch_Jab", "Roll", "Death01", "Dance", "Hit_Chest"]
func _init():
	var n = load("res://assets/_src/UAL1_Standard.glb").instantiate()
	var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0]
	print(ap.get_animation_list())
	var lib := AnimationLibrary.new()
	for nm in WANT:
		var a: Animation = null
		for cand in [nm, nm + "_Loop"]:
			if ap.has_animation(cand):
				a = ap.get_animation(cand).duplicate(true)
		if a == null:
			print("MISSING ", nm); continue
		# keep only rotations + pelvis/root position (works across body proportions); drop scale
		for t in range(a.get_track_count() - 1, -1, -1):
			var path := str(a.track_get_path(t))
			var ty := a.track_get_type(t)
			if ty == Animation.TYPE_SCALE_3D or (ty == Animation.TYPE_POSITION_3D and not (path.ends_with(":pelvis") or path.ends_with(":root"))):
				a.remove_track(t)
			elif ty == Animation.TYPE_ROTATION_3D and (path.contains("_04_leaf") or path.ends_with("_leaf_l") or path.ends_with("_leaf_r")):
				a.remove_track(t)
		a.optimize(0.01, 0.01, 3.0)
		lib.add_animation(nm, a)
	print(ResourceSaver.save(lib, "res://assets/anims/ual_lib.res", ResourceSaver.FLAG_COMPRESS))
	n.free()
	quit()
