class_name GameRegistry extends RefCounted
## Static registry of available games. Adding a game = append one entry to
## `_GAMES` and create the scene; nothing else changes in the menu code.
##
## Scene paths are strings (no preload) — the menu loads on selection so unused
## games don't pay startup cost. Verified resolvable at boot via `validate()`.

const GameDescriptor := preload("res://scripts/core/game/game_descriptor.gd")

# Each entry: [id, title, scene_path, icon_path].
const _GAMES: Array = [
	[&"tetris", "Tetris", "res://scenes/tetris/tetris.tscn", ""],
	[&"snake", "Snake", "res://scenes/snake/snake.tscn", ""],
	[&"g2048", "2048", "res://scenes/g2048/g2048.tscn", ""],
]

static func all() -> Array:
	var out: Array = []
	for entry in _GAMES:
		out.append(GameDescriptor.new(entry[0], entry[1], entry[2], entry[3]))
	return out

static func by_id(id: StringName) -> GameDescriptor:
	for entry in _GAMES:
		if entry[0] == id:
			return GameDescriptor.new(entry[0], entry[1], entry[2], entry[3])
	return null

static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in _GAMES:
		out.append(entry[0])
	return out

# Returns a list of human-readable problems; empty array means OK. Used by the
# menu at boot to surface registry mistakes early instead of crashing on click.
static func validate() -> Array[String]:
	var problems: Array[String] = []
	var seen: Dictionary = {}
	for entry in _GAMES:
		var id: StringName = entry[0]
		if seen.has(id):
			problems.append("duplicate id: %s" % id)
		seen[id] = true
		var scene_path: String = entry[2]
		if not ResourceLoader.exists(scene_path):
			problems.append("%s: scene not found at %s" % [id, scene_path])
		var icon_path: String = entry[3]
		if icon_path != "" and not ResourceLoader.exists(icon_path):
			problems.append("%s: icon not found at %s" % [id, icon_path])
	return problems
