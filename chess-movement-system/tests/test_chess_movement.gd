extends SceneTree

## Automated Verification Suite for Chess Movement System
## Rigorously validates ChessBoard dynamic resizing, coordinate conversions,
## King 8-way movement, mouse direction targeting, boundary bumping, and F6 scene isolation.

func _init() -> void:
	print("====================================================")
	print("--- Running Chess Movement System Verification ---")
	print("====================================================")

	var success: bool = true

	success = _test_board_math_and_coordinates() and success
	success = _test_algebraic_notation() and success
	success = _test_dynamic_board_resizing() and success
	success = _test_king_8way_input_mapping() and success
	success = _test_king_mouse_targeting() and success
	success = _test_king_movement_and_bumping() and success
	success = _test_king_reset_and_teleport() and success
	success = _test_camera_trauma() and success
	success = _test_ui_contracts() and success
	success = _test_f6_scene_isolation() and success

	if success:
		print("====================================================")
		print("✅ ALL CHESS MOVEMENT SYSTEM TESTS PASSED!")
		print("====================================================")
		quit(0)
	else:
		push_error("❌ ONE OR MORE TESTS FAILED!")
		quit(1)

func _test_board_math_and_coordinates() -> bool:
	print("[Test 1] Validating ChessBoard coordinate math & bounds...")

	var board := ChessBoard.new()
	board.min_radius = 3
	board.max_radius = 8
	board.radius = 3
	board.tile_size = 72.0

	# 1. Centered origin check: Tile (0, 0) MUST map to local Vector2.ZERO
	var local_zero: Vector2 = board.tile_to_local(Vector2i(0, 0))
	if local_zero != Vector2.ZERO:
		push_error("Tile (0,0) must map to Vector2.ZERO: got %s" % local_zero)
		board.free()
		return false

	# 2. Round-Trip Coordinate check
	var test_tiles: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(3, 3),
		Vector2i(-3, -3),
		Vector2i(2, -1),
		Vector2i(-2, 3),
		Vector2i(0, -3)
	]

	for tile: Vector2i in test_tiles:
		var local_pos: Vector2 = board.tile_to_local(tile)
		var back_tile: Vector2i = board.local_to_tile(local_pos)
		if back_tile != tile:
			push_error("Round-trip failed for tile %s: got %s" % [tile, back_tile])
			board.free()
			return false

	# 3. Active tile bounds at radius 3
	if not board.is_valid_tile(Vector2i(0, 0)) or not board.is_valid_tile(Vector2i(3, 3)):
		push_error("Tile (0,0) and (3,3) must be valid at radius 3")
		board.free()
		return false

	if board.is_valid_tile(Vector2i(4, 0)) or board.is_valid_tile(Vector2i(0, 4)):
		push_error("Tile (4,0) should not be within active radius 3 perimeter")
		board.free()
		return false

	# 4. Expansion bounds check
	if not board.can_step_to_tile(Vector2i(4, 0)) or not board.can_step_to_tile(Vector2i(8, 8)):
		push_error("can_step_to_tile should permit tiles up to max_radius 8")
		board.free()
		return false

	if board.can_step_to_tile(Vector2i(9, 0)) or board.can_step_to_tile(Vector2i(0, 9)):
		push_error("can_step_to_tile should reject tiles beyond max_radius 8")
		board.free()
		return false

	# 5. Alternating tile colors
	var is_dark_00: bool = board.is_tile_dark(Vector2i(0, 0))
	var is_dark_10: bool = board.is_tile_dark(Vector2i(1, 0))
	if is_dark_00 == is_dark_10:
		push_error("Adjacent tiles must alternate light and dark")
		board.free()
		return false

	board.free()
	print("  -> ChessBoard math and bounds validated.")
	return true

func _test_algebraic_notation() -> bool:
	print("[Test 2] Validating Algebraic Chess Notation...")

	var board := ChessBoard.new()
	board.radius = 3 # 7x7 board (-3..+3)
	board.animated_radius = 3.0

	# At radius 3:
	# Columns (-3..3) map to A..G: x=-3 -> A, x=0 -> D, x=3 -> G
	# Rows (-3..3) map to 7..1: y=-3 -> 7, y=0 -> 4, y=3 -> 1
	var center_not: String = board.get_chess_notation(Vector2i(0, 0))
	if center_not != "D4":
		push_error("Center tile (0,0) at radius 3 should be D4, got '%s'" % center_not)
		board.free()
		return false

	var top_left: String = board.get_chess_notation(Vector2i(-3, -3))
	if top_left != "A7":
		push_error("Top-left (-3,-3) at radius 3 should be A7, got '%s'" % top_left)
		board.free()
		return false

	var bottom_right: String = board.get_chess_notation(Vector2i(3, 3))
	if bottom_right != "G1":
		push_error("Bottom-right (3,3) at radius 3 should be G1, got '%s'" % bottom_right)
		board.free()
		return false

	board.free()
	print("  -> Algebraic Chess Notation validated.")
	return true

func _test_dynamic_board_resizing() -> bool:
	print("[Test 3] Validating Dynamic Board Resizing...")

	var board := ChessBoard.new()
	board.min_radius = 3
	board.max_radius = 8
	board.radius = 3
	board.buffer_tiles = 1

	var resize_events: Array[Dictionary] = []
	board.board_resized.connect(func(new_rad: int, is_exp: bool) -> void:
		resize_events.append({"radius": new_rad, "expanding": is_exp})
	)

	# 1. King approaching perimeter: King steps to (3, 0)
	# Distance = 3. With buffer 1, required radius = 3 + 1 = 4.
	var req_rad: int = board.calculate_desired_radius(Vector2i(3, 0))
	if req_rad != 4:
		push_error("Desired radius for King at (3,0) should be 4, got %d" % req_rad)
		board.free()
		return false

	board.update_size_for_king(Vector2i(3, 0))
	if board.target_radius != 4 or resize_events.is_empty() or resize_events[0]["radius"] != 4 or not resize_events[0]["expanding"]:
		push_error("Board failed to expand to radius 4 on King approach")
		board.free()
		return false

	# 2. King moving further outward: King steps to (5, 0) -> expands to 6
	board.update_size_for_king(Vector2i(5, 0))
	if board.target_radius != 6 or resize_events.back()["radius"] != 6:
		push_error("Board failed to expand to radius 6 for King at (5,0)")
		board.free()
		return false

	# 3. Clamping at max_radius 8
	var max_req: int = board.calculate_desired_radius(Vector2i(8, 0))
	if max_req != 8:
		push_error("Board should clamp expansion at max_radius 8, got %d" % max_req)
		board.free()
		return false

	board.free()
	print("  -> Dynamic Board Resizing validated.")
	return true

func _test_king_8way_input_mapping() -> bool:
	print("[Test 4] Validating King 8-way input mapping...")

	var king := King.new()

	# Cardinal mappings
	if king._match_key_direction(KEY_W) != Vector2i(0, -1) or king._match_key_direction(KEY_UP) != Vector2i(0, -1):
		push_error("UP key mapping failed")
		king.free()
		return false
	if king._match_key_direction(KEY_S) != Vector2i(0, 1) or king._match_key_direction(KEY_DOWN) != Vector2i(0, 1):
		push_error("DOWN key mapping failed")
		king.free()
		return false
	if king._match_key_direction(KEY_A) != Vector2i(-1, 0) or king._match_key_direction(KEY_LEFT) != Vector2i(-1, 0):
		push_error("LEFT key mapping failed")
		king.free()
		return false
	if king._match_key_direction(KEY_D) != Vector2i(1, 0) or king._match_key_direction(KEY_RIGHT) != Vector2i(1, 0):
		push_error("RIGHT key mapping failed")
		king.free()
		return false

	# Diagonal mappings
	if king._match_key_direction(KEY_Q) != Vector2i(-1, -1) or king._match_key_direction(KEY_KP_7) != Vector2i(-1, -1):
		push_error("UP-LEFT diagonal mapping failed")
		king.free()
		return false
	if king._match_key_direction(KEY_E) != Vector2i(1, -1) or king._match_key_direction(KEY_KP_9) != Vector2i(1, -1):
		push_error("UP-RIGHT diagonal mapping failed")
		king.free()
		return false
	if king._match_key_direction(KEY_Z) != Vector2i(-1, 1) or king._match_key_direction(KEY_KP_1) != Vector2i(-1, 1):
		push_error("DOWN-LEFT diagonal mapping failed")
		king.free()
		return false
	if king._match_key_direction(KEY_C) != Vector2i(1, 1) or king._match_key_direction(KEY_KP_3) != Vector2i(1, 1):
		push_error("DOWN-RIGHT diagonal mapping failed")
		king.free()
		return false

	king.free()
	print("  -> King 8-way input mapping validated.")
	return true

func _test_king_mouse_targeting() -> bool:
	print("[Test 5] Validating Mouse targeting & step calculation...")

	var king := King.new()
	king.tile_pos = Vector2i(0, 0)

	# Click adjacent tiles
	var dir_right: Vector2i = king._get_direction_toward_tile(Vector2i(1, 0))
	var dir_up_left: Vector2i = king._get_direction_toward_tile(Vector2i(-1, -1))
	var dir_down: Vector2i = king._get_direction_toward_tile(Vector2i(0, 1))

	if dir_right != Vector2i(1, 0) or dir_up_left != Vector2i(-1, -1) or dir_down != Vector2i(0, 1):
		push_error("Mouse adjacent direction calculation failed")
		king.free()
		return false

	# Click distant tile (e.g. at (5, -3)) should clamp to 1 step in that direction: (1, -1)
	var dir_distant: Vector2i = king._get_direction_toward_tile(Vector2i(5, -3))
	if dir_distant != Vector2i(1, -1):
		push_error("Distant mouse click must clamp to step direction (1, -1), got %s" % dir_distant)
		king.free()
		return false

	king.free()
	print("  -> Mouse targeting validated.")
	return true

func _test_king_movement_and_bumping() -> bool:
	print("[Test 6] Validating King movement & boundary bumping...")

	var board := ChessBoard.new()
	board.min_radius = 3
	board.max_radius = 8
	board.radius = 3

	var king := King.new()
	king.start_tile = Vector2i(0, 0)
	king.setup(board)

	var bump_data: Dictionary = {"bumped": false, "dir": Vector2i.ZERO}
	king.bump_occurred.connect(func(_from: Vector2i, _blocked: Vector2i, dir: Vector2i) -> void:
		bump_data["bumped"] = true
		bump_data["dir"] = dir
	)

	# 1. Step to (1, 0) within bounds: must succeed and expand if needed
	var step_success: bool = king.try_step(Vector2i(1, 0))
	if not step_success or king.tile_pos != Vector2i(1, 0):
		push_error("Valid step failed: tile_pos=%s" % king.tile_pos)
		king.free()
		board.free()
		return false

	# 2. Stepping beyond max_radius (e.g. from (8, 0) stepping (1, 0) to (9, 0)): must fail and bump
	king.tile_pos = Vector2i(8, 0)
	king.is_moving = false
	var step_blocked: bool = king.try_step(Vector2i(1, 0))
	if step_blocked or not bump_data["bumped"] or bump_data["dir"] != Vector2i(1, 0):
		push_error("Stepping beyond max_radius 8 must trigger wall bump recoil")
		king.free()
		board.free()
		return false

	king.free()
	board.free()
	print("  -> King movement and boundary bumping validated.")
	return true

func _test_king_reset_and_teleport() -> bool:
	print("[Test 7] Validating King teleport & reset...")

	var board := ChessBoard.new()
	var king := King.new()
	king.start_tile = Vector2i(0, 0)
	king.setup(board)

	king.teleport_to_tile(Vector2i(2, -1))
	if king.tile_pos != Vector2i(2, -1):
		push_error("Teleport failed: tile=%s" % king.tile_pos)
		king.free()
		board.free()
		return false

	king.reset_to_start()
	if king.tile_pos != Vector2i(0, 0) or king.step_count != 0:
		push_error("Reset to start failed: tile=%s" % king.tile_pos)
		king.free()
		board.free()
		return false

	king.free()
	board.free()
	print("  -> King teleport & reset validated.")
	return true

func _test_camera_trauma() -> bool:
	print("[Test 8] Validating CameraController trauma, framing & dynamic zoom...")

	var cam := CameraController.new()
	cam.enable_shake = true

	# 1. Trauma & Shake test
	cam.add_trauma(0.5)
	if cam.trauma < 0.49:
		push_error("Trauma addition failed: got %f" % cam.trauma)
		cam.free()
		return false

	cam.shake_on_hop(Vector2.RIGHT)
	if cam.trauma <= 0.5:
		push_error("Hop shake did not increase trauma")
		cam.free()
		return false

	# 2. Dynamic Framing & Zoom test with ChessBoard
	var board := ChessBoard.new()
	board.min_radius = 3
	board.max_radius = 8
	board.radius = 3
	board.animated_radius = 3.0
	board.global_position = Vector2(640, 400)
	cam.board = board
	cam.anchor_node = board
	cam.global_position = Vector2(640, 400)

	# At radius 3: zoom must be 1.0 (crisp 1:1 view)
	var zoom_r3: float = cam.calculate_target_zoom()
	if not is_equal_approx(zoom_r3, 1.0):
		push_error("Camera zoom at radius 3 should be 1.0, got %f" % zoom_r3)
		board.free()
		cam.free()
		return false

	var rect_r3: Rect2 = board.get_visual_rect()
	var screen_top_r3: float = cam.global_position.y - absf(rect_r3.position.y) * zoom_r3
	var screen_bottom_r3: float = cam.global_position.y + rect_r3.end.y * zoom_r3
	if screen_top_r3 < 40.0 or screen_bottom_r3 > 760.0:
		push_error("Radius 3 board bounds out of safe screen framing: top=%f, bottom=%f" % [screen_top_r3, screen_bottom_r3])
		board.free()
		cam.free()
		return false

	# At radius 8: board visual span is 1318px, camera must dynamically zoom out (~0.53)
	board.radius = 8
	board.target_radius = 8
	board.animated_radius = 8.0
	var zoom_r8: float = cam.calculate_target_zoom()
	if zoom_r8 > 0.58 or zoom_r8 < 0.48:
		push_error("Camera zoom at radius 8 should be ~0.53, got %f" % zoom_r8)
		board.free()
		cam.free()
		return false

	var rect_r8: Rect2 = board.get_visual_rect()
	var screen_top_r8: float = cam.global_position.y - absf(rect_r8.position.y) * zoom_r8
	var screen_bottom_r8: float = cam.global_position.y + rect_r8.end.y * zoom_r8
	if screen_top_r8 < 35.0 or screen_bottom_r8 > 765.0:
		push_error("Radius 8 board bounds out of safe screen framing: top=%f, bottom=%f" % [screen_top_r8, screen_bottom_r8])
		board.free()
		cam.free()
		return false

	board.free()
	cam.free()
	print("  -> CameraController trauma, framing & dynamic zoom validated.")
	return true

func _test_ui_contracts() -> bool:
	print("[Test 9] Validating GameUI contracts...")

	var ui := GameUI.new()
	var ui_state: Dictionary = {"reset_fired": false}
	ui.reset_requested.connect(func() -> void:
		ui_state["reset_fired"] = true
	)

	ui.update_tile_info(Vector2i(0, 0), "D4", 5)
	ui._on_reset_pressed()

	if not ui_state["reset_fired"]:
		push_error("GameUI reset_requested did not fire")
		ui.free()
		return false

	ui.free()
	print("  -> GameUI contracts validated.")
	return true

func _test_f6_scene_isolation() -> bool:
	print("[Test 10] Validating F6 Standalone Scene instantiation...")

	var scenes: Array[String] = [
		"res://features/board/chess_board.tscn",
		"res://features/king/king.tscn",
		"res://features/ui/game_ui.tscn",
		"res://main_scene.tscn"
	]

	for path: String in scenes:
		var scene_res: PackedScene = load(path) as PackedScene
		if scene_res == null:
			push_error("Failed to load PackedScene at %s" % path)
			return false

		var instance: Node = scene_res.instantiate()
		if instance == null:
			push_error("Failed to instantiate scene at %s" % path)
			return false

		instance.free()
		print("  -> %s verified standalone." % path.get_file())

	print("  -> All 4 scenes passed F6 instantiation without errors.")
	return true
