extends Node
## Namespaced SFX library autoload.
##
## Reusable across games: each game registers events under its own namespace
## (e.g. `&"tetris"`, `&"snake"`) so event-name collisions are impossible.
##
## Audio assets are loaded from disk at runtime, never referenced from .tscn/
## .tres committed files. Missing files (the common case in CI and on a fresh
## clone of repos with gitignored audio) are silently skipped — the
## `register_many()` helper emits at most one summary `push_warning` so logs
## stay quiet.
##
## Bus: spawned `AudioStreamPlayer` nodes target the `"SFX"` bus. The bus
## layout is established by `default_bus_layout.tres` (set in project.godot
## under `audio/buses/default_bus_layout`).

const _SFX_BUS: StringName = &"SFX"

# (StringName key) -> AudioStream
var _streams: Dictionary = {}
# Per-batch counter; reset by register_many() after the warning fires.
var _missing: int = 0


## Register a single (namespace, event) → audio file mapping. Returns true if
## the file was found and loaded. A false return is silent — callers don't get
## an engine-level error for a missing path because we gate `load()` with
## `FileAccess.file_exists()`.
func register(ns: StringName, event: StringName, path: String) -> bool:
	if not FileAccess.file_exists(path):
		_missing += 1
		return false
	var stream: Resource = load(path)
	if stream == null:
		_missing += 1
		return false
	_streams[_key(ns, event)] = stream
	return true


## Register a batch of events under a single namespace from a Dictionary of
## `event_name (StringName) -> path (String)`. After registration, if any
## files were missing this batch, a single `push_warning` is emitted so the
## warning ratio is one-per-game-per-boot instead of one-per-event.
func register_many(ns: StringName, mapping: Dictionary) -> void:
	for event in mapping:
		register(ns, StringName(event), String(mapping[event]))
	if _missing > 0:
		push_warning("SfxLibrary[%s]: %d events have no audio file" % [String(ns), _missing])
		_missing = 0


## Play a registered (namespace, event). Silent no-op if unregistered (callers
## don't need to know whether assets are present on this build). Spawns a
## one-shot `AudioStreamPlayer` that frees itself on `finished`.
func play(ns: StringName, event: StringName, volume_db: float = 0.0) -> void:
	var stream: Resource = _streams.get(_key(ns, event), null)
	if stream == null:
		return
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = _SFX_BUS
	p.volume_db = volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Return true if (ns, event) is registered. Useful in tests.
func has_event(ns: StringName, event: StringName) -> bool:
	return _streams.has(_key(ns, event))


func _key(ns: StringName, event: StringName) -> StringName:
	return StringName(String(ns) + "/" + String(event))
