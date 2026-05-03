extends Node2D
## One-shot pixel-burst explosions, scene-only and pooled. The parent triggers
## a burst at a world position; we spawn ephemeral particle records and fade
## them out over EXPLOSION_DURATION_MS via _draw. No timers per-burst — a
## single _process drains expired records.

const InvadersConfig := preload("res://scripts/invaders/core/invaders_config.gd")
const Palette := preload("res://scripts/invaders/invaders_palette.gd")

const EXPLOSION_DURATION_MS: int = 200
const EXPLOSION_PARTICLE_COUNT: int = 8
const EXPLOSION_PARTICLE_SIZE: float = 1.5
const EXPLOSION_RADIUS: float = 6.0

# Active bursts: Array of {x, y, t0_ms, particles: Array[Vector2]} where each
# Vector2 is a unit-direction offset multiplied by EXPLOSION_RADIUS at peak.
var _bursts: Array = []


func configure(_cfg: InvadersConfig) -> void:
	set_process(true)
	queue_redraw()


func spawn(world_x: float, world_y: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var particles: Array = []
	for i in range(EXPLOSION_PARTICLE_COUNT):
		var theta: float = rng.randf_range(0.0, TAU)
		particles.append(Vector2(cos(theta), sin(theta)))
	_bursts.append({"x": world_x, "y": world_y, "t0_ms": Time.get_ticks_msec(), "particles": particles})
	queue_redraw()


func _process(_delta: float) -> void:
	if _bursts.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var i: int = 0
	while i < _bursts.size():
		var b: Dictionary = _bursts[i]
		if now - int(b["t0_ms"]) > EXPLOSION_DURATION_MS:
			_bursts.remove_at(i)
		else:
			i += 1
	queue_redraw()


func _draw() -> void:
	var now: int = Time.get_ticks_msec()
	for b in _bursts:
		var t: float = clampf(float(now - int(b["t0_ms"])) / float(EXPLOSION_DURATION_MS), 0.0, 1.0)
		var radius: float = EXPLOSION_RADIUS * t
		var alpha: float = 1.0 - t
		var color := Color(Palette.EXPLOSION.r, Palette.EXPLOSION.g, Palette.EXPLOSION.b, alpha)
		var bx: float = float(b["x"])
		var by: float = float(b["y"])
		for p in b["particles"]:
			var pv: Vector2 = p
			draw_rect(Rect2(Vector2(bx + pv.x * radius - EXPLOSION_PARTICLE_SIZE * 0.5,
					by + pv.y * radius - EXPLOSION_PARTICLE_SIZE * 0.5),
					Vector2(EXPLOSION_PARTICLE_SIZE, EXPLOSION_PARTICLE_SIZE)), color, true)
