extends SceneTree
## Development tool: synthesizes the example sound files used by the OasisFx
## SFX example presets, so the repository ships no third-party audio.
##
##   godot --headless --path . --script res://tools/synth_example_sounds.gd
##
## Output: addons/oasis_fx/presets/examples/audio/*.wav (16-bit mono, 44.1 kHz).
## Everything is computed from fixed seeds, so the files are identical on
## every run. The sounds are made for this project and released as CC0
## (see the LICENSE.txt written next to them).

const OUT_DIR := "res://addons/oasis_fx/presets/examples/audio"
const RATE := 44100

var _seed := 1


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_save("whoosh_1", _whoosh(0.34, 300.0, 3200.0, 11))
	_save("whoosh_2", _whoosh(0.30, 380.0, 3800.0, 12))
	_save("whoosh_3", _whoosh(0.38, 260.0, 2800.0, 13))
	_save("impact", _impact())
	_save("fire_crackle", _crackle(0.9, 21))
	_save("sizzle_loop", _sizzle(2.0))
	_save("chime", _chime())
	_save("sparkle", _sparkle())
	var license := FileAccess.open(OUT_DIR + "/LICENSE.txt", FileAccess.WRITE)
	license.store_string("These example sounds were synthesized by tools/synth_example_sounds.gd for OasisFx.\nThey contain no recorded or third-party material and are dedicated to the public domain (CC0 1.0).\n")
	license.close()
	print("wrote example sounds to " + OUT_DIR)
	quit()


# --- Generators (return float samples in -1..1) -----------------------------

## Noise through a low-pass filter whose cutoff sweeps up and down.
func _whoosh(seconds: float, low_hz: float, high_hz: float, seed: int) -> PackedFloat32Array:
	_seed = seed
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / n
		var sweep := sin(PI * t)
		var cutoff := lerpf(low_hz, high_hz, sweep)
		var a := 1.0 - exp(-TAU * cutoff / RATE)
		lp += a * (_noise() - lp)
		lp2 += a * (lp - lp2)
		var env := pow(sin(PI * pow(t, 0.7)), 1.6)
		out[i] = lp2 * env * 2.2
	return out


## Low sine thump with falling pitch plus a short noise click.
func _impact() -> PackedFloat32Array:
	_seed = 31
	var n := int(0.45 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var freq := 45.0 + 110.0 * exp(-t * 18.0)
		phase += TAU * freq / RATE
		var body := sin(phase) * exp(-t * 7.0)
		lp += 0.35 * (_noise() - lp)
		var click := lp * exp(-t * 60.0) * 0.8
		out[i] = (body * 0.9 + click) * minf(1.0, t * 400.0)
	return out


## Sparse pops over a soft rumble.
func _crackle(seconds: float, seed: int) -> PackedFloat32Array:
	_seed = seed
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var pop := 0.0
	for i in n:
		var t := float(i) / n
		if _uniform() < 0.0016:
			pop = 0.4 + 0.6 * _uniform()
		pop *= 0.985
		lp += 0.05 * (_noise() - lp)
		var env := minf(1.0, t * 12.0) * (1.0 - t) ** 0.6
		out[i] = (lp * 0.5 + _noise() * pop) * env
	return out


## Bright noise with crackles; the first and last 0.1 s are cross-faded so the
## file loops without a click.
func _sizzle(seconds: float) -> PackedFloat32Array:
	_seed = 41
	var n := int(seconds * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var hp_prev := 0.0
	var hp := 0.0
	var pop := 0.0
	for i in n:
		var x := _noise()
		hp = 0.92 * (hp + x - hp_prev)
		hp_prev = x
		if _uniform() < 0.003:
			pop = 0.3 + 0.5 * _uniform()
		pop *= 0.97
		raw[i] = hp * 0.22 + _noise() * pop * 0.5
	var fade := int(0.1 * RATE)
	var out := PackedFloat32Array()
	out.resize(n - fade)
	for i in n - fade:
		out[i] = raw[i]
	for i in fade:
		var w := float(i) / fade
		out[i] = raw[i] * w + raw[n - fade + i] * (1.0 - w)
	return out


## Two bell-like partial groups, the second slightly delayed.
func _chime() -> PackedFloat32Array:
	var n := int(1.0 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var a := _bell(t, 880.0) * 0.5
		var b := _bell(t - 0.12, 1318.5) * 0.45 if t >= 0.12 else 0.0
		out[i] = a + b
	return out


func _bell(t: float, f: float) -> float:
	var env := exp(-t * 4.5) * minf(1.0, t * 300.0)
	return (sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.76 * t) * exp(-t * 6.0) + 0.2 * sin(TAU * f * 5.4 * t) * exp(-t * 9.0)) * env


## Short high blips at random pitches.
func _sparkle() -> PackedFloat32Array:
	_seed = 51
	var n := int(0.7 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in 9:
		var start := int((0.03 + 0.065 * k + 0.02 * _uniform()) * RATE)
		var f := 1800.0 + 2200.0 * _uniform()
		var amp := 0.25 + 0.15 * _uniform()
		for j in int(0.12 * RATE):
			if start + j >= n:
				break
			var t := float(j) / RATE
			out[start + j] += sin(TAU * f * t) * exp(-t * 38.0) * amp * minf(1.0, t * 2000.0)
	return out


# --- Helpers ----------------------------------------------------------------

## Deterministic LCG: same numbers on every platform and Godot version.
func _uniform() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF
	return float(_seed) / float(0x7FFFFFFF)


func _noise() -> float:
	return _uniform() * 2.0 - 1.0


func _save(name: String, samples: PackedFloat32Array) -> void:
	var peak := 0.0
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain := 0.89 / peak if peak > 0.0 else 1.0  # normalize to about -1 dBFS
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, clampi(roundi(samples[i] * gain * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	var path := OUT_DIR + "/" + name + ".wav"
	var err := wav.save_to_wav(path)
	print("%s %s (%.2f s)" % [path, error_string(err), float(samples.size()) / RATE])
