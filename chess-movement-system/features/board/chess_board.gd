class_name ChessBoard
extends Node2D

## ChessBoard System
## A modular, procedural expandable chessboard.
## Features dynamic expansion when the King approaches the perimeter, smooth shrink hysteresis,
## algebraic chess notation, procedural border frame with drop shadow, and tile fade-in effects.

signal board_resized(new_radius: int, is_expanding: bool)

@export_group("Dynamic Resizing")
@export var dynamic_resizing: bool = true       ## If true, board dynamically expands/shrinks with King
@export var min_radius: int = 3                 ## Minimum board radius (3 = 7x7 board: -3..+3)
@export var max_radius: int = 8                 ## Maximum board radius (8 = 17x17 board: -8..+8)
@export var radius: int = 3:                    ## Current active integer radius
	set(value):
		radius = clampi(value, min_radius, max_radius)
		target_radius = radius
		queue_redraw()
@export var buffer_tiles: int = 1               ## Number of buffer tiles to maintain beyond King
@export var expand_smooth_speed: float = 12.0   ## Snappy expansion lerp speed
@export var shrink_smooth_speed: float = 5.0    ## Gentle shrinkage lerp speed
@export var shrink_delay: float = 0.45          ## Seconds to wait before shrinking (prevents jitter)

@export_group("Geometry & Tile")
@export var tile_size: float = 72.0:
	set(value):
		tile_size = maxf(16.0, value)
		queue_redraw()

@export_group("Color Palette")
@export var dark_tile_color: Color = Color("#565FA0")
@export var light_tile_color: Color = Color("#ECEEF8")
@export var highlight_color: Color = Color(1.0, 0.85, 0.2, 0.35)

@export_group("Outer Frame")
@export var border_margin: float = 44.0
@export var frame_bg_color: Color = Color("#171826")
@export var frame_edge_color: Color = Color("#24283D")
@export var frame_line_color: Color = Color("#4A5375")
@export var shadow_color: Color = Color(0.04, 0.05, 0.07, 0.65)
@export var shadow_offset: Vector2 = Vector2(0.0, 6.0)

@export_group("Coordinates")
@export var show_coordinates: bool = true
@export var coordinate_color: Color = Color("#8E99BD")
@export var coordinate_font: Font = null
@export var coordinate_font_size: int = 18
@export var show_all_sides: bool = true

@export_group("Audio")
@export var expand_sound: AudioStream = preload("res://sfx/board_expand.wav")
@export var shrink_sound: AudioStream = preload("res://sfx/board_shrink.wav")
@export var resize_volume_db: float = -2.0

@onready var resize_audio: AudioStreamPlayer2D = %ResizeAudio if has_node("%ResizeAudio") else null

var target_radius: int = 3
var animated_radius: float = 3.0
var _shrink_timer: float = 0.0
var _pending_shrink_radius: int = 3
var _highlighted_tile: Vector2i = Vector2i(999, 999)

func _ready() -> void:
	radius = clampi(radius, min_radius, max_radius)
	target_radius = radius
	_pending_shrink_radius = radius
	animated_radius = float(radius)

	if resize_audio != null:
		resize_audio.bus = AudioHelper.SFX_BUS

	queue_redraw()

func _process(delta: float) -> void:
	if dynamic_resizing:
		_process_dynamic_resizing(delta)

	# Smoothly animate animated_radius toward target_radius
	if not is_equal_approx(animated_radius, float(target_radius)):
		var speed: float = expand_smooth_speed if float(target_radius) > animated_radius else shrink_smooth_speed
		var blend: float = 1.0 - exp(-speed * delta)
		animated_radius = lerpf(animated_radius, float(target_radius), blend)

		if absf(animated_radius - float(target_radius)) < 0.002:
			animated_radius = float(target_radius)

		queue_redraw()

# ==============================================================================
# DYNAMIC RESIZING ENGINE
# ==============================================================================

func _process_dynamic_resizing(delta: float) -> void:
	var desired_radius: int = calculate_desired_radius()

	# 1. Immediate outward expansion if King needs more room
	if desired_radius > target_radius:
		_shrink_timer = 0.0
		_pending_shrink_radius = desired_radius
		target_radius = desired_radius
		radius = target_radius
		board_resized.emit(radius, true)
		play_resize_sound(true)
		queue_redraw()

	# 2. Hysteresis delay before shrinking inward
	if _shrink_timer > 0.0:
		_shrink_timer -= delta
		if _shrink_timer <= 0.0:
			var safe_shrink: int = maxi(_pending_shrink_radius, calculate_desired_radius())
			if safe_shrink < target_radius:
				target_radius = safe_shrink
				radius = target_radius
				board_resized.emit(radius, false)
				play_resize_sound(false)
				queue_redraw()
			else:
				_pending_shrink_radius = target_radius

## Calculates the required board radius to encompass the King plus buffer tiles
func calculate_desired_radius(override_king_tile: Variant = null) -> int:
	var req_radius: int = min_radius

	var k_tile: Vector2i = Vector2i.ZERO
	var has_king: bool = false

	if override_king_tile is Vector2i:
		k_tile = override_king_tile
		has_king = true
	elif is_inside_tree():
		for player: Node in get_tree().get_nodes_in_group(&"player"):
			var p_tile: Variant = player.get("tile_pos")
			if p_tile is Vector2i:
				k_tile = p_tile
				has_king = true
				break

	if has_king:
		var k_dist: int = maxi(absi(k_tile.x), absi(k_tile.y))
		req_radius = maxi(req_radius, k_dist + buffer_tiles)

	return clampi(req_radius, min_radius, max_radius)

## Called immediately when the King initiates movement to prepare the board
func update_size_for_king(king_target_tile: Vector2i) -> void:
	if not dynamic_resizing:
		return

	var desired: int = calculate_desired_radius(king_target_tile)

	if desired > target_radius:
		_shrink_timer = 0.0
		_pending_shrink_radius = desired
		target_radius = desired
		radius = target_radius
		board_resized.emit(radius, true)
		play_resize_sound(true)
		queue_redraw()
	elif desired < target_radius:
		_pending_shrink_radius = desired
		_shrink_timer = shrink_delay
	else:
		if _pending_shrink_radius < target_radius:
			_shrink_timer = 0.0
			_pending_shrink_radius = target_radius

## Sets the board radius manually (e.g. from UI or level config)
func set_board_radius(new_radius: int, animate: bool = true) -> void:
	var clamped: int = clampi(new_radius, min_radius, max_radius)
	if clamped == target_radius:
		return

	var is_expanding: bool = clamped > target_radius
	target_radius = clamped
	radius = target_radius
	_pending_shrink_radius = target_radius
	_shrink_timer = 0.0

	if not animate:
		animated_radius = float(radius)

	board_resized.emit(radius, is_expanding)
	play_resize_sound(is_expanding)
	queue_redraw()

func play_resize_sound(is_expanding: bool) -> void:
	if resize_audio == null:
		return
	var stream: AudioStream = expand_sound if is_expanding else shrink_sound
	AudioHelper.play_sound_2d(resize_audio, stream, resize_volume_db, 1.0, 0.03)

# ==============================================================================
# COORDINATE CONVERSIONS & CHESS NOTATION
# ==============================================================================

## Converts a grid coordinate (e.g. Vector2i(0,0)) to local pixel position
func tile_to_local(tile: Vector2i) -> Vector2:
	return Vector2(float(tile.x) * tile_size, float(tile.y) * tile_size)

## Converts local pixel position to the nearest grid coordinate
func local_to_tile(local_pos: Vector2) -> Vector2i:
	var x: int = floori((local_pos.x + tile_size * 0.5) / tile_size)
	var y: int = floori((local_pos.y + tile_size * 0.5) / tile_size)
	return Vector2i(x, y)

## Checks whether a tile is currently active within the board's animated perimeter
func is_valid_tile(tile: Vector2i) -> bool:
	var boundary: int = maxi(maxi(radius, target_radius), int(ceilf(animated_radius)))
	return absi(tile.x) <= boundary and absi(tile.y) <= boundary

## Checks whether the King can step to a tile (allows expansion up to max_radius)
func can_step_to_tile(tile: Vector2i) -> bool:
	if dynamic_resizing:
		return absi(tile.x) <= max_radius and absi(tile.y) <= max_radius
	return is_valid_tile(tile)

## Alternates colors matching chessboard pattern
func is_tile_dark(tile: Vector2i) -> bool:
	return posmod(tile.x + tile.y, 2) == 0

## Converts grid coordinate into standard chess notation (e.g. (0,0) -> "D4" at radius 3)
func get_chess_notation(tile: Vector2i) -> String:
	var active_rad: int = int(roundf(animated_radius))
	var col_idx: int = tile.x + active_rad
	var rank_num: int = (active_rad - tile.y) + 1

	if col_idx < 0:
		return "??"

	var file_char: String = _get_column_name(col_idx)
	return "%s%d" % [file_char, rank_num]

func _get_column_name(idx: int) -> String:
	if idx < 0:
		return ""
	if idx < 26:
		return String.chr(65 + idx)
	var first: String = String.chr(65 + floori(float(idx) / 26.0) - 1)
	var second: String = String.chr(65 + (idx % 26))
	return first + second

func get_center_tile() -> Vector2i:
	return Vector2i.ZERO

func get_grid_dimensions_string() -> String:
	var span: int = target_radius * 2 + 1
	return "%dx%d (R%d)" % [span, span, target_radius]

func set_highlighted_tile(tile: Vector2i) -> void:
	if _highlighted_tile != tile:
		_highlighted_tile = tile
		queue_redraw()

## Returns the local bounding Rect2 covering the board frame, tiles, coordinates and drop shadow.
## If override_radius is provided (>= 0.0), computes for that radius; otherwise uses animated_radius.
func get_visual_rect(override_radius: float = -1.0) -> Rect2:
	var cur_rad: float = override_radius if override_radius >= 0.0 else animated_radius
	var half_span: float = (cur_rad + 0.5) * tile_size
	var total_half: float = half_span + border_margin
	var top_left: Vector2 = Vector2(-total_half, -total_half)
	var size: Vector2 = Vector2(total_half * 2.0, total_half * 2.0 + maxf(0.0, shadow_offset.y))
	return Rect2(top_left, size)

## Returns the total pixel dimensions of the board frame and shadow at the given radius
func get_visual_size(override_radius: float = -1.0) -> Vector2:
	var rect: Rect2 = get_visual_rect(override_radius)
	return rect.size

# ==============================================================================
# PROCEDURAL DRAWING
# ==============================================================================

func _draw() -> void:
	var cur_rad: float = animated_radius
	var max_ring: int = int(ceilf(cur_rad))

	var half_span: float = (cur_rad + 0.5) * tile_size
	var total_half_span: float = half_span + border_margin
	var outer_rect: Rect2 = Rect2(-total_half_span, -total_half_span, total_half_span * 2.0, total_half_span * 2.0)
	var grid_rect: Rect2 = Rect2(-half_span, -half_span, half_span * 2.0, half_span * 2.0)

	# 1. Outer drop shadow
	var shadow_rect: Rect2 = Rect2(outer_rect.position + shadow_offset, outer_rect.size)
	draw_rect(shadow_rect, shadow_color)

	# 2. Outer frame body & border
	draw_rect(outer_rect, frame_bg_color)
	draw_rect(outer_rect, frame_edge_color, false, 2.5)

	# 3. Tiles with smooth opacity fade at perimeter
	for y: int in range(-max_ring, max_ring + 1):
		for x: int in range(-max_ring, max_ring + 1):
			var tile_ring: float = maxf(absf(float(x)), absf(float(y)))
			var fade: float = clampf(cur_rad - (tile_ring - 1.0), 0.0, 1.0)
			if fade <= 0.001:
				continue

			var tile: Vector2i = Vector2i(x, y)
			var tile_pos: Vector2 = Vector2(float(x) * tile_size - tile_size * 0.5, float(y) * tile_size - tile_size * 0.5)
			var tile_rect: Rect2 = Rect2(tile_pos, Vector2(tile_size, tile_size))

			var tile_color: Color = dark_tile_color if is_tile_dark(tile) else light_tile_color
			tile_color.a = fade

			draw_rect(tile_rect, tile_color)
			draw_rect(tile_rect, Color(0.0, 0.0, 0.0, 0.15 * fade), false, 1.0)

	# 4. Highlighted tile (if active)
	if can_step_to_tile(_highlighted_tile):
		var hl_pos: Vector2 = tile_to_local(_highlighted_tile) - Vector2(tile_size * 0.5, tile_size * 0.5)
		var is_within_current: bool = is_valid_tile(_highlighted_tile)
		var hl_col: Color = highlight_color if is_within_current else Color(highlight_color.r, highlight_color.g, highlight_color.b, 0.22)
		draw_rect(Rect2(hl_pos, Vector2(tile_size, tile_size)), hl_col)
		draw_rect(Rect2(hl_pos, Vector2(tile_size, tile_size)), Color(hl_col, 0.85), false, 2.0)

	# 5. Inner grid border
	draw_rect(grid_rect, frame_line_color, false, 2.0)

	# 6. Coordinate labels
	if show_coordinates:
		_draw_coordinates(cur_rad, max_ring, half_span)

func _draw_coordinates(cur_rad: float, max_ring: int, half_span: float) -> void:
	var font: Font = coordinate_font if coordinate_font != null else ThemeDB.fallback_font
	var font_size: int = coordinate_font_size
	var ascent: float = font.get_ascent(font_size)
	var descent: float = font.get_descent(font_size)
	var vert_offset: float = (ascent - descent) * 0.5

	var active_rad: int = int(roundf(cur_rad))
	var left_x: float = -half_span - border_margin * 0.5
	var right_x: float = half_span + border_margin * 0.5
	var bottom_y: float = half_span + border_margin * 0.5 + vert_offset
	var top_y: float = -half_span - border_margin * 0.5 + vert_offset

	# Ranks (vertical numbers)
	for y: int in range(-max_ring, max_ring + 1):
		var row_ring: float = absf(float(y))
		var row_fade: float = clampf(cur_rad - (row_ring - 1.0), 0.0, 1.0)
		if row_fade <= 0.001:
			continue

		var rank_num: int = (active_rad - y) + 1
		var rank_str: String = str(rank_num)
		var text_sz: Vector2 = font.get_string_size(rank_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
		var center_y: float = float(y) * tile_size
		var col: Color = coordinate_color
		col.a *= row_fade

		draw_string(font, Vector2(left_x - text_sz.x * 0.5, center_y + vert_offset), rank_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, col)
		if show_all_sides:
			draw_string(font, Vector2(right_x - text_sz.x * 0.5, center_y + vert_offset), rank_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, col)

	# Files (horizontal letters)
	for x: int in range(-max_ring, max_ring + 1):
		var col_ring: float = absf(float(x))
		var col_fade: float = clampf(cur_rad - (col_ring - 1.0), 0.0, 1.0)
		if col_fade <= 0.001:
			continue

		var col_idx: int = x + active_rad
		var file_str: String = _get_column_name(col_idx)
		var text_sz: Vector2 = font.get_string_size(file_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
		var center_x: float = float(x) * tile_size
		var col: Color = coordinate_color
		col.a *= col_fade

		draw_string(font, Vector2(center_x - text_sz.x * 0.5, bottom_y), file_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, col)
		if show_all_sides:
			draw_string(font, Vector2(center_x - text_sz.x * 0.5, top_y), file_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, col)
