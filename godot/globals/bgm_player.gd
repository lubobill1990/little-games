extends AudioStreamPlayer
## Namespaced background-music player autoload.
##
## Each game registers its tracks under its own namespace, then asks for one
## by name. Switching tracks fades the current one out and the new one in.
## Pause/resume is supported via `stream_paused` so the pause overlay can stop
## the music without losing playback position.
##
## Bus: this `AudioStreamPlayer`'s `bus` is set to `"Music"` in `_ready()`. The
## bus layout is established by `default_bus_layout.tres` (set in
## `project.godot` under `audio/buses/default_bus_layout`).
##
## Loop semantics: registered streams have their `loop` flag set to true so
## tracks repeat naturally. Godot 4.6's `AudioStreamMP3` supports this directly
## — no `finished`-callback fallback needed.

const _MUSIC_BUS: StringName = &"Music"
const _FADE_STEPS: int = 20

# (StringName key) -> AudioStream
var _tracks: Dictionary = {}
var _fade_tween: Tween


func _ready() -> void:
	bus = _MUSIC_BUS


## Register a single track. Returns true if the file was found, false if
## missing. Looping is enabled for `AudioStreamMP3` / `AudioStreamOggVorbis`
## streams so callers don't have to remember to set it themselves.
func register_track(ns: StringName, name: StringName, path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var s: Resource = load(path)
	if s == null:
		return false
	# Enable looping where the stream type supports it. Wrapped in `has_method`
	# so we don't crash if a future stream type lacks the property.
	if "loop" in s:
		s.set("loop", true)
	_tracks[_key(ns, name)] = s
	return true


## Play a registered track with a linear-volume fade-in. Silent no-op if the
## track isn't registered (callers don't need to know whether assets are
## present on this build). If a different track is currently playing, it fades
## out first.
func play_track(ns: StringName, name: StringName, fade_in: float = 0.5) -> void:
	var s: AudioStream = _tracks.get(_key(ns, name), null)
	if s == null:
		return
	if stream == s and playing:
		return
	stream = s
	stream_paused = false
	volume_db = -40.0
	play()
	_fade_to(0.0, max(0.0, fade_in))


## Stop the current track with a linear-volume fade-out.
func stop_track(fade_out: float = 0.5) -> void:
	if not playing:
		return
	if fade_out <= 0.0:
		stop()
		return
	_fade_to(-40.0, fade_out)
	# Schedule the actual stop after the fade completes.
	if _fade_tween != null:
		_fade_tween.finished.connect(_on_fadeout_done, CONNECT_ONE_SHOT)


## Pause the current track in place (no fade). Used by the pause overlay.
func pause() -> void:
	if playing:
		stream_paused = true


## Resume from a pause() position.
func resume() -> void:
	if stream_paused:
		stream_paused = false


## Return true if (ns, name) is registered. Useful in tests.
func has_track(ns: StringName, name: StringName) -> bool:
	return _tracks.has(_key(ns, name))


func _fade_to(target_db: float, duration: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "volume_db", target_db, duration)


func _on_fadeout_done() -> void:
	stop()


func _key(ns: StringName, name: StringName) -> StringName:
	return StringName(String(ns) + "/" + String(name))
