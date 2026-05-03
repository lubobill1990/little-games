extends Node
## E2E replay runner. Boots the Tetris scene, attaches a TetrisAI, and feeds
## the AI's actions to the engine via Input.action_press / action_release on a
## fixed-tick schedule. Writes a JSON sidecar of (seed, commit_sha, action_log,
## final_score, …) next to the movie-maker output, regardless of recording.
##
## Use as the main scene of a Godot run. Movie maker is enabled via the
## --write-movie command-line flag; this script doesn't start/stop it.
##
## Command-line args (after `--`):
##   --seed=<int>           Required. Threads through TetrisGameState RNG.
##   --max-pieces=<int>     Optional cap; default 200. Stops the AI early.
##   --sidecar=<path>       Where to write the JSON sidecar; default user://e2e.json.
##   --commit=<sha>         Embedded in the sidecar; default "unknown".
##
## **Headless caveat.** Godot's movie maker mode requires a rendering device
## and is incompatible with `--headless`. On Linux CI we wrap the Godot call
## with `xvfb-run -a`. On Mac/Windows we run direct. See docs/e2e-replay.md.

const TetrisAI := preload("res://scripts/e2e/tetris_ai.gd")
const TetrisGameScene := preload("res://scenes/tetris/tetris.tscn")

# How many real-time frames between AI actions. 1 = act every frame; under
# fixed-fps movie mode that's 60 actions/sec, well above human play rate but
# still sane for the AI's per-piece plan (~3–5 actions). The limiting factor
# is core gravity, not AI speed.
const ACTION_INTERVAL_FRAMES: int = 1

var _ai: TetrisAI
var _scene: Control
var _frame_counter: int = 0
var _action_log: Array[Dictionary] = []
var _sidecar_path: String = "user://e2e.json"
var _commit: String = "unknown"
var _seed: int = 0
var _max_pieces: int = 200
var _pieces_locked: int = 0
var _last_piece_kind: int = -1
var _finished: bool = false


func _ready() -> void:
	_parse_args()
	_ai = TetrisAI.new()
	_scene = TetrisGameScene.instantiate() as Control
	add_child(_scene)
	# Tetris.start() is the GameHost entry point; bypass the menu entirely.
	_scene.start(_seed)
	# Make sure no synthetic action is held over from a previous run.
	_release_all_actions()
	_action_log.clear()
	_pieces_locked = 0
	_finished = false
	_write_sidecar()   # Initial write so we have *something* even if we crash.


func _process(_delta: float) -> void:
	if _finished:
		return
	if _scene == null or _scene.state == null:
		return
	# Detect piece-locked transitions by watching the current_piece reference.
	# The scene's `state` field is the TetrisGameState; piece becomes a fresh
	# Piece on each spawn, so kind+origin together change after a hard_drop.
	var piece = _scene.state.current_piece()
	var current_kind: int = piece.kind if piece != null else -1
	if _last_piece_kind != -1 and current_kind != _last_piece_kind:
		_pieces_locked += 1
	_last_piece_kind = current_kind

	# Stop conditions.
	if _scene.state.is_game_over() or _pieces_locked >= _max_pieces:
		_finalize()
		return

	_frame_counter += 1
	if _frame_counter < ACTION_INTERVAL_FRAMES:
		return
	_frame_counter = 0

	# Release every action from the previous frame; we drive single-frame
	# pulses so DAS/ARR doesn't auto-repeat. (`Input.action_press` followed
	# by `Input.action_release` on the next frame mirrors a human tap.)
	_release_all_actions()

	var act: StringName = _ai.next_action(_scene.state)
	if act == &"":
		return
	# Emit the action: press the matching engine action so InputManager picks
	# it up via its existing per-frame poll. We DO NOT extend InputManager
	# with a separate test bus — Input.action_press is the same path tests
	# already use, and it preserves DAS/ARR semantics for honest gameplay.
	var engine_action: StringName = _engine_action_for(act)
	if engine_action != &"":
		Input.action_press(engine_action)
	_action_log.append({
		"frame": Engine.get_process_frames(),
		"action": String(act),
	})
	# Periodic flush — every 30 actions — so a crash mid-run still leaves a
	# usable sidecar for triage.
	if _action_log.size() % 30 == 0:
		_write_sidecar()


func _notification(what: int) -> void:
	# Final flush on window close — the user might Ctrl+C or close mid-play
	# and we still want the action log on disk.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_finalize()


func _finalize() -> void:
	if _finished:
		return
	_finished = true
	_release_all_actions()
	_write_sidecar()
	# Quit the Godot process so movie maker finalizes its output and the shell
	# wrapper can collect artifacts.
	get_tree().quit()


func _release_all_actions() -> void:
	for a in [&"move_left", &"move_right", &"rotate_cw", &"rotate_ccw", &"hard_drop", &"soft_drop", &"hold", &"pause"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


# Map TetrisAI.ACT_* constants to InputManager action names. Kept as a tiny
# function (not a const Dictionary) because StringName const dicts have
# hashing quirks across Godot versions.
func _engine_action_for(ai_act: StringName) -> StringName:
	if ai_act == TetrisAI.ACT_ROTATE_CW:
		return &"rotate_cw"
	if ai_act == TetrisAI.ACT_MOVE_LEFT:
		return &"move_left"
	if ai_act == TetrisAI.ACT_MOVE_RIGHT:
		return &"move_right"
	if ai_act == TetrisAI.ACT_HARD_DROP:
		return &"hard_drop"
	return &""


func _parse_args() -> void:
	for raw in OS.get_cmdline_user_args():
		if raw.begins_with("--seed="):
			_seed = int(raw.substr("--seed=".length()))
		elif raw.begins_with("--max-pieces="):
			_max_pieces = int(raw.substr("--max-pieces=".length()))
		elif raw.begins_with("--sidecar="):
			_sidecar_path = raw.substr("--sidecar=".length())
		elif raw.begins_with("--commit="):
			_commit = raw.substr("--commit=".length())


func _write_sidecar() -> void:
	var doc: Dictionary = {
		"version": 1,
		"game": "tetris",
		"seed": _seed,
		"commit": _commit,
		"max_pieces": _max_pieces,
		"pieces_locked": _pieces_locked,
		"finished": _finished,
		"final_score": _scene.state.score() if (_scene != null and _scene.state != null) else 0,
		"final_lines": _scene.state.lines_cleared() if (_scene != null and _scene.state != null) else 0,
		"action_log": _action_log,
	}
	var f: FileAccess = FileAccess.open(_sidecar_path, FileAccess.WRITE)
	if f == null:
		push_error("e2e runner: could not open sidecar path %s for write" % _sidecar_path)
		return
	# Sorted keys + \n line endings + fixed precision — matches the
	# canonicalization contract documented in docs/e2e-replay.md so two
	# runs of the same seed produce byte-identical sidecars.
	f.store_string(JSON.stringify(doc, "\t", true) + "\n")
	f.close()
