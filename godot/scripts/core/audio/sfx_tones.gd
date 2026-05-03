extends RefCounted
## Procedural SFX tone synthesis.
##
## No binary OGG assets — generates short PCM blips at runtime. Keeps the
## CI workflow free of LFS / asset bookkeeping and the headless test suite
## free of audio-decoder dependencies.
##
## Usage: `var stream := SfxTones.tone(440.0, 0.12)` returns an
## AudioStreamWAV ready to feed an `AudioStreamPlayer.stream`. For chords
## or two-note jingles, sum samples via `tone_chord` / `tone_sequence`.

const SAMPLE_RATE: int = 22050


## Single sine tone with linear attack/decay envelope. `freq_hz` 0 → silence.
static func tone(freq_hz: float, duration_s: float, volume: float = 0.6) -> AudioStreamWAV:
	var n: int = int(duration_s * SAMPLE_RATE)
	var samples: PackedByteArray = PackedByteArray()
	samples.resize(n * 2)
	var attack: int = int(0.01 * SAMPLE_RATE)
	var decay: int = int(0.04 * SAMPLE_RATE)
	for i in n:
		var env: float = 1.0
		if i < attack:
			env = float(i) / float(max(1, attack))
		elif i > n - decay:
			env = float(n - i) / float(max(1, decay))
		var s: float = sin(TAU * freq_hz * float(i) / float(SAMPLE_RATE))
		var v: int = int(clamp(s * env * volume, -1.0, 1.0) * 32767.0)
		samples[i * 2] = v & 0xFF
		samples[i * 2 + 1] = (v >> 8) & 0xFF
	return _wav_from_pcm(samples)


## Sum two sines for a quick "merge" feel. Frequencies in Hz.
static func tone_chord(freqs: Array, duration_s: float, volume: float = 0.5) -> AudioStreamWAV:
	var n: int = int(duration_s * SAMPLE_RATE)
	var samples: PackedByteArray = PackedByteArray()
	samples.resize(n * 2)
	var attack: int = int(0.01 * SAMPLE_RATE)
	var decay: int = int(0.05 * SAMPLE_RATE)
	var k: int = max(1, freqs.size())
	for i in n:
		var env: float = 1.0
		if i < attack:
			env = float(i) / float(max(1, attack))
		elif i > n - decay:
			env = float(n - i) / float(max(1, decay))
		var sum: float = 0.0
		for f in freqs:
			sum += sin(TAU * float(f) * float(i) / float(SAMPLE_RATE))
		var s: float = sum / float(k)
		var v: int = int(clamp(s * env * volume, -1.0, 1.0) * 32767.0)
		samples[i * 2] = v & 0xFF
		samples[i * 2 + 1] = (v >> 8) & 0xFF
	return _wav_from_pcm(samples)


## Concatenate a list of (freq_hz, duration_s) pairs into one stream.
## Use Vector2(freq, dur). freq=0 = silence segment.
static func tone_sequence(steps: Array, volume: float = 0.55) -> AudioStreamWAV:
	var total_n: int = 0
	for step in steps:
		total_n += int(step.y * SAMPLE_RATE)
	var samples: PackedByteArray = PackedByteArray()
	samples.resize(total_n * 2)
	var idx: int = 0
	for step in steps:
		var freq: float = step.x
		var seg_n: int = int(step.y * SAMPLE_RATE)
		var attack: int = int(0.005 * SAMPLE_RATE)
		var decay: int = int(0.01 * SAMPLE_RATE)
		for i in seg_n:
			var env: float = 1.0
			if i < attack:
				env = float(i) / float(max(1, attack))
			elif i > seg_n - decay:
				env = float(seg_n - i) / float(max(1, decay))
			var s: float = 0.0
			if freq > 0.0:
				s = sin(TAU * freq * float(i) / float(SAMPLE_RATE))
			var v: int = int(clamp(s * env * volume, -1.0, 1.0) * 32767.0)
			samples[idx * 2] = v & 0xFF
			samples[idx * 2 + 1] = (v >> 8) & 0xFF
			idx += 1
	return _wav_from_pcm(samples)


static func _wav_from_pcm(samples: PackedByteArray) -> AudioStreamWAV:
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SAMPLE_RATE
	w.stereo = false
	w.data = samples
	return w


## A `tone()` whose `loop_mode` is set to LOOP_FORWARD before return — for
## sustained loops like the UFO drone. Kept here so callers in `scenes/` don't
## have to spell out an `AudioStreamWAV` type, which would trip the
## `Audio containment` CI lint (issue #43).
static func looping_tone(freq: float, duration_s: float, volume: float) -> AudioStreamWAV:
	var w: AudioStreamWAV = tone(freq, duration_s, volume)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return w
