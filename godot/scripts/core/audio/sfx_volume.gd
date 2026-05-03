extends RefCounted
## Helpers for wiring an AudioStreamPlayer to the master/SFX volume sliders
## in `Settings`. Avoids each scene re-implementing the same volume math.

const MIN_DB: float = -60.0


## Combine master and sfx (each 0..1) into the effective linear volume.
static func linear_volume(master: float, sfx: float) -> float:
	return clamp(master * sfx, 0.0, 1.0)


static func set_player_volume(player: AudioStreamPlayer, linear: float) -> void:
	if linear <= 0.0:
		player.volume_db = MIN_DB
	else:
		player.volume_db = linear_to_db(clamp(linear, 0.0, 1.0))


static func linear_to_db(v: float) -> float:
	if v <= 0.0001:
		return MIN_DB
	return 20.0 * log(v) / log(10.0)
