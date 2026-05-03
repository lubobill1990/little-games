extends GutTest
## Forward-looking shape check: every registered game's scene satisfies the
## GameHost duck-typed contract (start/pause/resume/teardown methods +
## exit_requested signal). Catches contract drift (e.g. a new game forgets
## `pause`) within the warm GUT environment.
##
## NOT a substitute for tests/cold_load_smoke.gd — that runs in a subprocess
## to catch class_name / preload race bugs that only manifest cold.

const GameRegistry := preload("res://scripts/core/game/game_registry.gd")

func test_every_registered_game_satisfies_game_host_contract() -> void:
	for descriptor in GameRegistry.all():
		var packed: PackedScene = descriptor.load_scene()
		assert_ne(packed, null, "%s: load_scene returned null" % descriptor.id)
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		assert_ne(inst, null, "%s: instantiate returned null" % descriptor.id)
		if inst == null:
			continue
		for m in [&"start", &"pause", &"resume", &"teardown"]:
			assert_true(inst.has_method(m), "%s missing method %s" % [descriptor.id, m])
		assert_true(inst.has_signal(&"exit_requested"), "%s missing signal exit_requested" % descriptor.id)
		inst.free()
