extends SceneTree

## Generates Sandline's SFX as 16-bit PCM mono 44.1kHz WAVs.
## Run: godot --headless -s tools/gen_sfx.gd
##
## Design brief: visceral and dark. Every impact is layered as transient +
## body + tail rather than a single burst, weight comes from saturated sub
## content, and the musical stings use low minor and tritone intervals - no
## bright arpeggios. Deterministic: noise runs off a fixed-seed LCG, so the
## committed WAVs are byte-reproducible.

const RATE := 44100
const OUT_DIR := "res://assets/audio"

var _lcg := 1


func _noise() -> float:
	_lcg = (_lcg * 1103515245 + 12345) & 0x7FFFFFFF
	return float(_lcg) / float(0x40000000) - 1.0


## Soft clip. Adds odd harmonics and glues layers into one body.
static func _sat(x: float, drive: float) -> float:
	var y := x * drive
	return y / (1.0 + absf(y))


static func _env(t: float, dur: float, k: float) -> float:
	return exp(-k * t / dur)


static func _blank(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


static func _mix_into(dst: PackedFloat32Array, src: PackedFloat32Array,
		gain: float, offset := 0) -> void:
	var need := offset + src.size()
	if dst.size() < need:
		dst.resize(need)
	for i in src.size():
		dst[offset + i] += src[i] * gain


## Exponential pitch sweep. Sine for weight, square for grit.
func _sweep(dur: float, f0: float, f1: float, k: float, square := false,
		attack := 0.002) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f: float = f0 * pow(f1 / f0, t / dur)
		phase += f / RATE
		var v := sin(TAU * phase)
		if square:
			v = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		out[i] = v * minf(t / attack, 1.0) * _env(t, dur, k)
	return out


## Two detuned sines. The beating between them is what reads as dread.
func _detuned(dur: float, f0: float, f1: float, detune: float, k: float,
		attack := 0.01) -> PackedFloat32Array:
	var a := _sweep(dur, f0, f1, k, false, attack)
	var b := _sweep(dur, f0 * detune, f1 * detune, k, false, attack)
	var out := PackedFloat32Array()
	out.resize(a.size())
	for i in a.size():
		out[i] = (a[i] + b[i]) * 0.5
	return out


## State-variable filtered noise with a swept cutoff. mode: low/band/high.
func _fnoise(dur: float, k: float, fc0: float, fc1: float, q: float,
		mode := "low", attack := 0.001) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var band := 0.0
	var damp: float = clampf(1.0 / maxf(q, 0.5), 0.0, 1.9)
	for i in n:
		var t := float(i) / RATE
		var fc: float = fc0 * pow(fc1 / fc0, t / dur)
		var f: float = clampf(2.0 * sin(PI * minf(fc, RATE * 0.45) / RATE), 0.0, 1.0)
		var high := _noise() - low - damp * band
		band += f * high
		low += f * band
		var v := low
		if mode == "band":
			v = band
		elif mode == "high":
			v = high
		out[i] = v * minf(t / attack, 1.0) * _env(t, dur, k)
	return out


static func _comb(src: PackedFloat32Array, d: int, fb: float,
		length: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(length)
	for i in length:
		var v: float = src[i] if i < src.size() else 0.0
		if i >= d:
			v += out[i - d] * fb
		out[i] = v
	return out


## Cheap room. Three combs at coprime delays, so the tail does not ring
## metallically - it just gives the sound somewhere to die.
static func _room(dry: PackedFloat32Array, tail: float, mix: float) -> PackedFloat32Array:
	var length := dry.size() + int(tail * RATE)
	var out := PackedFloat32Array()
	out.resize(length)
	for i in dry.size():
		out[i] = dry[i]
	var delays := [1103, 1571, 2069]
	var fbs := [0.80, 0.76, 0.71]
	for idx in delays.size():
		var wet := _comb(dry, delays[idx], fbs[idx], length)
		for i in length:
			out[i] += wet[i] * mix
	return out


static func _drive(buf: PackedFloat32Array, amount: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for i in buf.size():
		out[i] = _sat(buf[i], amount)
	return out


func _write_wav(path: String, samples: PackedFloat32Array) -> void:
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain := 0.82 / peak
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
	print("wrote %s (%.2fs)" % [path, float(n) / RATE])


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_shot()
	_hit_impact()
	_unit_death()
	_select()
	_footsteps()
	_overwatch_set()
	_turn_stings()
	_win_lose()
	_reload()
	_miss()
	_explosion()
	_smoke_pop()
	quit()


## Grenade going off: a hard crack off the top, a sub that drops through the
## floor under it, and a long dirty tail of debris raining back down. The
## loudest thing in the mix by a distance - it should feel like the one
## moment the squad stops being outgunned.
func _explosion() -> void:
	_lcg = 29
	var buf := _blank(1.5)
	# Crack: the detonation itself, gone almost immediately.
	_mix_into(buf, _fnoise(0.010, 45.0, 9000.0, 2200.0, 1.0, "high"), 1.0)
	# Body: two sweeps an octave apart so it reads as size, not just bass.
	_mix_into(buf, _sweep(0.55, 240.0, 28.0, 7.0), 1.0)
	_mix_into(buf, _detuned(0.42, 120.0, 22.0, 1.007, 6.0), 0.85)
	# Blast wave: broadband noise collapsing downward.
	_mix_into(buf, _fnoise(0.34, 9.0, 5200.0, 260.0, 1.3, "band"), 0.9)
	# Tail: debris and dust settling, well behind the transient.
	_mix_into(buf, _fnoise(1.1, 4.0, 1500.0, 90.0, 0.7), 0.42, int(0.05 * RATE))
	_mix_into(buf, _fnoise(0.7, 5.5, 620.0, 70.0, 0.9), 0.3, int(0.16 * RATE))
	_write_wav(OUT_DIR + "/explosion.wav", _room(_drive(buf, 2.6), 0.55, 0.30))


## Smoke canister: a dull pop with no crack to it, then the long soft hiss of
## the cloud building. Deliberately the opposite of the frag - nothing sharp.
func _smoke_pop() -> void:
	_lcg = 31
	var buf := _blank(1.1)
	_mix_into(buf, _sweep(0.14, 300.0, 90.0, 14.0), 0.8)
	_mix_into(buf, _fnoise(0.09, 20.0, 1800.0, 500.0, 1.1, "band"), 0.5)
	# The hiss: high, quiet, and much longer than the pop that started it.
	_mix_into(buf, _fnoise(0.95, 2.4, 4200.0, 1900.0, 0.6, "high"), 0.5,
			int(0.04 * RATE))
	_write_wav(OUT_DIR + "/smoke_pop.wav", _room(_drive(buf, 1.4), 0.3, 0.18))


## Rifle report: snap, gut-punch body, and a report rolling away over sand.
func _shot() -> void:
	_lcg = 7
	var buf := _blank(0.5)
	_mix_into(buf, _fnoise(0.008, 40.0, 7000.0, 3000.0, 1.0, "high"), 0.9)
	_mix_into(buf, _fnoise(0.13, 16.0, 2600.0, 700.0, 1.6, "band"), 0.8)
	_mix_into(buf, _sweep(0.24, 190.0, 46.0, 9.0), 1.0)
	_mix_into(buf, _sweep(0.10, 520.0, 120.0, 22.0, true), 0.35)
	_mix_into(buf, _fnoise(0.45, 6.0, 900.0, 180.0, 0.8), 0.3)
	_write_wav(OUT_DIR + "/shot.wav", _room(_drive(buf, 1.9), 0.14, 0.10))


## Round meeting a body: crack, wet thump, low squelch under it.
func _hit_impact() -> void:
	_lcg = 11
	var buf := _blank(0.34)
	_mix_into(buf, _fnoise(0.006, 50.0, 6000.0, 2500.0, 1.0, "high"), 0.7)
	_mix_into(buf, _sweep(0.19, 135.0, 62.0, 11.0), 1.0)
	_mix_into(buf, _fnoise(0.2, 13.0, 2400.0, 320.0, 1.2, "low"), 0.65)
	_write_wav(OUT_DIR + "/hit_impact.wav", _room(_drive(buf, 2.2), 0.1, 0.08))


## A body going down: detuned groan collapsing into a sub drop.
func _unit_death() -> void:
	_lcg = 13
	var buf := _blank(1.05)
	_mix_into(buf, _detuned(0.75, 300.0, 62.0, 1.021, 3.4), 0.85)
	_mix_into(buf, _sweep(0.95, 95.0, 28.0, 2.4), 1.0)
	_mix_into(buf, _fnoise(0.7, 4.5, 1400.0, 190.0, 0.9), 0.5)
	_mix_into(buf, _fnoise(0.05, 30.0, 3000.0, 800.0, 1.4, "band"), 0.4)
	_write_wav(OUT_DIR + "/unit_death.wav", _room(_drive(buf, 1.7), 0.35, 0.2))


## Muted tactical acknowledgement - a stock tap, not a chime.
func _select() -> void:
	_lcg = 3
	var buf := _blank(0.09)
	_mix_into(buf, _sweep(0.055, 320.0, 190.0, 26.0, true), 0.7)
	_mix_into(buf, _fnoise(0.02, 30.0, 2200.0, 900.0, 1.5, "band"), 0.5)
	_write_wav(OUT_DIR + "/select.wav", _drive(buf, 1.5))


## Boots into grit: a low thud with dry sand over the top.
func _footsteps() -> void:
	for variant in 2:
		_lcg = 17 + variant * 6
		var buf := _blank(0.12)
		_mix_into(buf, _sweep(0.07, 105.0 - variant * 14.0, 48.0, 20.0), 0.9)
		_mix_into(buf, _fnoise(0.075, 17.0, 1500.0 - variant * 400.0, 300.0, 0.9), 0.55)
		_write_wav(OUT_DIR + "/footstep_%d.wav" % (variant + 1), _drive(buf, 1.4))


## Weapon settling into the shoulder: metal seating, then a low held tone.
func _overwatch_set() -> void:
	_lcg = 23
	var buf := _blank(0.42)
	_mix_into(buf, _fnoise(0.05, 22.0, 3400.0, 1800.0, 7.0, "band"), 0.8)
	_mix_into(buf, _sweep(0.3, 174.6, 164.8, 5.0), 0.9, int(0.05 * RATE))
	_mix_into(buf, _sweep(0.3, 87.3, 82.4, 4.0), 0.7, int(0.05 * RATE))
	_write_wav(OUT_DIR + "/overwatch_set.wav", _room(_drive(buf, 1.6), 0.16, 0.14))


## Turn stings. Ours is a low minor triad that swells and settles; theirs is
## a tritone - the oldest dissonance there is - crawling upward.
func _turn_stings() -> void:
	_lcg = 31
	var player := _blank(1.0)
	for freq in [110.0, 130.81, 164.81]:
		_mix_into(player, _sweep(0.85, freq, freq * 0.995, 2.6, false, 0.09), 0.6)
	_mix_into(player, _sweep(0.5, 62.0, 55.0, 3.0), 0.8)
	_write_wav(OUT_DIR + "/turn_player.wav", _room(_drive(player, 1.5), 0.3, 0.18))

	_lcg = 37
	var enemy := _blank(1.0)
	_mix_into(enemy, _detuned(0.9, 103.8, 110.0, 1.006, 2.2, 0.14), 0.9)
	_mix_into(enemy, _sweep(0.9, 146.8, 155.6, 2.0, false, 0.18), 0.65)
	_mix_into(enemy, _fnoise(0.85, 2.0, 300.0, 900.0, 1.1), 0.35)
	_write_wav(OUT_DIR + "/turn_enemy.wav", _room(_drive(enemy, 1.8), 0.35, 0.24))


## Endings. Victory is grim rather than triumphant - an open fifth over a
## drum hit. Defeat is a sub collapsing under a beating minor second.
func _win_lose() -> void:
	_lcg = 41
	var win := _blank(1.5)
	_mix_into(win, _sweep(0.3, 150.0, 52.0, 7.0), 1.0)
	for freq in [110.0, 164.81, 220.0]:
		_mix_into(win, _sweep(1.15, freq, freq, 1.9, false, 0.16), 0.55,
				int(0.12 * RATE))
	_write_wav(OUT_DIR + "/win.wav", _room(_drive(win, 1.6), 0.45, 0.26))

	_lcg = 43
	var lose := _blank(1.6)
	_mix_into(lose, _sweep(1.3, 124.0, 27.0, 2.0, false, 0.05), 1.0)
	_mix_into(lose, _detuned(1.25, 110.0, 104.0, 1.045, 2.2, 0.1), 0.7)
	_mix_into(lose, _fnoise(1.2, 2.6, 800.0, 120.0, 0.8), 0.4)
	_write_wav(OUT_DIR + "/lose.wav", _room(_drive(lose, 1.7), 0.5, 0.3))


## Magazine out, magazine in, bolt released - heavy, mechanical.
func _reload() -> void:
	_lcg = 29
	var buf := _blank(0.55)
	_mix_into(buf, _fnoise(0.045, 26.0, 3600.0, 1500.0, 6.0, "band"), 0.75)
	_mix_into(buf, _fnoise(0.05, 22.0, 2800.0, 1100.0, 5.0, "band"), 0.8,
			int(0.14 * RATE))
	_mix_into(buf, _sweep(0.16, 150.0, 58.0, 12.0), 0.9, int(0.14 * RATE))
	_mix_into(buf, _fnoise(0.04, 30.0, 4200.0, 2000.0, 8.0, "band"), 0.7,
			int(0.3 * RATE))
	_mix_into(buf, _sweep(0.13, 120.0, 52.0, 14.0), 0.7, int(0.3 * RATE))
	_write_wav(OUT_DIR + "/reload.wav", _room(_drive(buf, 1.7), 0.12, 0.1))


## A round cracking past your ear and away downrange.
func _miss() -> void:
	_lcg = 47
	var buf := _blank(0.4)
	_mix_into(buf, _fnoise(0.02, 34.0, 6000.0, 3000.0, 2.0, "high"), 0.6)
	_mix_into(buf, _fnoise(0.3, 7.0, 3600.0, 420.0, 5.0, "band"), 1.0)
	_mix_into(buf, _sweep(0.16, 260.0, 70.0, 11.0), 0.35)
	_write_wav(OUT_DIR + "/miss.wav", _room(_drive(buf, 1.6), 0.18, 0.14))
