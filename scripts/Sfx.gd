extends Node

## Global sound-effect player (autoload). Non-positional, pooled.
## Pitch jitter uses a private RNG so gameplay determinism is untouched.

const STREAMS := {
	"shot": preload("res://assets/audio/shot.wav"),
	"hit_impact": preload("res://assets/audio/hit_impact.wav"),
	"unit_death": preload("res://assets/audio/unit_death.wav"),
	"select": preload("res://assets/audio/select.wav"),
	"footstep_1": preload("res://assets/audio/footstep_1.wav"),
	"footstep_2": preload("res://assets/audio/footstep_2.wav"),
	"overwatch_set": preload("res://assets/audio/overwatch_set.wav"),
	"reload": preload("res://assets/audio/reload.wav"),
	"miss": preload("res://assets/audio/miss.wav"),
	"turn_player": preload("res://assets/audio/turn_player.wav"),
	"turn_enemy": preload("res://assets/audio/turn_enemy.wav"),
	"win": preload("res://assets/audio/win.wav"),
	"lose": preload("res://assets/audio/lose.wav"),
}

# Per-sound mix so call sites stay one-liners. The sustained stings carry
# roughly twice the RMS of the impacts, so they sit a good deal lower here
# to land at a comparable loudness.
const BASE_DB := {
	"shot": -3.0,
	"hit_impact": -3.0,
	"unit_death": -6.0,
	"select": -11.0,
	"footstep_1": -15.0,
	"footstep_2": -15.0,
	"overwatch_set": -8.0,
	"reload": -9.0,
	"miss": -8.0,
	"turn_player": -9.0,
	"turn_enemy": -8.0,
	"win": -5.0,
	"lose": -5.0,
}

# Tails run long now (a rifle report rings for half a second), so a full-auto
# burst can have a dozen voices alive at once.
const POOL_SIZE := 14
const PITCH_VAR := 0.06

var _players: Array[AudioStreamPlayer] = []
var _rng := RandomNumberGenerator.new()
var _steal_index := 0


func _ready() -> void:
	_rng.randomize()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)


## pitch_var 0.0 keeps melodic stings on-pitch; default jitter suits noise SFX.
func play(sound: String, volume_db := 0.0, pitch_var := PITCH_VAR) -> void:
	var player := _idle_player()
	player.stream = STREAMS[sound]
	player.volume_db = BASE_DB[sound] + volume_db
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_var, pitch_var)
	player.play()


func _idle_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	# Pool saturated: steal round-robin so no single sound gets cut twice.
	_steal_index = (_steal_index + 1) % _players.size()
	return _players[_steal_index]
