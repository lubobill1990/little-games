extends GutTest
## Pure helper tests for Haptics.tier_for + SfxTones tone synthesis.

const Haptics := preload("res://scripts/core/input/haptics.gd")
const SfxTones := preload("res://scripts/core/audio/sfx_tones.gd")
const SfxVolume := preload("res://scripts/core/audio/sfx_volume.gd")


func _tiers() -> Array:
	return [
		[16,    0.2,  60],
		[128,   0.4, 100],
		[1024,  0.6, 140],
		[INF,   0.9, 200],
	]


func test_tier_for_low_value_picks_first_tier() -> void:
	var t: Dictionary = Haptics.tier_for(8, _tiers())
	assert_almost_eq(float(t["intensity"]), 0.2, 0.001)
	assert_eq(int(t["duration_ms"]), 60)


func test_tier_for_mid_value_picks_middle_tier() -> void:
	var t: Dictionary = Haptics.tier_for(64, _tiers())
	assert_almost_eq(float(t["intensity"]), 0.4, 0.001)


func test_tier_for_threshold_boundary_picks_next_tier() -> void:
	# value == threshold → NOT < threshold; picks next tier up.
	var t: Dictionary = Haptics.tier_for(16, _tiers())
	assert_almost_eq(float(t["intensity"]), 0.4, 0.001)


func test_tier_for_huge_value_picks_cap() -> void:
	var t: Dictionary = Haptics.tier_for(2048, _tiers())
	assert_almost_eq(float(t["intensity"]), 0.9, 0.001)
	assert_eq(int(t["duration_ms"]), 200)


func test_tone_produces_correct_byte_length() -> void:
	var w: AudioStreamWAV = SfxTones.tone(440.0, 0.05, 0.5)
	# n samples = int(0.05 * 22050) = 1102; 16-bit mono = 2 bytes/sample.
	var n: int = int(0.05 * SfxTones.SAMPLE_RATE)
	assert_eq(w.data.size(), n * 2)
	assert_eq(w.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_eq(w.mix_rate, SfxTones.SAMPLE_RATE)


func test_tone_sequence_concatenates_durations() -> void:
	var w: AudioStreamWAV = SfxTones.tone_sequence([
		Vector2(440.0, 0.05),
		Vector2(660.0, 0.10),
	])
	# Sum of int(dur * rate) per step, doubled for 2 bytes/sample.
	var total_n: int = int(0.05 * SfxTones.SAMPLE_RATE) + int(0.10 * SfxTones.SAMPLE_RATE)
	assert_eq(w.data.size(), total_n * 2)


func test_volume_clamps_and_combines() -> void:
	assert_almost_eq(SfxVolume.linear_volume(1.0, 1.0), 1.0, 0.001)
	assert_almost_eq(SfxVolume.linear_volume(0.5, 0.5), 0.25, 0.001)
	# Out-of-range inputs clamp.
	assert_almost_eq(SfxVolume.linear_volume(2.0, 0.5), 1.0, 0.001)
	assert_almost_eq(SfxVolume.linear_volume(-1.0, 0.5), 0.0, 0.001)


func test_volume_zero_emits_min_db() -> void:
	var p := AudioStreamPlayer.new()
	add_child_autofree(p)
	SfxVolume.set_player_volume(p, 0.0)
	assert_almost_eq(p.volume_db, SfxVolume.MIN_DB, 0.01)
