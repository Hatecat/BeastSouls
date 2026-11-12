extends SceneTree
## Vuelca en JSON los clips, huesos y medidas de un modelo importado. Lo usa tools/new_character.py.
##   godot --headless --path . --script tools/inspect_model.gd -- res://ruta/modelo.glb


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene := load(args[0]) as PackedScene if not args.is_empty() else null
	if scene == null:
		print("MODEL_JSON_BEGIN{\"error\": \"no se pudo cargar el modelo\"}MODEL_JSON_END")
		quit(1)
		return
	var root_node := scene.instantiate()
	var out := {clips = {}, bones = [], meshes = 0, triangles = 0}
	var players := root_node.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var ap := players[0] as AnimationPlayer
		for c in ap.get_animation_list():
			out.clips[c] = ap.get_animation(c).length
	var skels := root_node.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var sk := skels[0] as Skeleton3D
		for b in sk.get_bone_count():
			out.bones.append([sk.get_bone_name(b), sk.get_bone_parent(b), sk.get_bone_children(b).size()])
	for m: MeshInstance3D in root_node.find_children("*", "MeshInstance3D", true, false):
		out.meshes += 1
		for i in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(i)
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			out.triangles += (idx.size() if idx else arr[Mesh.ARRAY_VERTEX].size()) / 3
	print("MODEL_JSON_BEGIN" + JSON.stringify(out) + "MODEL_JSON_END")
	root_node.free()
	quit()
