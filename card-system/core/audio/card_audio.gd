class_name CardAudio
extends Node

## Central audio manager and sound pool for the card system.
## Provides tactile audio feedback for drawing, picking up, docking, placing,
## reordering, and discarding playing cards with voice pooling and pitch variation,
## as well as looping ambient background music.

signal sound_played(sound_name: StringName, stream: AudioStream)
signal music_started(stream: AudioStream)
signal music_stopped

const POOL_SIZE: int = 12
const PRIORITY_LOW: int = 0
const PRIORITY_STANDARD: int = 1
const PRIORITY_HIGH: int = 2

## Active singleton instance.
static var instance: CardAudio = null

@export_group("Audio State")
## Master toggle for card sound effects.
@export var sfx_enabled: bool = true

## Dedicated audio bus for sound effects.
@export var audio_bus: StringName = &"SFX"

@export_group("Background Music")
## Master toggle for background music.
@export var music_enabled: bool = true

## Looping background music stream (e.g. saloon ambient ragtime).
@export var music_stream: AudioStream = preload("res://sfx/music/tap-room-rag.mp3")

## Ambient background volume in dB (gentle background ambiance, not overpowering).
@export_range(-40.0, 0.0, 0.5) var music_volume_db: float = -16.0

## Duration of smooth music fade-in in seconds (0.0 plays immediately at target volume).
@export_range(0.0, 5.0, 0.1) var music_fade_in_duration: float = 0.0

## Dedicated audio bus for background music.
@export var music_bus: StringName = &"Music"

@export_group("Sound Resources")
## Audio stream played when a card is placed, docked, or dropped.
@export var place_sound: AudioStream = preload("res://sfx/cards/placing-playing-card.mp3")

## Audio stream variations played when drawing, taking, or lifting a card.
@export var take_sounds: Array[AudioStream] = [
	preload("res://sfx/cards/taking-playing-card.mp3"),
	preload("res://sfx/cards/taking-playing-card-2.mp3"),
	preload("res://sfx/cards/taking-playing-card-3.mp3"),
]

@export_group("SFX Volume Adjustments (dB)")
@export var draw_volume_db: float = 0.0
@export var take_volume_db: float = -1.0
@export var dock_volume_db: float = 0.0
@export var place_volume_db: float = -2.0
@export var discard_volume_db: float = 0.5
@export var reorder_volume_db: float = -5.0
@export var hover_volume_db: float = -14.0

# Voice pool internals
var _players: Array[AudioStreamPlayer] = []
var _priorities: PackedInt32Array = PackedInt32Array()
var _started_msec: PackedInt64Array = PackedInt64Array()
var _last_played_msec: Dictionary = {}
var _resolved_sfx_bus: StringName = &"Master"
var _resolved_music_bus: StringName = &"Master"

# Background music player internals
var _music_player: AudioStreamPlayer = null
var _music_tween: Tween = null


func _init() -> void:
	if instance == null:
		instance = self
	_ensure_pool()
	_ensure_music_player()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if instance == self:
			instance = null


func _enter_tree() -> void:
	if instance == null:
		instance = self
	_ensure_pool()
	_ensure_music_player()


func _ready() -> void:
	if instance == null:
		instance = self
	_ensure_pool()
	_ensure_music_player()

	if music_enabled and music_stream:
		play_music(music_fade_in_duration)


func _exit_tree() -> void:
	if _music_tween:
		_music_tween.kill()
	if instance == self:
		instance = null


func _input(event: InputEvent) -> void:
	# Autoplay safety: resume / start music on ANY user interaction (motion, click, key, touch)
	if music_enabled and _music_player and is_inside_tree() and not _music_player.playing:
		if (
			event is InputEventMouse
			or event is InputEventKey
			or event is InputEventScreenTouch
			or event is InputEventScreenDrag
		):
			play_music(0.0)


func _ensure_pool() -> void:
	if not _players.is_empty():
		return

	if AudioServer.get_bus_index(audio_bus) != -1:
		_resolved_sfx_bus = audio_bus
	else:
		_resolved_sfx_bus = &"Master"

	_players.clear()
	_priorities.resize(POOL_SIZE)
	_started_msec.resize(POOL_SIZE)

	for i: int in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "AudioVoice_%d" % i
		player.bus = _resolved_sfx_bus
		add_child(player)
		_players.append(player)
		_priorities[i] = PRIORITY_LOW
		_started_msec[i] = 0
		player.finished.connect(_on_player_finished.bind(i))


func _ensure_music_player() -> void:
	if _music_player != null:
		return

	if AudioServer.get_bus_index(music_bus) != -1:
		_resolved_music_bus = music_bus
	else:
		_resolved_music_bus = &"Master"

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "BackgroundMusicPlayer"
	_music_player.bus = _resolved_music_bus
	add_child(_music_player)

	_configure_music_stream(music_stream)
	_music_player.finished.connect(_on_music_finished)


func _configure_music_stream(stream: AudioStream) -> void:
	if stream and stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	if _music_player:
		_music_player.stream = stream


# -----------------------------------------------------------------------------
# Background Music Control
# -----------------------------------------------------------------------------

## Starts or transitions background music with looping and optional fade-in.
func play_music(fade_in: float = -1.0) -> void:
	if not music_enabled or not music_stream:
		return

	_ensure_music_player()

	if _music_player.stream != music_stream:
		_configure_music_stream(music_stream)

	if _music_tween:
		_music_tween.kill()

	var duration: float = music_fade_in_duration if fade_in < 0.0 else fade_in

	if duration > 0.0 and is_inside_tree():
		_music_player.volume_db = -50.0
		if not _music_player.playing:
			_music_player.play()
		_music_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_music_tween.tween_property(_music_player, "volume_db", music_volume_db, duration)
	else:
		_music_player.volume_db = music_volume_db
		if not _music_player.playing and is_inside_tree():
			_music_player.play()

	music_started.emit(_music_player.stream)


## Smoothly fades out and stops background music.
func stop_music(fade_out: float = 0.5) -> void:
	if not _music_player:
		return

	if _music_tween:
		_music_tween.kill()

	if fade_out > 0.0 and is_inside_tree() and _music_player.playing:
		_music_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_music_tween.tween_property(_music_player, "volume_db", -50.0, fade_out)
		_music_tween.tween_callback(func() -> void:
			if _music_player:
				_music_player.stop()
				music_stopped.emit()
		)
	else:
		if _music_player.playing:
			_music_player.stop()
		music_stopped.emit()


## Dynamically adjusts the music volume in dB.
func set_music_volume(volume_db: float) -> void:
	music_volume_db = volume_db
	if _music_player and _music_player.playing and (not _music_tween or not _music_tween.is_running()):
		_music_player.volume_db = music_volume_db


func _on_music_finished() -> void:
	# Fail-safe loop restart in case the stream doesn't natively loop
	if music_enabled and is_inside_tree() and _music_player:
		_music_player.play()


# -----------------------------------------------------------------------------
# Public Semantic Sound Triggers
# -----------------------------------------------------------------------------

## Plays a card drawing sound when dealt or drawn from deck.
func play_draw() -> void:
	if not _can_trigger(&"draw", 35):
		return
	var stream := _get_random_take_sound()
	var pitch := randf_range(0.97, 1.03)
	_play_voice(stream, draw_volume_db, pitch, PRIORITY_HIGH)
	sound_played.emit(&"draw", stream)


## Plays a card pickup / drag start sound.
func play_take() -> void:
	if not _can_trigger(&"take", 35):
		return
	var stream := _get_random_take_sound()
	var pitch := randf_range(0.98, 1.05)
	_play_voice(stream, take_volume_db, pitch, PRIORITY_STANDARD)
	sound_played.emit(&"take", stream)


## Plays a tactile snap sound when a card successfully docks into a slot.
func play_dock() -> void:
	if not _can_trigger(&"dock", 35):
		return
	var pitch := randf_range(0.98, 1.03)
	_play_voice(place_sound, dock_volume_db, pitch, PRIORITY_HIGH)
	sound_played.emit(&"dock", place_sound)


## Plays a sound when a card is placed down or returned to hand/origin.
func play_place() -> void:
	if not _can_trigger(&"place", 35):
		return
	var pitch := randf_range(0.95, 1.02)
	_play_voice(place_sound, place_volume_db, pitch, PRIORITY_STANDARD)
	sound_played.emit(&"place", place_sound)


## Plays a deeper, weightier sound when a card is discarded onto the discard pile.
func play_discard() -> void:
	if not _can_trigger(&"discard", 35):
		return
	var pitch := randf_range(0.88, 0.94)
	_play_voice(place_sound, discard_volume_db, pitch, PRIORITY_HIGH)
	sound_played.emit(&"discard", place_sound)


## Plays a subtle card slide sound when reordering cards in hand.
func play_reorder() -> void:
	if not _can_trigger(&"reorder", 75):
		return
	var stream := _get_random_take_sound()
	var pitch := randf_range(1.10, 1.25)
	_play_voice(stream, reorder_volume_db, pitch, PRIORITY_LOW)
	sound_played.emit(&"reorder", stream)


## Plays sequential sounds when cards are recycled or shuffled.
func play_shuffle() -> void:
	if not sfx_enabled:
		return
	var tween := create_tween()
	for i in range(3):
		tween.tween_callback(func() -> void:
			var stream := _get_random_take_sound()
			var pitch := randf_range(0.95 + i * 0.05, 1.05 + i * 0.05)
			_play_voice(stream, take_volume_db - 1.0, pitch, PRIORITY_STANDARD)
		)
		tween.tween_interval(0.06)


## Plays a light tactile card tick sound when hovering over a card.
func play_hover() -> void:
	if not _can_trigger(&"hover", 50):
		return
	var stream := _get_random_take_sound()
	var pitch := randf_range(1.25, 1.40)
	_play_voice(stream, hover_volume_db, pitch, PRIORITY_LOW)
	sound_played.emit(&"hover", stream)


# -----------------------------------------------------------------------------
# Static Convenience Helpers (Fail-soft if instance is null)
# -----------------------------------------------------------------------------

static func hover() -> void:
	if instance:
		instance.play_hover()

static func draw() -> void:
	if instance:
		instance.play_draw()


static func take() -> void:
	if instance:
		instance.play_take()


static func dock() -> void:
	if instance:
		instance.play_dock()


static func place() -> void:
	if instance:
		instance.play_place()


static func discard() -> void:
	if instance:
		instance.play_discard()


static func reorder() -> void:
	if instance:
		instance.play_reorder()


static func shuffle() -> void:
	if instance:
		instance.play_shuffle()


static func start_music(fade_in: float = -1.0) -> void:
	if instance:
		instance.play_music(fade_in)


static func stop_background_music(fade_out: float = 0.5) -> void:
	if instance:
		instance.stop_music(fade_out)


# -----------------------------------------------------------------------------
# Voice Pool Engine & Voice Stealing
# -----------------------------------------------------------------------------

func _play_voice(stream: AudioStream, vol_db: float, pitch: float, priority: int) -> AudioStreamPlayer:
	if not sfx_enabled or not stream:
		return null

	var idx := _find_idle_voice()
	if idx < 0:
		idx = _steal_voice(priority)
	if idx < 0:
		return null

	var player := _players[idx]
	player.stream = stream
	player.volume_db = vol_db
	player.pitch_scale = pitch
	player.bus = _resolved_sfx_bus
	_priorities[idx] = clampi(priority, PRIORITY_LOW, PRIORITY_HIGH)
	_started_msec[idx] = Time.get_ticks_msec()
	if is_inside_tree() and player.is_inside_tree():
		player.play()
	return player


## Resets rate-limiting cooldown timers (useful for tests or state resets).
func reset_cooldowns() -> void:
	_last_played_msec.clear()


func _find_idle_voice() -> int:
	for i in range(_players.size()):
		if not _players[i].playing:
			return i
	return -1


func _steal_voice(incoming_priority: int) -> int:
	var best_idx := -1
	var best_priority := 999
	var best_age: int = -1
	var now := Time.get_ticks_msec()

	for i in range(_players.size()):
		var pri := int(_priorities[i])
		if pri >= PRIORITY_HIGH and incoming_priority < PRIORITY_HIGH:
			continue
		if pri > incoming_priority:
			continue
		var age := int(now - _started_msec[i])
		if pri < best_priority or (pri == best_priority and age > best_age):
			best_priority = pri
			best_age = age
			best_idx = i

	if best_idx >= 0:
		_players[best_idx].stop()
	return best_idx


func _on_player_finished(idx: int) -> void:
	_priorities[idx] = PRIORITY_LOW
	_started_msec[idx] = 0


func _can_trigger(event_id: StringName, cooldown_msec: int) -> bool:
	if not sfx_enabled:
		return false
	var now := Time.get_ticks_msec()
	var last: int = _last_played_msec.get(event_id, 0)
	if (now - last) < cooldown_msec:
		return false
	_last_played_msec[event_id] = now
	return true


func _get_random_take_sound() -> AudioStream:
	if take_sounds.is_empty():
		return place_sound
	return take_sounds[randi() % take_sounds.size()]
