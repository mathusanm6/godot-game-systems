class_name CameraController
extends Camera2D

## Camera Controller for Chess Movement System
## Provides smooth target tracking, boundary framing, micro-trauma feedback on steps/bumps,
## and clean framing for the chessboard.

@export_group("Target Tracking")
@export var target: Node2D = null                             ## Primary node to follow (King)
@export var anchor_node: Node2D = null                         ## Anchor (Board center)
@export var board: ChessBoard = null                           ## ChessBoard for dynamic framing bounds
@export_range(0.0, 1.0, 0.05) var follow_bias: float = 0.0   ## Blend between Board center (0.0) and King (1.0). 0.0 keeps board firmly centered
@export_range(1.0, 20.0, 0.5) var follow_speed: float = 6.0  ## Smooth tracking lerp speed

@export_group("Zoom Framing")
@export var auto_framing: bool = true                          ## Automatically zoom to frame the entire board
@export_range(0.2, 2.0, 0.05) var default_zoom: float = 1.0   ## Default zoom level
@export_range(0.1, 1.0, 0.05) var min_zoom: float = 0.4       ## Minimum zoom limit at maximum board expansion
@export_range(0.5, 2.0, 0.05) var max_zoom: float = 1.0       ## Maximum zoom limit at minimal board size
@export_range(1.0, 20.0, 0.5) var zoom_speed: float = 8.0     ## Exponential lerp speed for smooth camera zoom
@export_range(0.0, 200.0, 2.0) var margin_vertical: float = 48.0   ## Vertical screen padding (keeps top/bottom borders and coordinates visible)
@export_range(0.0, 200.0, 2.0) var margin_horizontal: float = 48.0 ## Horizontal screen padding

@export_group("Screen Shake & Trauma")
@export var enable_shake: bool = true
@export var max_offset: Vector2 = Vector2(4.0, 3.0)
@export var max_roll: float = 0.005
@export var shake_decay: float = 6.0
@export var hop_trauma: float = 0.04
@export var landing_trauma: float = 0.08
@export var bump_trauma: float = 0.28
@export var bump_kick_strength: float = 4.0

var trauma: float = 0.0
var directional_kick: Vector2 = Vector2.ZERO
var noise: FastNoiseLite = FastNoiseLite.new()
var noise_time: float = 0.0

func _ready() -> void:
	noise.seed = int(randi())
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.5

	if board == null and anchor_node is ChessBoard:
		board = anchor_node as ChessBoard

	if anchor_node != null:
		global_position = anchor_node.global_position
	elif target != null:
		global_position = target.global_position

	var initial_z: float = calculate_target_zoom() if (auto_framing and board != null) else default_zoom
	zoom = Vector2(initial_z, initial_z)

func _process(delta: float) -> void:
	_update_target_tracking(delta)
	_update_zoom_framing(delta)
	_update_shake(delta)

func get_desired_target_position() -> Vector2:
	if anchor_node != null and target != null:
		if is_zero_approx(follow_bias):
			return anchor_node.global_position
		return anchor_node.global_position.lerp(target.global_position, follow_bias)
	if target != null:
		return target.global_position
	if anchor_node != null:
		return anchor_node.global_position
	return global_position

func _update_target_tracking(delta: float) -> void:
	var desired: Vector2 = get_desired_target_position()
	var factor: float = 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(desired, factor)

## Computes ideal camera zoom so that the entire chessboard (ranks, files, borders, shadows)
## remains fully visible within safe viewport margins
func calculate_target_zoom() -> float:
	if board == null:
		return default_zoom

	var vp_size: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2(1280.0, 800.0)
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		vp_size = Vector2(1280.0, 800.0)

	var eff_rad: float = maxf(board.animated_radius, float(board.target_radius))
	var local_rect: Rect2 = board.get_visual_rect(eff_rad)

	var top_left_global: Vector2 = board.to_global(local_rect.position) if board.is_inside_tree() else (board.global_position + local_rect.position)
	var bottom_right_global: Vector2 = board.to_global(local_rect.end) if board.is_inside_tree() else (board.global_position + local_rect.end)

	var cam_pos: Vector2 = global_position
	var dist_top: float = absf(cam_pos.y - top_left_global.y)
	var dist_bottom: float = absf(bottom_right_global.y - cam_pos.y)
	var dist_left: float = absf(cam_pos.x - top_left_global.x)
	var dist_right: float = absf(bottom_right_global.x - cam_pos.x)

	var max_dist_y: float = maxf(dist_top, dist_bottom)
	var max_dist_x: float = maxf(dist_left, dist_right)

	var safe_half_h: float = maxf(vp_size.y * 0.5 - margin_vertical, 100.0)
	var safe_half_w: float = maxf(vp_size.x * 0.5 - margin_horizontal, 100.0)

	var zoom_y: float = safe_half_h / maxf(max_dist_y, 1.0)
	var zoom_x: float = safe_half_w / maxf(max_dist_x, 1.0)

	var calculated_zoom: float = minf(zoom_x, zoom_y)
	return clampf(calculated_zoom, min_zoom, max_zoom)

func _update_zoom_framing(delta: float) -> void:
	if not auto_framing or board == null:
		return

	var target_zoom_val: float = calculate_target_zoom()
	var blend: float = 1.0 - exp(-zoom_speed * delta)
	var current_z: float = lerpf(zoom.x, target_zoom_val, blend)
	zoom = Vector2(current_z, current_z)

func _update_shake(delta: float) -> void:
	if not enable_shake:
		offset = Vector2.ZERO
		rotation = 0.0
		return

	if trauma > 0.0:
		trauma = maxf(trauma - shake_decay * delta, 0.0)
		var intensity: float = trauma * trauma
		noise_time += delta * 24.0

		var nx: float = noise.get_noise_2d(15.0, noise_time)
		var ny: float = noise.get_noise_2d(45.0, noise_time)
		var nr: float = noise.get_noise_2d(75.0, noise_time)

		offset = Vector2(max_offset.x * intensity * nx, max_offset.y * intensity * ny) + directional_kick
		rotation = max_roll * intensity * nr
	else:
		offset = directional_kick
		rotation = 0.0

	if directional_kick != Vector2.ZERO:
		directional_kick = directional_kick.lerp(Vector2.ZERO, delta * 14.0)
		if directional_kick.length_squared() < 0.01:
			directional_kick = Vector2.ZERO

func add_trauma(amount: float) -> void:
	if enable_shake:
		trauma = clampf(trauma + amount, 0.0, 1.0)

func kick(dir: Vector2, strength: float) -> void:
	if enable_shake and dir != Vector2.ZERO:
		directional_kick += dir.normalized() * strength

func shake_on_hop(dir: Vector2) -> void:
	kick(dir, 1.0)
	add_trauma(hop_trauma)

func shake_on_landing() -> void:
	add_trauma(landing_trauma)

func shake_on_bump(dir: Vector2) -> void:
	kick(-dir, bump_kick_strength)
	add_trauma(bump_trauma)
