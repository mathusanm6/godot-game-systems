class_name MainScene
extends Node2D

## MainScene Orchestrator for Chess Movement System
## Clean top-level controller wiring ChessBoard, King, Camera2D, and GameUI.
## Follows Call Down, Signal Up architecture.

@onready var camera: CameraController = %Camera2D if has_node("%Camera2D") else null
@onready var chess_board: ChessBoard = %ChessBoard if has_node("%ChessBoard") else null
@onready var king: King = %King if has_node("%King") else null
@onready var game_ui: GameUI = %GameUI if has_node("%GameUI") else null

func _ready() -> void:
	_setup_system()

func _setup_system() -> void:
	# 1. Setup Board and King
	if king != null and chess_board != null:
		king.setup(chess_board)

	# 2. Camera Setup
	if camera != null:
		camera.board = chess_board
		camera.anchor_node = chess_board
		camera.target = king

	# 3. Wire King Events to Camera Juice and UI
	if king != null:
		if camera != null:
			king.hop_started.connect(func(_from: Vector2i, _to: Vector2i, dir: Vector2i) -> void:
				camera.shake_on_hop(Vector2(dir))
			)
			king.hop_landed.connect(func(_tile: Vector2i, _dir: Vector2i) -> void:
				camera.shake_on_landing()
			)
			king.bump_occurred.connect(func(_from: Vector2i, _blocked: Vector2i, dir: Vector2i) -> void:
				camera.shake_on_bump(Vector2(dir))
			)

		if game_ui != null:
			king.tile_changed.connect(func(tile: Vector2i, notation: String) -> void:
				game_ui.update_tile_info(tile, notation, king.step_count)
			)

	# 4. Wire UI Actions
	if game_ui != null and king != null:
		game_ui.reset_requested.connect(_on_ui_reset_requested)

	# Initial UI telemetry sync
	_sync_ui()

func _sync_ui() -> void:
	if game_ui != null and king != null:
		game_ui.update_tile_info(king.tile_pos, king.get_chess_notation(), king.step_count)

func _on_ui_reset_requested() -> void:
	if king != null:
		king.reset_to_start()
		if chess_board != null:
			chess_board.update_size_for_king(king.tile_pos)
		_sync_ui()
