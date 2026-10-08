class_name AudioHelper
extends RefCounted

## AudioHelper utility for Love & War
## Standardizes audio playback with randomized pitch variations and safe bus assignment.

const SFX_BUS: StringName = &"SFX"

static func play_sound_2d(
	player: AudioStreamPlayer2D,
	stream: AudioStream,
	volume_db: float = 0.0,
	base_pitch: float = 1.0,
	pitch_randomness: float = 0.0
) -> void:
	if player == null or stream == null:
		return
	player.bus = SFX_BUS
	player.stream = stream
	player.volume_db = volume_db
	if pitch_randomness > 0.0:
		player.pitch_scale = base_pitch + randf_range(-pitch_randomness, pitch_randomness)
	else:
		player.pitch_scale = base_pitch
	player.play()

static func play_sound(
	player: AudioStreamPlayer,
	stream: AudioStream,
	volume_db: float = 0.0,
	base_pitch: float = 1.0,
	pitch_randomness: float = 0.0
) -> void:
	if player == null or stream == null:
		return
	player.bus = SFX_BUS
	player.stream = stream
	player.volume_db = volume_db
	if pitch_randomness > 0.0:
		player.pitch_scale = base_pitch + randf_range(-pitch_randomness, pitch_randomness)
	else:
		player.pitch_scale = base_pitch
	player.play()
