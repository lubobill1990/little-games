extends CanvasLayer
## Snake difficulty picker. Layer 5 (below pause/game-over). Three Buttons in
## a row; first selection grabs focus so gamepad d-pad / left-stick navigates
## natively. Confirm (A / Enter) emits `difficulty_chosen(id)`.
##
## Default selection is `Settings.snake.last_difficulty` (or `"normal"` if
## absent). Per-difficulty best score is shown beneath each button.

const Difficulty := preload("res://scripts/snake/difficulty.gd")

signal difficulty_chosen(id: String)

var _buttons: Array[Button] = []
var _initial_focus_id: String = Difficulty.DEFAULT_ID


func _ready() -> void:
	layer = 5
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.add_theme_constant_override("separation", 24)
	add_child(vbox)
	var title := Label.new()
	title.text = "SNAKE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	vbox.add_child(title)
	var prompt := Label.new()
	prompt.text = "Pick a difficulty"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 22)
	vbox.add_child(prompt)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	vbox.add_child(row)
	for d in Difficulty.DIFFICULTIES:
		var card: VBoxContainer = _build_card(d)
		row.add_child(card)


func _build_card(d: Dictionary) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	var btn := Button.new()
	btn.text = String(d["title"])
	btn.custom_minimum_size = Vector2(160.0, 80.0)
	btn.add_theme_font_size_override("font_size", 28)
	var id: String = String(d["id"])
	btn.pressed.connect(func() -> void: _emit_choice(id))
	col.add_child(btn)
	_buttons.append(btn)
	var detail := Label.new()
	detail.text = "%dms · %s" % [int(d["start_step_ms"]), "walls" if bool(d["walls"]) else "wrap"]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 14)
	col.add_child(detail)
	var best := Label.new()
	best.text = _best_label(id)
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best.add_theme_font_size_override("font_size", 14)
	col.add_child(best)
	return col


func _best_label(id: String) -> String:
	if not _has_settings():
		return "Best: 0"
	var v: int = int(Settings.get_value(Difficulty.best_key(id), 0))
	return "Best: %d" % v


func _has_settings() -> bool:
	return get_tree().root.has_node("Settings")


## Set initial focus and reveal. Caller passes the id to default to (last
## chosen, or `normal`). Wires focus_neighbor so d-pad left/right walk the row.
func show_picker(initial_id: String = Difficulty.DEFAULT_ID) -> void:
	_initial_focus_id = initial_id
	visible = true
	# Refresh best labels on each show — caller may have just persisted one.
	for i in _buttons.size():
		var card: VBoxContainer = _buttons[i].get_parent() as VBoxContainer
		if card != null and card.get_child_count() >= 3:
			var best_label: Label = card.get_child(2) as Label
			if best_label != null:
				best_label.text = _best_label(String(Difficulty.DIFFICULTIES[i]["id"]))
	# Wire focus neighbours horizontally.
	for i in _buttons.size():
		var b: Button = _buttons[i]
		var left: int = (i - 1 + _buttons.size()) % _buttons.size()
		var right: int = (i + 1) % _buttons.size()
		b.focus_neighbor_left = _buttons[left].get_path()
		b.focus_neighbor_right = _buttons[right].get_path()
	var idx: int = 0
	for i in _buttons.size():
		if String(Difficulty.DIFFICULTIES[i]["id"]) == _initial_focus_id:
			idx = i
			break
	_buttons[idx].grab_focus()


func _emit_choice(id: String) -> void:
	if _has_settings():
		Settings.set_value(Difficulty.LAST_KEY, id)
	visible = false
	difficulty_chosen.emit(id)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_accept"):
		var f: Control = get_viewport().gui_get_focus_owner()
		if f is Button:
			(f as Button).pressed.emit()
