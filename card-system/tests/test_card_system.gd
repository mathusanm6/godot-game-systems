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
	success = _test_card_hand_reordering() and success
	success = _test_custom_unslotting_placement() and success
	success = _test_hand_card_limit_8() and success
	success = _test_discard_pile_contracts() and success
	success = _test_discard_via_drag_and_drop() and success

	if success:
		print("✅ ALL TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		push_error("❌ ONE OR MORE TESTS FAILED!")
		quit(1)


func _test_card_data_resources() -> bool:
	print("[Test] Validating Classic CardData Resources...")

	var spades_a: CardData = load("res://resources/cards/spades_A.tres") as CardData
	if not spades_a:
		push_error("Failed to load spades_A.tres as CardData")
		return false
	if (
		spades_a.title != "Ace of Spades" or spades_a.suit != CardData.Suit.SPADES
		or spades_a.rank != CardData.Rank.ACE or spades_a.value != 11
		or not spades_a.artwork
	):
		push_error("Spades A CardData properties mismatch: %s" % spades_a)
		return false

	var hearts_k: CardData = load("res://resources/cards/hearts_K.tres") as CardData
	if not hearts_k:
		push_error("Failed to load hearts_K.tres as CardData")
		return false
	if (
		hearts_k.title != "King of Hearts" or hearts_k.suit != CardData.Suit.HEARTS
		or hearts_k.rank != CardData.Rank.KING or hearts_k.value != 10
		or not hearts_k.artwork
	):
		push_error("Hearts K CardData properties mismatch: %s" % hearts_k)
		return false

	var diamonds_q: CardData = load("res://resources/cards/diamonds_Q.tres") as CardData
	if not diamonds_q:
		push_error("Failed to load diamonds_Q.tres as CardData")
		return false
	if (
		diamonds_q.title != "Queen of Diamonds" or diamonds_q.suit != CardData.Suit.DIAMONDS
		or diamonds_q.rank != CardData.Rank.QUEEN or diamonds_q.value != 10
		or not diamonds_q.artwork
	):
		push_error("Diamonds Q CardData properties mismatch: %s" % diamonds_q)
		return false

	var clubs_j: CardData = load("res://resources/cards/clubs_J.tres") as CardData
	if not clubs_j:
		push_error("Failed to load clubs_J.tres as CardData")
		return false
	if (
		clubs_j.title != "Jack of Clubs" or clubs_j.suit != CardData.Suit.CLUBS
		or clubs_j.rank != CardData.Rank.JACK or clubs_j.value != 10
		or not clubs_j.artwork
	):
		push_error("Clubs J CardData properties mismatch: %s" % clubs_j)
		return false

	var joker_red: CardData = load("res://resources/cards/joker_red.tres") as CardData
	if not joker_red:
		push_error("Failed to load joker_red.tres as CardData")
		return false
	if joker_red.rank != CardData.Rank.JOKER or not joker_red.artwork:
		push_error("Red Joker CardData properties mismatch: %s" % joker_red)
		return false

	print("  -> Classic CardData resources validated.")
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
	var spades_a: CardData = load("res://resources/cards/spades_A.tres") as CardData
	var hearts_k: CardData = load("res://resources/cards/hearts_K.tres") as CardData

	var cards_list: Array[CardData] = [spades_a, hearts_k]
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
	if drawn_signals.is_empty() or drawn_signals[0].data != hearts_k:
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
	deck.add_card_to_deck(spades_a)
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


func _test_card_hand_reordering() -> bool:
	print("[Test] Validating CardHand reordering, move_card, and insertion index math...")

	var hand := CardHand.new()
	hand.hand_center = Vector2(640, 640)
	hand.max_card_spacing = 140.0
	hand.max_hand_width = 720.0

	var card_scene: PackedScene = load("res://features/card/Card.tscn")
	var c1: Card = card_scene.instantiate() as Card
	var c2: Card = card_scene.instantiate() as Card
	var c3: Card = card_scene.instantiate() as Card

	hand.add_card(c1, -1, false)
	hand.add_card(c2, -1, false)
	hand.add_card(c3, -1, false)

	# Initial order: [c1, c2, c3]
	if hand.get_card_index(c1) != 0 or hand.get_card_index(c2) != 1 or hand.get_card_index(c3) != 2:
		push_error("Initial card order in hand is incorrect")
		hand.free()
		return false

	# 1. Test insertion index math for 3 cards
	# Slot centers: 500, 640, 780. Midpoint thresholds: 570, 710.
	var idx_left: int = hand.get_insertion_index_for_position(Vector2(450, 640), c1)
	var idx_mid: int = hand.get_insertion_index_for_position(Vector2(640, 640), c1)
	var idx_right: int = hand.get_insertion_index_for_position(Vector2(850, 640), c1)

	if idx_left != 0 or idx_mid != 1 or idx_right != 2:
		push_error("get_insertion_index_for_position returned unexpected indices: %d, %d, %d" % [idx_left, idx_mid, idx_right])
		hand.free()
		return false

	# 2. Test move_card: move c1 (at 0) to index 2
	var moved: bool = hand.move_card(c1, 2, false)
	if not moved or hand.get_card_index(c1) != 2 or hand.get_card_index(c2) != 0 or hand.get_card_index(c3) != 1:
		push_error("move_card failed to move c1 from index 0 to 2")
		hand.free()
		return false

	# 3. Test moving back to 0
	hand.move_card(c1, 0, false)
	if hand.get_card_index(c1) != 0 or hand.get_card_index(c2) != 1 or hand.get_card_index(c3) != 2:
		push_error("move_card failed to restore c1 to index 0")
		hand.free()
		return false

	# 4. Test add_card delegation to move_card when card already exists in hand
	hand.add_card(c3, 0, false)
	if hand.get_card_index(c3) != 0 or hand.get_card_index(c1) != 1 or hand.get_card_index(c2) != 2:
		push_error("add_card failed to reorder existing card c3 to index 0")
		hand.free()
		return false

	c1.free()
	c2.free()
	c3.free()
	hand.free()
	print("  -> CardHand reordering, move_card, and insertion index math validated.")
	return true


func _test_custom_unslotting_placement() -> bool:
	print("[Test] Validating custom unslotting placement and dynamic hand reordering...")

	var manager := CardManager.new()
	var hand := CardHand.new()
	var slot := CardSlot.new()

	manager.card_hand = hand
	manager.add_child(hand)
	manager.add_child(slot)

	var card_scene: PackedScene = load("res://features/card/Card.tscn")
	var c1: Card = card_scene.instantiate() as Card
	var c2: Card = card_scene.instantiate() as Card
	var c3: Card = card_scene.instantiate() as Card

	manager.register_card_slot(slot)
	manager.register_card(c1)
	manager.register_card(c2)
	manager.register_card(c3)

	# Hand starts with c1 and c2
	hand.add_card(c1, -1, false)
	hand.add_card(c2, -1, false)

	# Slot starts with c3
	manager._dock_card_in_slot(c3, slot)

	if hand.get_card_count() != 2 or slot.card_in_slot != c3:
		push_error("Setup failed: hand should have 2 cards, slot should have c3")
		manager.free()
		return false

	# 1. Unslot c3 and place at leftmost position (index 0)
	manager.card_being_dragged = c3
	manager._drag_source_slot = slot
	c3.start_drag()
	# Place at X = 400 (far left, before c1)
	c3.global_position = Vector2(400, 640)
	manager._handle_card_drop(c3)

	if c3.card_slot != null or slot.card_in_slot != null:
		push_error("c3 must be unslotted from slot")
		manager.free()
		return false

	if hand.get_card_count() != 3:
		push_error("Hand must contain 3 cards after unslotting, had %d" % hand.get_card_count())
		manager.free()
		return false

	if hand.get_card_index(c3) != 0:
		push_error("c3 was expected at index 0 after leftmost drop, was at %d" % hand.get_card_index(c3))
		manager.free()
		return false

	# 2. Dock c1 into slot, leaving hand with [c3, c2]
	manager._dock_card_in_slot(c1, slot)
	if hand.get_card_count() != 2 or slot.card_in_slot != c1:
		push_error("Docking c1 into slot failed")
		manager.free()
		return false

	# 3. Unslot c1 and place at rightmost position (index 2)
	manager.card_being_dragged = c1
	manager._drag_source_slot = slot
	c1.start_drag()
	c1.global_position = Vector2(900, 640)
	manager._handle_card_drop(c1)

	if hand.get_card_count() != 3:
		push_error("Hand must contain 3 cards after second unslotting")
		manager.free()
		return false

	if hand.get_card_index(c1) != 2:
		push_error("c1 was expected at index 2 after rightmost drop, was at %d" % hand.get_card_index(c1))
		manager.free()
		return false

	# 4. Drag card within hand: drag c1 from index 2 to index 0
	manager.card_being_dragged = c1
	manager._drag_source_slot = null
	c1.start_drag()
	c1.global_position = Vector2(400, 640)
	manager._process_card_drag_motion()

	if hand.get_card_index(c1) != 0:
		push_error("Live drag motion failed to reorder c1 to index 0")
		manager.free()
		return false

	manager._handle_card_drop(c1)
	if hand.get_card_index(c1) != 0:
		push_error("c1 should remain at index 0 after drop")
		manager.free()
		return false

	manager.free()
	print("  -> Custom unslotting placement and dynamic hand reordering validated.")
	return true


func _test_hand_card_limit_8() -> bool:
	print("[Test] Validating Hand capacity limit of 8 cards and draw rejection...")

	var hand := CardHand.new()
	hand.hand_center = Vector2(640, 640)
	hand.max_cards = 8

	var card_scene: PackedScene = load("res://features/card/Card.tscn")
	var cards_list: Array[Card] = []

	for i in range(8):
		var c: Card = card_scene.instantiate() as Card
		cards_list.append(c)
		var added: bool = hand.add_card(c, -1, false)
		if not added:
			push_error("Failed to add card %d to hand" % i)
			hand.free()
			return false

	if hand.get_card_count() != 8:
		push_error("Hand should contain exactly 8 cards, had %d" % hand.get_card_count())
		hand.free()
		return false

	if not hand.is_full or hand.can_add_card():
		push_error("Hand should report is_full = true and can_add_card = false at 8 cards")
		hand.free()
		return false

	# 1. Attempt to add 9th card: must be rejected
	var c9: Card = card_scene.instantiate() as Card
	var full_emitted := [false]
	hand.hand_full.connect(func(_c: Card) -> void: full_emitted[0] = true)

	var added_9: bool = hand.add_card(c9, -1, false)
	if added_9 or hand.get_card_count() != 8:
		push_error("9th card should have been rejected by add_card()")
		c9.free()
		hand.free()
		return false

	if not full_emitted[0]:
		push_error("hand_full signal should have been emitted when attempting 9th card")
		c9.free()
		hand.free()
		return false

	c9.free()

	# 2. Moving / reordering existing cards in full hand MUST still work
	var reordered: bool = hand.move_card(cards_list[0], 7, false)
	if not reordered or hand.get_card_index(cards_list[0]) != 7 or hand.get_card_count() != 8:
		push_error("Reordering cards in full hand must be permitted")
		hand.free()
		return false

	# 3. Test Deck.draw_card() when hand is full: must return null and not pop from draw pile
	var deck_script: Script = load("res://features/deck/deck.gd")
	var deck: Node = deck_script.new()
	var spades_a: CardData = load("res://resources/cards/spades_A.tres") as CardData
	var test_deck_cards: Array[CardData] = [spades_a]
	deck.initial_cards = test_deck_cards
	deck.draw_pile = test_deck_cards.duplicate()
	deck.card_hand = hand

	var drawn_card: Card = deck.draw_card()
	if drawn_card != null:
		push_error("deck.draw_card() must return null when hand is full (8 limit)")
		drawn_card.free()
		deck.free()
		hand.free()
		return false

	if deck.remaining_count != 1:
		push_error("deck.draw_pile must not be decremented when draw is rejected at hand limit")
		deck.free()
		hand.free()
		return false

	# Clean up
	deck.free()
	for c in cards_list:
		c.free()
	hand.free()
	print("  -> Hand capacity limit of 8 cards and draw rejection validated.")
	return true


func _test_discard_pile_contracts() -> bool:
	print("[Test] Validating DiscardPile contracts, discarding, and recycling into deck...")

	var discard_script: Script = load("res://features/discard_pile/discard_pile.gd")
	var discard_pile: Node = discard_script.new()

	if not discard_pile.is_empty or discard_pile.remaining_count != 0:
		push_error("New DiscardPile must be empty with remaining_count = 0")
		discard_pile.free()
		return false

	var card_scene: PackedScene = load("res://features/card/Card.tscn")
	var c1: Card = card_scene.instantiate() as Card
	var spades_a: CardData = load("res://resources/cards/spades_A.tres") as CardData
	c1.card_data = spades_a

	var discard_emitted := [false]
	discard_pile.card_discarded.connect(func(_d: CardData, _c: Card) -> void: discard_emitted[0] = true)

	# 1. Discard card
	discard_pile.discard_card(c1, false)

	if discard_pile.is_empty or discard_pile.remaining_count != 1:
		push_error("Discard pile must have 1 card after discard")
		discard_pile.free()
		return false

	if not discard_emitted[0]:
		push_error("card_discarded signal must be emitted")
		discard_pile.free()
		return false

	if discard_pile.discard_pile[0] != spades_a:
		push_error("Discard pile does not contain correct CardData")
		discard_pile.free()
		return false

	# 2. Recycle into Deck
	var deck_script: Script = load("res://features/deck/deck.gd")
	var deck: Node = deck_script.new()
	var empty_pile: Array[CardData] = []
	deck.draw_pile = empty_pile

	var recycled: int = discard_pile.recycle_into_deck(deck, true)
	if recycled != 1 or not discard_pile.is_empty or deck.remaining_count != 1:
		push_error("Recycling discard pile into deck failed")
		deck.free()
		discard_pile.free()
		return false

	if deck.draw_pile[0] != spades_a:
		push_error("Deck did not receive recycled card data")
		deck.free()
		discard_pile.free()
		return false

	deck.free()
	discard_pile.free()
	print("  -> DiscardPile contracts, discarding, and recycling validated.")
	return true


func _test_discard_via_drag_and_drop() -> bool:
	print("[Test] Validating card discard via drag & drop in CardManager...")

	var manager := CardManager.new()
	var hand := CardHand.new()
	var discard_script: Script = load("res://features/discard_pile/discard_pile.gd")
	var discard_pile: Node = discard_script.new()

	manager.card_hand = hand
	manager.discard_pile = discard_pile
	manager.add_child(hand)
	manager.add_child(discard_pile)

	manager.register_discard_pile(discard_pile)

	var card_scene: PackedScene = load("res://features/card/Card.tscn")
	var c1: Card = card_scene.instantiate() as Card
	var hearts_k: CardData = load("res://resources/cards/hearts_K.tres") as CardData
	c1.card_data = hearts_k

	manager.register_card(c1)
	hand.add_card(c1, -1, false)

	if hand.get_card_count() != 1:
		push_error("Hand must start with 1 card")
		manager.free()
		return false

	# Simulate dragging c1 over discard pile and dropping
	manager.card_being_dragged = c1
	c1.start_drag()
	manager._overlapping_discard_piles.append(discard_pile)

	manager._handle_card_drop(c1)

	if hand.get_card_count() != 0 or hand.has_card(c1):
		push_error("Discarded card must be removed from hand")
		manager.free()
		return false

	if discard_pile.remaining_count != 1 or discard_pile.discard_pile[0] != hearts_k:
		push_error("Card was not properly added to discard pile on drop")
		manager.free()
		return false

	manager.free()
	print("  -> Card discard via drag & drop validated.")
	return true
