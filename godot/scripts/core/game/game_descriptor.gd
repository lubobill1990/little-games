class_name GameDescriptor extends RefCounted
## One entry in the GameRegistry. Lazy-loaded — `scene_path` is a string so
## adding a game costs zero memory until the player picks it.

var id: StringName
var title: String
var scene_path: String
var icon_path: String  # "" when no icon.

func _init(p_id: StringName, p_title: String, p_scene_path: String, p_icon_path: String = "") -> void:
	id = p_id
	title = p_title
	scene_path = p_scene_path
	icon_path = p_icon_path

func load_scene() -> PackedScene:
	return load(scene_path) as PackedScene

func load_icon() -> Texture2D:
	if icon_path == "":
		return null
	return load(icon_path) as Texture2D
