extends SceneTree

## Generates ThinShot's placeholder retro SFX as 16-bit PCM mono 44.1kHz WAVs.
## Run: godot --headless -s tools/gen_sfx.gd
## Deterministic: noise uses a fixed-seed LCG, so output bytes are reproducible.

const RATE := 44100
const OUT_DIR := "res://assets/audio"

var _lcg := 1


func _noise() -> float:
	_lcg = (_lcg * 1103515245 + 12345) & 0x7FFFFFFF
	return float(_lcg) / float(0x40000000) - 1.0


static func _env(t: float, dur: float, k: float) -> float:
	return exp(-k * t / dur)


func _write_wav(path: String, samples: PackedFloat32Array) -> void:
	# Normalize to 0.7 peak.
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain := 0.7 / peak
	var f := FileAccess.open(path, FileAccess.WRITE)
	var n := samples.size()
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + n * 2)
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(RATE)
	f.store_32(RATE * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(n * 2)
	for s in samples:
		f.store_16(int(clampf(s * gain, -1.0, 1.0) * 32767.0) & 0xFFFF)
	print("wrote %s (%d samples)" % [path, n])


## Square-wave tone burst with exponential decay, appended to buf.
func _tone(buf: PackedFloat32Array, freq: float, dur: float, k: float,
		vibrato := 0.0) -> void:
	var n := int(dur * RATE)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := freq * (1.0 + vibrato * sin(TAU * 6.0 * t))
		phase += f / RATE
		var v := 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		buf.append(v * _env(t, dur, k))


## Square sweep from f0 to f1 over dur.
func _sweep(buf: PackedFloat32Array, f0: float, f1: float, dur: float, k: float,
		vibrato := 0.0) -> void:
	var n := int(dur * RATE)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / dur) * (1.0 + vibrato * sin(TAU * 6.0 * t))
		phase += f / RATE
		var v := 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		buf.append(v * _env(t, dur, k))


## Low-passed noise burst (simple one-pole filter).
func _noise_burst(buf: PackedFloat32Array, dur: float, k: float,
		cutoff: float, attack := 0.001) -> void:
	var n := int(dur * RATE)
	var alpha := clampf(TAU * cutoff / RATE, 0.0, 1.0)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += alpha * (_noise() - lp)
		var a := minf(t / attack, 1.0)
		buf.append(lp * a * _env(t, dur, k))


static func _mix(a: PackedFloat32Array, b: PackedFloat32Array,
		wa: float, wb: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := maxi(a.size(), b.size())
	out.resize(n)
	for i in n:
		var va := a[i] if i < a.size() else 0.0
		var vb := b[i] if i < b.size() else 0.0
		out[i] = va * wa + vb * wb
	return out


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	_lcg = 7
	var noise_part := PackedFloat32Array()
	_noise_burst(noise_part, 0.14, 7.0, 6000.0)
	var thump := PackedFloat32Array()
	_sweep(thump, 220.0, 60.0, 0.14, 5.0)
	_write_wav(OUT_DIR + "/shot.wav", _mix(noise_part, thump, 0.6, 0.4))

	_lcg = 11
	var crack := PackedFloat32Array()
	_noise_burst(crack, 0.12, 10.0, 5000.0)
	var thud := PackedFloat32Array()
	_tone(thud, 150.0, 0.12, 6.0)
	_write_wav(OUT_DIR + "/hit_impact.wav", _mix(crack, thud, 0.55, 0.45))

	_lcg = 13
	var death := PackedFloat32Array()
	_sweep(death, 440.0, 80.0, 0.45, 4.0, 0.04)
	var tail := PackedFloat32Array()
	tail.resize(int(0.30 * RATE))
	_noise_burst(tail, 0.15, 5.0, 900.0)
	_write_wav(OUT_DIR + "/unit_death.wav", _mix(death, tail, 0.8, 0.2))

	var sel := PackedFloat32Array()
	_tone(sel, 880.0, 0.08, 8.0)
	_write_wav(OUT_DIR + "/select.wav", sel)

	_lcg = 17
	var step1 := PackedFloat32Array()
	_noise_burst(step1, 0.06, 9.0, 1200.0)
	_write_wav(OUT_DIR + "/footstep_1.wav", step1)

	_lcg = 19
	var step2 := PackedFloat32Array()
	_noise_burst(step2, 0.054, 9.0, 900.0)
	_write_wav(OUT_DIR + "/footstep_2.wav", step2)

	var ow := PackedFloat32Array()
	_tone(ow, 523.25, 0.09, 5.0)
	_tone(ow, 783.99, 0.11, 5.0)
	_write_wav(OUT_DIR + "/overwatch_set.wav", ow)

	var tp := PackedFloat32Array()
	for freq in [261.63, 329.63, 392.0]:
		_tone(tp, freq, 0.11, 4.0)
	_write_wav(OUT_DIR + "/turn_player.wav", tp)

	var te := PackedFloat32Array()
	for freq in [196.0, 155.56, 130.81]:
		_tone(te, freq, 0.11, 4.0)
	_write_wav(OUT_DIR + "/turn_enemy.wav", te)

	var win := PackedFloat32Array()
	for freq in [261.63, 329.63, 392.0, 523.25]:
		_tone(win, freq, 0.12, 5.0)
	var chord := PackedFloat32Array()
	for freq in [261.63, 329.63, 392.0, 523.25]:
		var note := PackedFloat32Array()
		_tone(note, freq, 0.42, 3.0)
		chord = _mix(chord, note, 1.0, 0.3)
	win.append_array(chord)
	_write_wav(OUT_DIR + "/win.wav", win)

	var lose := PackedFloat32Array()
	for freq in [164.81, 130.81, 110.0, 87.31]:
		_tone(lose, freq, 0.2, 3.0)
	_write_wav(OUT_DIR + "/lose.wav", lose)

	# Magazine out, magazine in, bolt released.
	_lcg = 23
	var reload := PackedFloat32Array()
	_noise_burst(reload, 0.05, 12.0, 3000.0)
	for i in int(0.06 * RATE):
		reload.append(0.0)
	_noise_burst(reload, 0.05, 12.0, 2200.0)
	var thunk := PackedFloat32Array()
	_tone(thunk, 110.0, 0.10, 7.0)
	var head := reload.size()
	reload.resize(head + thunk.size())
	for i in thunk.size():
		reload[head + i] = thunk[i] * 0.8
	_write_wav(OUT_DIR + "/reload.wav", reload)

	quit()
