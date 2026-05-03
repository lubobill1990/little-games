extends SceneTree
## Cold-load smoke test. Invoked via `--script` in a fresh Godot subprocess
## (NOT inside GUT) so the global script class table is empty at start —
## reproducing what users hit on a real cold launch from the main menu.
##
## For each game in GameRegistry, instantiate the root scene and verify it
## satisfies the GameHost duck-typed contract. Exit code = problem count;
## CI also greps stderr for `SCRIPT ERROR` because Godot may print
## compile errors without setting a non-zero exit.

const GameRegistry := preload("res://scripts/core/game/game_registry.gd")

func _initialize() -> void:
	var problems: Array[String] = []
	for descriptor in GameRegistry.all():
		var packed: PackedScene = descriptor.load_scene()
		if packed == null:
			problems.append("%s: load_scene returned null" % descriptor.id)
			continue
		var instance: Node = packed.instantiate()
		if instance == null:
			problems.append("%s: instantiate returned null" % descriptor.id)
			continue
		for m in [&"start", &"pause", &"resume", &"teardown"]:
			if not instance.has_method(m):
				problems.append("%s: missing method %s" % [descriptor.id, m])
		if not instance.has_signal(&"exit_requested"):
			problems.append("%s: missing signal exit_requested" % descriptor.id)
		instance.free()
	if problems.is_empty():
		print("[cold_load_smoke] OK")
		quit(0)
	else:
		for p in problems:
			push_error("[cold_load_smoke] %s" % p)
		quit(problems.size())
