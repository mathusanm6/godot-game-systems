extends SceneTree


func _init() -> void:
	print("--- Running Card System Automated Verification Tests ---")
	var success := true

	success = _test_card_data_resources() and success
	success = _test_card_slot_contracts() and success
	success = _test_card_state_machine() and success
	success = _test_card_hand_curve_math() and success
	success = _test_card_hand_lifecycle() and success
	success = _test_card_deck() and success
	success = _test_card_unslotting_and_hand_return() and success

	if success:
		print("✅ ALL TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		push_error("❌ ONE OR MORE TESTS FAILED!")
		quit(1)


func _test_card_data_resources() -> bool:
	print("[Test] Validating CardData Resources...")

	var strike: CardData = load("res://resources/cards/strike.tres") as CardData
	if not strike:
		push_error("Failed to load strike.tres as CardData")
		return false
	if (
		strike.title != "Strike" or strike.cost != 1 or strike.attack != 6
		or strike.card_type != CardData.CardType.ATTACK
	):
		push_error("Strike CardData properties mismatch: %s" % strike)
		return false

	var defend: CardData = load("res://resources/cards/defend.tres") as CardData
	if not defend:
		push_error("Failed to load defend.tres as CardData")
		return false
	if (
		defend.title != "Defend" or defend.cost != 1 or defend.defense != 5
		or defend.card_type != CardData.CardType.SKILL
	):
		push_error("Defend CardData properties mismatch: %s" % defend)
		return false

	var empower: CardData = load("res://resources/cards/empower.tres") as CardData
	if not empower:
		push_error("Failed to load empower.tres as CardData")
		return false
	if (
		empower.title != "Empower" or empower.cost != 2
		or empower.card_type != CardData.CardType.POWER
	):
		push_error("Empower CardData properties mismatch: %s" % empower)
		return false

	print("  -> CardData resources validated.")
	return true


func _test_card_slot_contracts() -> bool:
	print("[Test] Validating CardSlot component API and contracts...")

	var slot := CardSlot.new()
	var card_scene: PackedScene = load("res://features/card/Card.tscn")
	var card_instance: Card = card_scene.instantiate() as Card

	if slot.is_occupied:
		push_error("New slot should be unoccupied")
		return false

	var slotted_emitted := [false]
	slot.card_slotted.connect(
		func(_c: Card, _s: CardSlot) -> void:
			slotted_emitted[0] = true,
	)

	slot.assign_card(card_instance)
	if not slot.is_occupied or slot.card_in_slot != card_instance:
		push_error("Slot failed to report card assignment")
		return false
	if not slotted_emitted[0]:
		push_error("Slot failed to emit card_slotted signal")
		return false

	var cleared_card: Card = slot.clear_card()
	if slot.is_occupied or cleared_card != card_instance:
		push_error("Slot clear_card() failed")
		return false

	card_instance.free()
	slot.free()
	print("  -> CardSlot component contracts validated.")
	return true


func _test_card_state_machine() -> bool:
	print("[Test] Validating Card lifecycle and state transitions...")

	var card_scene: PackedScene = load("res://features/card/Card.tscn")
	var card: Card = card_scene.instantiate() as Card

	# Initial state should be IDLE
	if card.current_state != Card.State.IDLE:
		push_error("Initial card state must be IDLE, was: %s" % card.current_state)
		return false

	# Test drag start and stop
	card.start_drag()
	if card.current_state != Card.State.DRAGGING or not card.is_dragging:
		push_error("Card state should be DRAGGING after start_drag()")
		return false

	card.stop_drag()
	if card.current_state != Card.State.IDLE:
		push_error("Card state should return to IDLE after stop_drag() without slot")
		return false

	card.free()
	print("  -> Card state machine validated.")
	return true


func _test_card_hand_curve_math() -> bool:
	print("[Test] Validating CardHand curve math and arc distribution...")

	var hand := CardHand.new()
	hand.hand_center = Vector2(640, 640)
	hand.max_card_spacing = 140.0
	hand.max_hand_width = 720.0
	hand.arc_height = 28.0
	hand.card_angle_step_deg = 5.5
	hand.max_angle_spread_deg = 36.0

	# 1 Card: Exactly centered, flat rotation
	var t1: Dictionary = hand.calculate_card_transform(0, 1)
	if t1.position != Vector2(640, 640) or not is_zero_approx(t1.rotation):
		push_error("Single card must be centered at hand_center with zero rotation")
		hand.free()
		return false

	# 3 Cards: Left negative rot/drop, Center apex, Right positive rot/drop
	var t3_0: Dictionary = hand.calculate_card_transform(0, 3)
	var t3_1: Dictionary = hand.calculate_card_transform(1, 3)
	var t3_2: Dictionary = hand.calculate_card_transform(2, 3)

	if not (t3_0.position.x < t3_1.position.x and t3_1.position.x < t3_2.position.x):
		push_error("Horizontal order violated for 3 cards")
		hand.free()
		return false

	if not is_equal_approx(t3_1.position.x, 640.0) or not is_equal_approx(t3_1.position.y, 640.0):
		push_error("Center card must be at arc apex")
		hand.free()
		return false

	# Outer cards should sit lower than center (arc drop)
	if not (t3_0.position.y > t3_1.position.y and t3_2.position.y > t3_1.position.y):
		push_error("Outer cards must exhibit parabolic downward curvature")
		hand.free()
		return false

	# Symmetry test
	if not is_equal_approx(t3_0.position.y, t3_2.position.y):
		push_error("Symmetrical cards must have identical vertical offsets")
		hand.free()
		return false

	if not (t3_0.rotation < 0.0 and is_zero_approx(t3_1.rotation) and t3_2.rotation > 0.0):
		push_error("Rotations must follow natural fan: left negative, center 0, right positive")
		hand.free()
		return false

	if not is_equal_approx(t3_0.rotation, -t3_2.rotation):
		push_error("Left and right cards must have equal and opposite fan angles")
		hand.free()
		return false

	# 10 Cards: Spacing compression within max_hand_width, angle within max_angle_spread
	var t10_first: Dictionary = hand.calculate_card_transform(0, 10)
	var t10_last: Dictionary = hand.calculate_card_transform(9, 10)
	var total_width: float = t10_last.position.x - t10_first.position.x
	if total_width > hand.max_hand_width + 0.01:
		push_error(
			"Hand cards exceeded max_hand_width limit: %f > %f" % [total_width, hand.max_hand_width]
		)
		hand.free()
		return false

	var total_rot_spread: float = rad_to_deg(t10_last.rotation - t10_first.rotation)
	if total_rot_spread > hand.max_angle_spread_deg + 0.01:
		push_error(
			"Hand cards exceeded max_angle_spread_deg: %f > %f"
			% [total_rot_spread, hand.max_angle_spread_deg]
		)
		hand.free()
		return false

	hand.free()
	print("  -> CardHand curve math and arc distribution validated.")
	return true


func _test_card_hand_lifecycle() -> bool:
	print("[Test] Validating CardHand lifecycle, card addition, and removal...")

	var hand := CardHand.new()
	hand.hand_center = Vector2(640, 640)

	var card_scene: PackedScene = load("res://features/card/Card.tscn")
	var c1: Card = card_scene.instantiate() as Card
	var c2: Card = card_scene.instantiate() as Card
	var c3: Card = card_scene.instantiate() as Card

	hand.add_card(c1, -1, false)
	hand.add_card(c2, -1, false)
	hand.add_card(c3, -1, false)

	if hand.get_card_count() != 3:
		push_error("CardHand should contain 3 cards, had %d" % hand.get_card_count())
		return false

	if c1.card_hand != hand or c2.card_hand != hand or c3.card_hand != hand:
		push_error("Cards in hand must reference their owning CardHand")
		return false

	if not (c1.hand_rotation < 0.0 and is_zero_approx(c2.hand_rotation) and c3.hand_rotation > 0.0):
		push_error("Cards in hand did not receive expected fan rotations")
		return false

	# Test removing a card
	var removed := hand.remove_card(c2, false)
	if not removed or hand.get_card_count() != 2 or c2.card_hand != null:
		push_error("Card removal failed")
		return false

	# Remaining 2 cards should be re-fanned
	if not (c1.hand_rotation < 0.0 and c3.hand_rotation > 0.0):
		push_error("Remaining cards should re-fan after removal")
		return false

	c1.free()
	c2.free()
	c3.free()
	hand.free()
	print("  -> CardHand lifecycle, addition, and removal validated.")
	return true


func _test_card_deck() -> bool:
	print("[Test] Validating CardDeck contracts, drawing, and depletion...")

	var deck_script: Script = load("res://features/deck/deck.gd")
	var deck: Node = deck_script.new()
	var strike: CardData = load("res://resources/cards/strike.tres") as CardData
	var defend: CardData = load("res://resources/cards/defend.tres") as CardData

	var cards_list: Array[CardData] = [strike, defend]
	deck.initial_cards = cards_list
	deck.shuffle_on_ready = false

	# Call _ready equivalent logic
	deck.draw_pile = deck.initial_cards.duplicate()

	if deck.remaining_count != 2 or deck.is_empty:
		push_error("Deck must report initial count of 2 and not empty")
		deck.free()
		return false

	var drawn_signals: Array[Dictionary] = []
	deck.card_drawn.connect(
		func(data: CardData, card: Card) -> void:
			drawn_signals.append({ "data": data, "card": card }),
	)

	var depleted_fired := [false]
	deck.deck_depleted.connect(
		func() -> void:
			depleted_fired[0] = true,
	)

	# Draw first card
	var c1: Card = deck.draw_card()
	if not c1 or deck.remaining_count != 1:
		push_error("Drawing first card failed")
		deck.free()
		return false
	if drawn_signals.is_empty() or drawn_signals[0].data != defend:
		push_error("Drawn card signal did not transmit correct card data")
		c1.free()
		deck.free()
		return false

	# Draw second card
	var c2: Card = deck.draw_card()
	if not c2 or deck.remaining_count != 0 or not deck.is_empty:
		push_error("Drawing second card failed or deck not empty")
		c1.free()
		deck.free()
		return false

	# Draw from depleted deck
	var c_empty: Card = deck.draw_card()
	if c_empty != null:
		push_error("Drawing from empty deck must return null")
		c1.free()
		c2.free()
		deck.free()
		return false
	if not depleted_fired[0]:
		push_error("Empty deck draw must emit deck_depleted signal")
		c1.free()
		c2.free()
		deck.free()
		return false

	# Add card back to deck
	deck.add_card_to_deck(strike)
	if deck.remaining_count != 1 or deck.is_empty:
		push_error("Adding card back to deck failed")
		c1.free()
		c2.free()
		deck.free()
		return false

	c1.free()
	c2.free()
	deck.free()
	print("  -> CardDeck contracts and mechanics validated.")
	return true


func _test_card_unslotting_and_hand_return() -> bool:
	print("[Test] Validating Card unslotting, drop resolution, and hand return...")

	var manager := CardManager.new()
	var hand := CardHand.new()
	var slot := CardSlot.new()

	manager.card_hand = hand
	manager.add_child(hand)
	manager.add_child(slot)

	var card_scene: PackedScene = load("res://features/card/Card.tscn")
	var c1: Card = card_scene.instantiate() as Card
	var c2: Card = card_scene.instantiate() as Card

	manager.register_card_slot(slot)
	manager.register_card(c1)
	manager.register_card(c2)

	hand.add_card(c1, -1, false)
	hand.add_card(c2, -1, false)

	if hand.get_card_count() != 2:
		push_error("Hand must start with 2 cards")
		manager.free()
		return false

	# 1. Dock card into slot
	manager._dock_card_in_slot(c1, slot)
	if slot.card_in_slot != c1 or c1.card_slot != slot:
		push_error("c1 was not assigned to slot properly")
		manager.free()
		return false
	if hand.has_card(c1) or hand.get_card_count() != 1:
		push_error("c1 should have been removed from hand upon slotting")
		manager.free()
		return false

	# 2. Simulate dragging card out of slot and dropping outside slots
	manager.card_being_dragged = c1
	c1.start_drag()
	# Drop outside of slots (over_card_slot is null)
	manager._handle_card_drop(c1)

	if c1.card_slot != null or slot.card_in_slot != null:
		push_error("c1 must be unslotted after drop outside slots")
		manager.free()
		return false
	if not hand.has_card(c1) or hand.get_card_count() != 2:
		push_error("c1 must be re-added to hand after unslotting")
		manager.free()
		return false
	if c1.is_hovered or c1.is_dragging:
		push_error("c1 must not remain hovered or dragging after drop")
		manager.free()
		return false

	# 3. Simulate mouse release dropping card
	manager.card_being_dragged = c2
	c2.start_drag()
	var release_event := InputEventMouseButton.new()
	release_event.button_index = MouseButton.MOUSE_BUTTON_LEFT
	release_event.pressed = false
	manager._input(release_event)

	if manager.card_being_dragged != null:
		push_error("Mouse release must drop currently dragged card")
		manager.free()
		return false

	manager.free()
	print("  -> Card unslotting, drop resolution, and hand return validated.")
	return true
