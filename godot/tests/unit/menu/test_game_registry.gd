extends GutTest
## Registry sanity: ids unique, scene paths resolvable, descriptors well-formed.

const GameRegistry := preload("res://scripts/core/game/game_registry.gd")
const GameDescriptor := preload("res://scripts/core/game/game_descriptor.gd")

func test_validate_returns_no_problems() -> void:
	var problems: Array[String] = GameRegistry.validate()
	assert_eq(problems, [] as Array[String], "registry validate: %s" % str(problems))

func test_all_returns_at_least_two_descriptors() -> void:
	var games: Array = GameRegistry.all()
	assert_gte(games.size(), 2, "registry has at least Tetris + one stub")
	for g in games:
		assert_true(g is GameDescriptor, "entry is GameDescriptor")
		assert_ne(String(g.id), "", "id non-empty")
		assert_ne(g.title, "", "title non-empty")
		assert_true(g.scene_path.begins_with("res://"), "scene_path is res://...")

func test_by_id_resolves_known_and_unknown() -> void:
	assert_ne(GameRegistry.by_id(&"tetris"), null, "tetris resolves")
	assert_eq(GameRegistry.by_id(&"does_not_exist"), null, "unknown returns null")

func test_ids_unique() -> void:
	var ids: Array[StringName] = GameRegistry.ids()
	var seen: Dictionary = {}
	for id in ids:
		assert_false(seen.has(id), "id duplicated: %s" % id)
		seen[id] = true

func test_descriptor_load_scene_returns_packed_scene() -> void:
	var d: GameDescriptor = GameRegistry.by_id(&"tetris")
	var scene: PackedScene = d.load_scene()
	assert_true(scene is PackedScene, "load_scene returns PackedScene")
	# Smoke-instance to confirm the scene parses; immediately free.
	var inst: Node = scene.instantiate()
	assert_ne(inst, null, "instantiate ok")
	inst.free()
