extends GutTest
## Integration: scripted seed + intent log → expected snapshot stream.
## Bypasses the scene + input layer entirely; drives SnakeGameState directly.
## Catches non-determinism in the core that the scene test can't (the scene
## has wall-clock timing in the loop).

const SnakeConfig := preload("res://scripts/snake/core/snake_config.gd")
const SnakeGameState := preload("res://scripts/snake/core/snake_state.gd")

const SEED: int = 4242

func _make_state() -> SnakeGameState:
	var cfg := SnakeConfig.new()
	# Small grid to make manual reasoning + dense food spawns feasible.
	cfg.grid_w = 8
	cfg.grid_h = 8
	cfg.start_step_ms = 50
	return SnakeGameState.create(SEED, cfg)


func test_same_seed_same_intents_same_snapshot_stream() -> void:
	# Two parallel runs with identical inputs should produce byte-identical
	# snapshot streams.
	var a := _make_state()
	var b := _make_state()
	# Drive both for 30 ticks. Inject a turn at step 10.
	var snaps_a: Array[Dictionary] = []
	var snaps_b: Array[Dictionary] = []
	for i in 30:
		if i == 10:
			a.turn(SnakeGameState.Dir.DOWN)
			b.turn(SnakeGameState.Dir.DOWN)
		var t: int = i * 60
		a.tick(t)
		b.tick(t)
		snaps_a.append(a.snapshot())
		snaps_b.append(b.snapshot())
	assert_eq(snaps_a, snaps_b, "snapshot streams must match for identical seed+intents")


func test_full_session_reaches_game_over() -> void:
	# With a small grid, walls-on, and aggressive turning, the snake must
	# eventually game-over. Verifies the core terminates rather than running
	# forever in the integration scenario.
	var s := _make_state()
	s.turn(SnakeGameState.Dir.RIGHT)
	var step: int = 0
	var t: int = 0
	# Cap iterations so a regression doesn't hang the suite.
	while not s.is_game_over() and step < 2000:
		t += 60
		s.tick(t)
		# Alternate turn intents to keep the snake moving and eventually crash.
		if step % 3 == 0:
			s.turn(SnakeGameState.Dir.DOWN)
		elif step % 3 == 1:
			s.turn(SnakeGameState.Dir.RIGHT)
		else:
			s.turn(SnakeGameState.Dir.UP)
		step += 1
	assert_true(s.is_game_over(), "session terminated within 2000 steps")


func test_snapshot_carries_version() -> void:
	var s := _make_state()
	var snap: Dictionary = s.snapshot()
	assert_eq(int(snap.get("version", 0)), SnakeGameState.SCHEMA_VERSION,
		"snapshot version field present and matches SCHEMA_VERSION")
