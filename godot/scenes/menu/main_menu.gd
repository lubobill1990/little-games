extends Control
## Main menu — lists registered games, instances and runs the picked one,
## reclaims control on `exit_requested`. Owns no per-game state; the host
## treats the active game as a duck-typed GameHost (start/pause/resume/
## teardown + exit_requested signal).

const GameRegistry := preload("res://scripts/core/game/game_registry.gd")
const GameDescriptor := preload("res://scripts/core/game/game_descriptor.gd")
const GameCardScript := preload("res://scenes/menu/game_card.gd")

@onready var _menu_root: Control = $MenuRoot
@onready var _game_root: Node = $GameRoot
@onready var _grid: GridContainer = $MenuRoot/CenterContainer/VBox/Grid
@onready var _title: Label = $MenuRoot/CenterContainer/VBox/Title
@onready var _problems: Label = $MenuRoot/CenterContainer/VBox/Problems

var _cards: Array[Button] = []
var _active_game: Node = null
var _last_focused_card: Control = null
var _focus_pending: bool = true  # true until something gets focus from input

func _ready() -> void:
	_title.text = GameInfo.PROJECT_NAME
	_problems.visible = false
	_populate_grid()
	# Catch hot-plugged controllers so the menu re-grabs focus.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# Defer focus acquisition until the first input arrives — avoids snatching
	# keyboard focus on web before the user has interacted (browser policy).

func _input(event: InputEvent) -> void:
	if not _menu_root.visible or not _focus_pending:
		return
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventScreenTouch or event is InputEventMouseButton:
		_focus_pending = false
		_focus_first_card()

func _populate_grid() -> void:
	var problems: Array[String] = GameRegistry.validate()
	if not problems.is_empty():
		_problems.visible = true
		_problems.text = "Registry problems:\n- " + "\n- ".join(problems)
		# Keep going — the unbroken entries should still be playable.
	_cards.clear()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for descriptor in GameRegistry.all():
		# Skip entries whose scene didn't resolve so a typo doesn't break the menu.
		if not ResourceLoader.exists(descriptor.scene_path):
			continue
		var card := Button.new()
		card.set_script(GameCardScript)
		_grid.add_child(card)
		card.bind(descriptor)
		card.game_chosen.connect(_on_game_chosen)
		_cards.append(card)

func _focus_first_card() -> void:
	var target: Control = _last_focused_card if _last_focused_card != null else (_cards[0] if not _cards.is_empty() else null)
	if target != null and is_instance_valid(target):
		target.grab_focus()
		_last_focused_card = target

func _on_joy_connection_changed(_device_id: int, connected: bool) -> void:
	if connected and _menu_root.visible:
		_focus_first_card()

func _on_game_chosen(descriptor: GameDescriptor) -> void:
	# Remember which card was active so we can restore focus on return.
	for card in _cards:
		if card.has_focus():
			_last_focused_card = card
			break
	var packed: PackedScene = descriptor.load_scene()
	if packed == null:
		push_error("MainMenu: load_scene returned null for %s" % descriptor.id)
		return
	var instance: Node = packed.instantiate()
	if not _is_game_host(instance):
		push_error("MainMenu: %s does not satisfy the GameHost contract" % descriptor.id)
		instance.free()
		return
	_active_game = instance
	_game_root.add_child(instance)
	instance.exit_requested.connect(_on_active_game_exit, CONNECT_ONE_SHOT)
	instance.call(&"start", _fresh_seed())
	_menu_root.visible = false

func _on_active_game_exit() -> void:
	_reclaim_from_active_game()

func _reclaim_from_active_game() -> void:
	if _active_game == null:
		return
	if _active_game.has_method(&"teardown"):
		_active_game.call(&"teardown")
	_game_root.remove_child(_active_game)
	_active_game.queue_free()
	_active_game = null
	_menu_root.visible = true
	# Wait one frame so freed nodes settle, then refocus.
	await get_tree().process_frame
	_focus_first_card()

func _is_game_host(node: Node) -> bool:
	return node.has_method(&"start") and node.has_method(&"teardown") and node.has_signal(&"exit_requested")

func _fresh_seed() -> int:
	return Time.get_ticks_msec() ^ (randi() & 0xFFFFFFFF)
