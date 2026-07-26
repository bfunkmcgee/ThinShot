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
	"turn_player": preload("res://assets/audio/turn_player.wav"),
	"turn_enemy": preload("res://assets/audio/turn_enemy.wav"),
	"win": preload("res://assets/audio/win.wav"),
	"lose": preload("res://assets/audio/lose.wav"),
}

# Per-sound mix so call sites stay one-liners.
const BASE_DB := {
	"shot": -4.0,
	"hit_impact": -3.0,
	"unit_death": -3.0,
	"select": -9.0,
	"footstep_1": -14.0,
	"footstep_2": -14.0,
	"overwatch_set": -6.0,
	"turn_player": -5.0,
	"turn_enemy": -5.0,
	"win": 0.0,
	"lose": 0.0,
}

const POOL_SIZE := 8
const PITCH_VAR := 0.06

var _players: Array[AudioStreamPlayer] = []
var _rng := RandomNumberGenerator.new()


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
	return _players[0]  # steal the oldest slot
