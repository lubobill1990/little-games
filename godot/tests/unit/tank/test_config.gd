extends GutTest
## tank_config.gd — defaults sanity, tunneling-cap predicate, score/HP lookup.

const TankConfig := preload("res://scripts/tank/core/tank_config.gd")


func _default_cfg() -> TankConfig:
	return TankConfig.new()


func test_defaults_consistent() -> void:
	var c: TankConfig = _default_cfg()
	assert_eq(c.world_w_tiles, 13)
	assert_eq(c.world_h_tiles, 13)
	assert_eq(c.tile_size_sub, 16)
	assert_eq(c.tank_w_tiles, 2)
	assert_eq(c.tank_h_tiles, 2)
	assert_eq(c.rail_snap_sub, 4)
	assert_eq(c.wave_size, 20)
	assert_eq(c.max_alive_enemies, 4)


func test_tunneling_cap_holds_for_defaults() -> void:
	# Per Dev plan §Risks: bullet_speed_max * sub_step_dt < min(half-brick height,
	# tank height) so bullets can't tunnel through. Defaults must satisfy this.
	var c: TankConfig = _default_cfg()
	assert_true(c.tunneling_ok())


func test_tunneling_cap_violated_when_bullet_too_fast() -> void:
	var c: TankConfig = _default_cfg()
	# 16-sub-px-per-step bullet would skip past an 8-sub-px half-brick.
	c.bullet_speed_fast_sub = 16
	assert_false(c.tunneling_ok())


func test_tunneling_cap_violated_when_half_brick_too_thin() -> void:
	var c: TankConfig = _default_cfg()
	# Shrink the tile to make the half-brick thinner than the bullet step.
	c.tile_size_sub = 4  # → half-brick = 2
	# Defaults bullet_speed_normal=1, fast=6 → max 6 ≥ 2 → violates.
	assert_false(c.tunneling_ok())


func test_score_lookup_per_kind() -> void:
	var c: TankConfig = _default_cfg()
	assert_eq(c.score_for_kind("basic"), 100)
	assert_eq(c.score_for_kind("fast"), 200)
	assert_eq(c.score_for_kind("power"), 300)
	assert_eq(c.score_for_kind("armor"), 400)
	# Unknown kind returns 0 — caller must defend its own contract.
	assert_eq(c.score_for_kind("ufo"), 0)


func test_hp_lookup_per_kind() -> void:
	var c: TankConfig = _default_cfg()
	assert_eq(c.hp_for_kind("basic"), 1)
	assert_eq(c.hp_for_kind("fast"), 1)
	assert_eq(c.hp_for_kind("power"), 1)
	assert_eq(c.hp_for_kind("armor"), 4)
	assert_eq(c.hp_for_kind("ufo"), 1)  # default
