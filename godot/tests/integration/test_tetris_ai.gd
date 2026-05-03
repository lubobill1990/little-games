extends GutTest
## Integration: TetrisAI drives a real TetrisGameState for a fixed seed and a
## bounded number of pieces. No rendering, no scene, no Godot Input. Asserts
## the AI doesn't crash and makes meaningful progress.
##
## Determinism: same seed + same AI weights → byte-identical action log.
## This is the contract the e2e replay layer relies on for reproducibility.

const TetrisGameState := preload("res://scripts/tetris/core/game_state.gd")
const TetrisAI := preload("res://scripts/e2e/tetris_ai.gd")

const SEED: int = 4242
const MAX_PIECES: int = 80


# Drive `state` by repeatedly asking `ai` for the next action and applying it
# directly to the core (bypassing Input / scene / DAS-ARR layers — that's the
# integration test's job, here we want pure rule-engine determinism).
# Returns {actions, pieces_locked, score, lines, game_over}.
func _drive(state: TetrisGameState, ai: TetrisAI, max_pieces: int) -> Dictionary:
	var actions: Array[String] = []
	var pieces_locked: int = 0
	var ms: int = 0
	# Prime tick clock so gravity doesn't fire on tick(0).
	state.tick(ms)
	while pieces_locked < max_pieces and not state.is_game_over():
		var act: StringName = ai.next_action(state)
		if act == &"":
			break
		actions.append(String(act))
		match act:
			TetrisAI.ACT_ROTATE_CW:
				state.rotate(1)
			TetrisAI.ACT_MOVE_LEFT:
				state.move(-1)
			TetrisAI.ACT_MOVE_RIGHT:
				state.move(1)
			TetrisAI.ACT_HARD_DROP:
				state.hard_drop()
				pieces_locked += 1
		# Advance time a hair so successive ticks don't accumulate gravity
		# (10 ms per action is well under the gravity threshold at level 1
		# and keeps the AI in control of when pieces drop).
		ms += 10
		state.tick(ms)
	return {
		"actions": actions,
		"pieces_locked": pieces_locked,
		"score": state.score(),
		"lines": state.lines_cleared(),
		"game_over": state.is_game_over(),
	}


func test_ai_plays_without_erroring() -> void:
	# Acceptance #3: AI plays for ≥ K pieces without erroring, clears ≥ 1 line.
	# K is the integration smoke seed; we use a small budget here for CI speed.
	var state := TetrisGameState.create(SEED)
	var ai := TetrisAI.new()
	var result: Dictionary = _drive(state, ai, MAX_PIECES)
	assert_gt(int(result["pieces_locked"]), 0, "AI placed at least one piece")
	# A heuristic this strong should clear at least one line in 80 pieces on
	# any sane seed. If this regresses, suspect score weights or planner bugs.
	assert_gt(int(result["lines"]), 0, "AI cleared at least one line in %d pieces" % MAX_PIECES)


func test_same_seed_produces_byte_identical_action_log() -> void:
	# Acceptance #2 (rule layer): determinism contract. Two runs with the same
	# seed and same AI weights must produce identical action sequences.
	var state_a := TetrisGameState.create(SEED)
	var state_b := TetrisGameState.create(SEED)
	var ai_a := TetrisAI.new()
	var ai_b := TetrisAI.new()
	var ra: Dictionary = _drive(state_a, ai_a, MAX_PIECES)
	var rb: Dictionary = _drive(state_b, ai_b, MAX_PIECES)
	assert_eq(ra["actions"], rb["actions"], "action log byte-identical for same seed")
	assert_eq(int(ra["score"]), int(rb["score"]), "final score identical")
	assert_eq(int(ra["lines"]), int(rb["lines"]), "lines cleared identical")


func test_action_log_is_compact_relative_to_pieces() -> void:
	# Sanity: the planner should issue at most ~10 actions per piece (4 rotations
	# max + 9 moves max + 1 drop = 14 worst-case; typically 3–5). If we ever ship
	# 100+ actions per piece, the planner is broken.
	var state := TetrisGameState.create(SEED)
	var ai := TetrisAI.new()
	var result: Dictionary = _drive(state, ai, 10)
	var per_piece: float = float((result["actions"] as Array).size()) / float(int(result["pieces_locked"]))
	assert_lt(per_piece, 14.0, "actions/piece must stay ≤ 14")
