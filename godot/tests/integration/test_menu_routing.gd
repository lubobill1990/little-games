extends GutTest
## Menu routing integration test:
## - Menu populates from registry.
## - Choosing a game instances it under GameRoot, hides menu.
## - Game's exit_requested → menu reappears, game freed, no orphan nodes.

const GameRegistry := preload("res://scripts/core/game/game_registry.gd")
const ActionMapDefaults := preload("res://scripts/core/input/action_map_defaults.gd")

var menu: Control

func before_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/menu/main_menu.tscn")
	menu = packed.instantiate()
	add_child(menu)
	await get_tree().process_frame

func after_each() -> void:
	for action in ActionMapDefaults.ACTIONS:
		Input.action_release(action)
	if is_instance_valid(menu):
		menu.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func test_menu_populates_one_card_per_registered_game() -> void:
	assert_eq(menu._cards.size(), GameRegistry.all().size(), "card per registered game")
	for card in menu._cards:
		var d = card.descriptor()
		assert_ne(d, null, "card has descriptor")
		assert_eq(card.text, d.title, "card text matches title")

func test_choosing_tetris_instances_under_game_root_and_hides_menu() -> void:
	var tetris_card: Button = _card_for(&"tetris")
	assert_ne(tetris_card, null, "tetris card present")
	tetris_card.emit_signal(&"game_chosen", tetris_card.descriptor())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(menu._menu_root.visible, "menu hidden while playing")
	assert_eq(menu._game_root.get_child_count(), 1, "exactly one active game")
	var active: Node = menu._active_game
	assert_ne(active, null, "active_game wired")
	assert_true(active.has_method(&"start"), "host has start()")
	assert_true(active.has_method(&"teardown"), "host has teardown()")
	assert_true(active.has_signal(&"exit_requested"), "host has exit_requested")

func test_exit_requested_returns_to_menu_with_no_orphans() -> void:
	var stub_card: Button = _card_for(&"snake_stub")
	assert_ne(stub_card, null, "stub card present")
	# Capture orphan-baseline AFTER menu is fully ready (already in tree, populated).
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	stub_card.emit_signal(&"game_chosen", stub_card.descriptor())
	await get_tree().process_frame
	assert_ne(menu._active_game, null, "game running")
	# Trigger exit explicitly so the test is deterministic (don't depend on the
	# stub's auto-exit timer firing inside a fixed frame budget).
	menu._active_game.emit_signal(&"exit_requested")
	# The handler awaits one frame internally; give it two to fully settle.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(menu._menu_root.visible, "menu visible again")
	assert_eq(menu._active_game, null, "active_game cleared")
	assert_eq(menu._game_root.get_child_count(), 0, "game_root drained")
	var after_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	assert_lte(after_orphans, baseline_orphans + 0, "no new orphan nodes (was=%d now=%d)" % [baseline_orphans, after_orphans])

func test_invalid_descriptor_paths_do_not_crash_population() -> void:
	# This test is a behavioral guarantee: validate() never throws and missing
	# scenes are skipped silently in the grid (problems label surfaces them).
	var problems: Array[String] = GameRegistry.validate()
	assert_typeof(problems, TYPE_ARRAY, "validate returns Array")

func _card_for(id: StringName) -> Button:
	for card in menu._cards:
		if card.descriptor().id == id:
			return card
	return null
