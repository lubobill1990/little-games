extends Control
## Stub second game. Exists to validate the GameHost contract:
##   start(seed), pause(), resume(), teardown(), exit_requested signal.
## Acceptance #4 requires this to be ≤ 50 LoC of placeholder so the framework
## itself is what's exercised. Real Snake is task #15 / #18 / #19.

signal exit_requested()
signal score_reported(value: int)

const _AUTO_EXIT_MS: int = 1500

var _label: Label
var _hint: Label
var _seed: int = 0
var _paused: bool = false
var _started_at_ms: int = -1
var _logical_elapsed_ms: int = 0
var _last_real_ms: int = 0
var _exit_emitted: bool = false

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.1, 0.05, 1.0)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	add_child(vbox)
	_label = Label.new()
	_label.text = "Snake — WIP"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 48)
	vbox.add_child(_label)
	_hint = Label.new()
	_hint.text = "(stub: returns to menu automatically)"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_hint)
	# Surface a single score event so anything wiring `score_reported` exercises
	# the path without us pretending to be a real game.
	score_reported.emit(0)

func start(seed_value: int = 0) -> void:
	_seed = seed_value
	_started_at_ms = Time.get_ticks_msec()
	_last_real_ms = _started_at_ms
	_logical_elapsed_ms = 0
	_paused = false
	_exit_emitted = false

func pause() -> void:
	_paused = true

func resume() -> void:
	_paused = false

func teardown() -> void:
	# Drop refs; the host queue_frees us right after.
	_label = null
	_hint = null

func _process(_delta: float) -> void:
	if _exit_emitted or _started_at_ms < 0:
		return
	var now: int = Time.get_ticks_msec()
	if not _paused:
		_logical_elapsed_ms += max(0, now - _last_real_ms)
	_last_real_ms = now
	if _logical_elapsed_ms >= _AUTO_EXIT_MS:
		_exit_emitted = true
		exit_requested.emit()
