class_name King
extends Node2D

## King Grid Movement System
## Reusable grid-based chess piece movement system following godot-master guidelines.
## Provides 8-way directional navigation, mouse click & drag movement, held-key auto-repeat,
## physics-inspired hop arcs, squash & stretch, dynamic shadows, landing dust, and elastic wall bumps.

signal hop_started(from_tile: Vector2i, to_tile: Vector2i, direction: Vector2i)
signal hop_landed(tile: Vector2i, direction: Vector2i)
signal bump_occurred(from_tile: Vector2i, attempted_tile: Vector2i, direction: Vector2i)
signal tile_changed(new_tile: Vector2i, notation: String)

const ACTION_MOVE_UP: StringName = &"move_up"
const ACTION_MOVE_DOWN: StringName = &"move_down"
const ACTION_MOVE_LEFT: StringName = &"move_left"
const ACTION_MOVE_RIGHT: StringName = &"move_right"
const ACTION_MOVE_UP_LEFT: StringName = &"move_up_left"
const ACTION_MOVE_UP_RIGHT: StringName = &"move_up_right"
const ACTION_MOVE_DOWN_LEFT: StringName = &"move_down_left"
const ACTION_MOVE_DOWN_RIGHT: StringName = &"move_down_right"
const ACTION_RESET: StringName = &"reset"

@export_group("Grid & Movement")
@export var start_tile: Vector2i = Vector2i.ZERO ## Starting tile (center of board)
@export_range(0.05, 0.4, 0.01) var hop_duration: float = 0.16
@export_range(10.0, 80.0, 1.0) var hop_height: float = 34.0
@export var default_tile_size: float = 72.0 ## Fallback tile size for standalone testing (F6)
@export var enable_mouse_control: bool = true   ## Click/drag with mouse to move King

@export_group("Juice & Visuals")
@export var base_sprite_scale: Vector2 = Vector2(0.27, 0.27)
@export var base_shadow_scale: Vector2 = Vector2(0.38, 0.18)
@export var base_sprite_pos: Vector2 = Vector2(0.0, -6.0)
@export var base_shadow_pos: Vector2 = Vector2(0.0, 20.0)
@export var squash_amount: float = 0.22 ## Landing squash intensity
@export var stretch_amount: float = 0.18 ## Apex jump stretch intensity

@export_group("Audio")
@export var hop_sound: AudioStream = preload("res://sfx/hop_bump.wav")
@export var wall_bump_sound: AudioStream = preload("res://sfx/wall_bump.wav")
@export var hop_sound_trigger: GameEnums.HopSoundTrigger = GameEnums.HopSoundTrigger.ON_HOP_START
@export_range(0.0, 0.3, 0.01) var pitch_randomness: float = 0.08
@export_range(0.5, 2.0, 0.05) var base_pitch: float = 1.0
@export_range(-20.0, 20.0, 0.5) var hop_volume_db: float = 0.0
@export_range(-20.0, 20.0, 0.5) var wall_bump_volume_db: float = 2.0

@onready var sprite: Sprite2D = %Sprite2D if has_node("%Sprite2D") else null
@onready var shadow: Sprite2D = %Shadow if has_node("%Shadow") else null
@onready var dust_particles: CPUParticles2D = %DustParticles if has_node("%DustParticles") else null
@onready var audio_player: AudioStreamPlayer2D = %AudioPlayer if has_node("%AudioPlayer") else null

var board: ChessBoard = null
var tile_pos: Vector2i = Vector2i.ZERO
var is_moving: bool = false
var buffered_input: Vector2i = Vector2i.ZERO
var step_count: int = 0
var custom_can_step_predicate: Callable = Callable()

var _move_tween: Tween = null
var _hop_tween: Tween = null
var _shadow_tween: Tween = null
var _squash_tween: Tween = null
var _bump_tween: Tween = null

func _ready() -> void:
	add_to_group(&"player")

	if audio_player != null:
		audio_player.bus = AudioHelper.SFX_BUS

	_reset_visual_transforms()
	tile_pos = start_tile
	position = _tile_to_local(tile_pos)

func _exit_tree() -> void:
	_kill_all_tweens()

## Connects the King to a ChessBoard instance
func setup(p_board: ChessBoard) -> void:
	board = p_board
	tile_pos = start_tile
	position = _tile_to_local(tile_pos)
	step_count = 0
	if board != null:
		board.update_size_for_king(tile_pos)
	_emit_tile_changed()

func _reset_visual_transforms() -> void:
	if sprite != null:
		sprite.scale = base_sprite_scale
		sprite.position = base_sprite_pos
	if shadow != null:
		shadow.scale = base_shadow_scale
		shadow.position = base_shadow_pos
		shadow.modulate.a = 1.0

func _tile_to_local(p_tile: Vector2i) -> Vector2:
	if board != null:
		return board.tile_to_local(p_tile)
	return Vector2(float(p_tile.x) * default_tile_size, float(p_tile.y) * default_tile_size)

func _is_valid_tile(p_tile: Vector2i) -> bool:
	if custom_can_step_predicate.is_valid() and not custom_can_step_predicate.call(p_tile):
		return false
	if board != null:
		return board.can_step_to_tile(p_tile)
	return absi(p_tile.x) <= 8 and absi(p_tile.y) <= 8

func get_chess_notation() -> String:
	if board != null:
		return board.get_chess_notation(tile_pos)
	return "(%d, %d)" % [tile_pos.x, tile_pos.y]

func _emit_tile_changed() -> void:
	tile_changed.emit(tile_pos, get_chess_notation())

# ==============================================================================
# INPUT HANDLING (Keyboard, Gamepad & Mouse Clicking)
# ==============================================================================

func _process(_delta: float) -> void:
	if enable_mouse_control and board != null:
		var hover_tile: Vector2i = _get_tile_under_mouse()
		board.set_highlighted_tile(hover_tile)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_RESET, false):
		get_viewport().set_input_as_handled()
		reset_to_start()
		return

	# 1. Mouse Click to Move
	if enable_mouse_control and event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var target_tile: Vector2i = _get_tile_under_mouse()
			var step_dir: Vector2i = _get_direction_toward_tile(target_tile)
			if step_dir != Vector2i.ZERO:
				get_viewport().set_input_as_handled()
				_request_step(step_dir)
				return

	# 2. Directional Keyboard/Gamepad Input
	var dir: Vector2i = _get_event_direction(event)
	if dir != Vector2i.ZERO:
		get_viewport().set_input_as_handled()
		_request_step(dir)

func _request_step(dir: Vector2i) -> void:
	if not is_moving:
		buffered_input = Vector2i.ZERO
		try_step(dir)
	else:
		buffered_input = dir

func _get_tile_under_mouse() -> Vector2i:
	if board != null:
		var local_in_board: Vector2 = board.get_local_mouse_position()
		return board.local_to_tile(local_in_board)
	var local: Vector2 = get_local_mouse_position()
	return tile_pos + Vector2i(
		floori((local.x + default_tile_size * 0.5) / default_tile_size),
		floori((local.y + default_tile_size * 0.5) / default_tile_size)
	)

func _get_direction_toward_tile(target: Vector2i) -> Vector2i:
	var diff: Vector2i = target - tile_pos
	if diff == Vector2i.ZERO:
		return Vector2i.ZERO
	return Vector2i(clampi(diff.x, -1, 1), clampi(diff.y, -1, 1))

func _get_event_direction(event: InputEvent) -> Vector2i:
	if not event.is_pressed():
		return Vector2i.ZERO

	# 1. Action map checks
	if event.is_action_pressed(ACTION_MOVE_UP_LEFT, false):
		return Vector2i(-1, -1)
	if event.is_action_pressed(ACTION_MOVE_UP_RIGHT, false):
		return Vector2i(1, -1)
	if event.is_action_pressed(ACTION_MOVE_DOWN_LEFT, false):
		return Vector2i(-1, 1)
	if event.is_action_pressed(ACTION_MOVE_DOWN_RIGHT, false):
		return Vector2i(1, 1)

	if event.is_action_pressed(ACTION_MOVE_UP, false) or event.is_action_pressed(&"ui_up", false):
		return Vector2i(0, -1)
	if event.is_action_pressed(ACTION_MOVE_DOWN, false) or event.is_action_pressed(&"ui_down", false):
		return Vector2i(0, 1)
	if event.is_action_pressed(ACTION_MOVE_LEFT, false) or event.is_action_pressed(&"ui_left", false):
		return Vector2i(-1, 0)
	if event.is_action_pressed(ACTION_MOVE_RIGHT, false) or event.is_action_pressed(&"ui_right", false):
		return Vector2i(1, 0)

	# 2. Keycode fallbacks
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		var dir: Vector2i = _match_key_direction(key_event.physical_keycode)
		if dir == Vector2i.ZERO:
			dir = _match_key_direction(key_event.keycode)
		return dir

	return Vector2i.ZERO

func _match_key_direction(code: Key) -> Vector2i:
	match code:
		KEY_W, KEY_UP, KEY_KP_8:
			return Vector2i(0, -1)
		KEY_S, KEY_DOWN, KEY_KP_2:
			return Vector2i(0, 1)
		KEY_A, KEY_LEFT, KEY_KP_4:
			return Vector2i(-1, 0)
		KEY_D, KEY_RIGHT, KEY_KP_6:
			return Vector2i(1, 0)
		KEY_Q, KEY_KP_7:
			return Vector2i(-1, -1)
		KEY_E, KEY_KP_9:
			return Vector2i(1, -1)
		KEY_Z, KEY_KP_1:
			return Vector2i(-1, 1)
		KEY_C, KEY_KP_3:
			return Vector2i(1, 1)
		_:
			return Vector2i.ZERO

## Polls currently held directional input (enables smooth continuous movement while holding down keys)
func _get_currently_held_direction() -> Vector2i:
	# Diagonals first
	if Input.is_key_pressed(KEY_Q) or Input.is_action_pressed(ACTION_MOVE_UP_LEFT):
		return Vector2i(-1, -1)
	if Input.is_key_pressed(KEY_E) or Input.is_action_pressed(ACTION_MOVE_UP_RIGHT):
		return Vector2i(1, -1)
	if Input.is_key_pressed(KEY_Z) or Input.is_action_pressed(ACTION_MOVE_DOWN_LEFT):
		return Vector2i(-1, 1)
	if Input.is_key_pressed(KEY_C) or Input.is_action_pressed(ACTION_MOVE_DOWN_RIGHT):
		return Vector2i(1, 1)

	var x: int = 0
	var y: int = 0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT) or Input.is_action_pressed(ACTION_MOVE_LEFT) or Input.is_action_pressed(&"ui_left"):
		x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT) or Input.is_action_pressed(ACTION_MOVE_RIGHT) or Input.is_action_pressed(&"ui_right"):
		x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_action_pressed(ACTION_MOVE_UP) or Input.is_action_pressed(&"ui_up"):
		y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_action_pressed(ACTION_MOVE_DOWN) or Input.is_action_pressed(&"ui_down"):
		y += 1

	if x != 0 or y != 0:
		return Vector2i(clampi(x, -1, 1), clampi(y, -1, 1))

	# Mouse button held down
	if enable_mouse_control and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and board != null:
		var target: Vector2i = _get_tile_under_mouse()
		var toward: Vector2i = _get_direction_toward_tile(target)
		if toward != Vector2i.ZERO:
			return toward

	return Vector2i.ZERO

# ==============================================================================
# STEP & HOP MOVEMENT
# ==============================================================================

## Attempts to step 1 tile in the specified direction. Returns true if movement started.
func try_step(dir: Vector2i) -> bool:
	if is_moving:
		return false

	var target_tile: Vector2i = tile_pos + dir
	if not _is_valid_tile(target_tile):
		play_bump_animation(target_tile)
		return false

	if board != null:
		board.update_size_for_king(target_tile)

	hop_to_tile(target_tile)
	return true

## Smoothly animates a hop to the target tile coordinate
func hop_to_tile(target_tile: Vector2i) -> void:
	is_moving = true
	var from_tile: Vector2i = tile_pos
	var dir: Vector2i = target_tile - from_tile
	tile_pos = target_tile
	step_count += 1

	hop_started.emit(from_tile, target_tile, dir)
	if hop_sound_trigger == GameEnums.HopSoundTrigger.ON_HOP_START or hop_sound_trigger == GameEnums.HopSoundTrigger.ON_BOTH:
		play_hop_sound()

	var target_pos: Vector2 = _tile_to_local(target_tile)
	_kill_all_tweens()

	# 1. Translation to destination tile
	_move_tween = create_tween()
	_move_tween.tween_property(self, ^"position", target_pos, hop_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 2. Vertical jump arc
	if sprite != null:
		_hop_tween = create_tween()
		_hop_tween.tween_property(sprite, ^"position:y", base_sprite_pos.y - hop_height, hop_duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hop_tween.tween_property(sprite, ^"position:y", base_sprite_pos.y, hop_duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

		# 3. Squash and stretch
		_squash_tween = create_tween()
		var stretch_scale: Vector2 = Vector2(base_sprite_scale.x * (1.0 - stretch_amount * 0.5), base_sprite_scale.y * (1.0 + stretch_amount))
		_squash_tween.tween_property(sprite, ^"scale", stretch_scale, hop_duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var squash_scale: Vector2 = Vector2(base_sprite_scale.x * (1.0 + squash_amount), base_sprite_scale.y * (1.0 - squash_amount * 0.8))
		_squash_tween.tween_property(sprite, ^"scale", squash_scale, hop_duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_squash_tween.tween_property(sprite, ^"scale", base_sprite_scale, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 4. Shadow scaling and altitude fading
	if shadow != null:
		_shadow_tween = create_tween()
		_shadow_tween.tween_property(shadow, ^"scale", base_shadow_scale * 0.65, hop_duration * 0.5).set_trans(Tween.TRANS_QUAD)
		_shadow_tween.parallel().tween_property(shadow, ^"modulate:a", 0.6, hop_duration * 0.5)
		_shadow_tween.tween_property(shadow, ^"scale", base_shadow_scale, hop_duration * 0.5).set_trans(Tween.TRANS_QUAD)
		_shadow_tween.parallel().tween_property(shadow, ^"modulate:a", 1.0, hop_duration * 0.5)

	# 5. Landing callback
	_move_tween.chain().tween_callback(func() -> void:
		is_moving = false
		_on_landing(dir)
		_consume_buffered_input()
	)

func _on_landing(dir: Vector2i) -> void:
	if dust_particles != null:
		dust_particles.restart()
		dust_particles.emitting = true

	if hop_sound_trigger == GameEnums.HopSoundTrigger.ON_LANDING or hop_sound_trigger == GameEnums.HopSoundTrigger.ON_BOTH:
		play_hop_sound()

	hop_landed.emit(tile_pos, dir)
	_emit_tile_changed()

func _consume_buffered_input() -> void:
	# 1. Process queued buffered input
	if buffered_input != Vector2i.ZERO:
		var next_dir: Vector2i = buffered_input
		buffered_input = Vector2i.ZERO
		try_step(next_dir)
		return

	# 2. Check if player is holding down keys or mouse button (continuous movement)
	var held_dir: Vector2i = _get_currently_held_direction()
	if held_dir != Vector2i.ZERO:
		try_step(held_dir)

## Plays an elastic bounce when the King tries to step into a boundary or blocked tile
func play_bump_animation(blocked_tile: Vector2i) -> void:
	is_moving = true
	var dir_i: Vector2i = blocked_tile - tile_pos
	bump_occurred.emit(tile_pos, blocked_tile, dir_i)
	play_wall_bump_sound()

	var bump_dir: Vector2 = Vector2(dir_i).normalized()
	var offset_vec: Vector2 = bump_dir * 14.0
	var original_pos: Vector2 = position

	_kill_all_tweens()
	_reset_visual_transforms()

	_bump_tween = create_tween()
	_bump_tween.tween_property(self, ^"position", original_pos + offset_vec, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_bump_tween.tween_property(self, ^"position", original_pos, 0.12).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	_bump_tween.tween_callback(func() -> void:
		is_moving = false
		buffered_input = Vector2i.ZERO
	)

## Instantly snaps the King to a specific tile without hopping
func teleport_to_tile(target_tile: Vector2i) -> void:
	_kill_all_tweens()
	is_moving = false
	buffered_input = Vector2i.ZERO
	tile_pos = target_tile
	position = _tile_to_local(tile_pos)
	_reset_visual_transforms()
	if board != null:
		board.update_size_for_king(tile_pos)
	_emit_tile_changed()

## Resets the King to the initial starting tile
func reset_to_start() -> void:
	teleport_to_tile(start_tile)
	step_count = 0

# ==============================================================================
# AUDIO
# ==============================================================================

func play_hop_sound() -> void:
	AudioHelper.play_sound_2d(audio_player, hop_sound, hop_volume_db, base_pitch, pitch_randomness)

func play_wall_bump_sound() -> void:
	AudioHelper.play_sound_2d(audio_player, wall_bump_sound, wall_bump_volume_db, 1.0, 0.04)

func _kill_all_tweens() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
		_move_tween = null
	if _hop_tween != null and _hop_tween.is_valid():
		_hop_tween.kill()
		_hop_tween = null
	if _shadow_tween != null and _shadow_tween.is_valid():
		_shadow_tween.kill()
		_shadow_tween = null
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()
		_squash_tween = null
	if _bump_tween != null and _bump_tween.is_valid():
		_bump_tween.kill()
		_bump_tween = null
