class_name CardManager
extends Node2D

## Optional explicit reference to the CardHand node.
@export var card_hand: CardHand = null

## Optional explicit reference to the DiscardPile node.
@export var discard_pile: DiscardPile = null

## Currently active dragged card, or null if idle.
var card_being_dragged: Card = null

## Currently active hovered card, or null if no card hovered.
var card_being_hovered: Card = null

## Currently hovered card slot (highest z-index / tree order among overlaps).
var over_card_slot: CardSlot:
	get:
		if _overlapping_slots.is_empty():
			return null
		var top_slot: CardSlot = _overlapping_slots[0]
		for slot in _overlapping_slots:
			if (
				slot.z_index > top_slot.z_index
				or (slot.z_index == top_slot.z_index and slot.get_index() > top_slot.get_index())
			):
				top_slot = slot
		return top_slot

## Currently hovered discard pile.
var over_discard_pile: DiscardPile:
	get:
		if _overlapping_discard_piles.is_empty():
			return null
		return _overlapping_discard_piles.back()

# Internal tracking
var _overlapping_slots: Array[CardSlot] = []
var _overlapping_discard_piles: Array[DiscardPile] = []
var _clicked_candidates: Array[Card] = []
var _hovered_candidates: Array[Card] = []
var _last_highlighted_slot: CardSlot = null
var _last_highlighted_discard_pile: DiscardPile = null
var _drag_source_slot: CardSlot = null

var _is_mouse_down: bool = false


func _ready() -> void:
	add_to_group("managers")
	add_to_group("card_managers")
	child_entered_tree.connect(_on_child_entered_tree)
	child_exiting_tree.connect(_on_child_exiting_tree)

	if not card_hand:
		card_hand = get_node_or_null("CardHand") as CardHand
		if not card_hand:
			var hands := get_tree().get_nodes_in_group("card_hands")
			if not hands.is_empty():
				card_hand = hands[0] as CardHand

	# Register all existing cards and slots in scene tree
	for card: Node in get_tree().get_nodes_in_group("cards"):
		if card is Card:
			register_card(card)
			if card_hand and not card.card_slot and not card_hand.has_card(card):
				card_hand.add_card(card, -1, false)

	for card_slot: Node in get_tree().get_nodes_in_group("card_slots"):
		if card_slot is CardSlot:
			register_card_slot(card_slot)

	for pile: Node in get_tree().get_nodes_in_group("discard_piles"):
		if pile is DiscardPile:
			register_discard_pile(pile)

	if card_hand:
		card_hand.reorganize_hand(false)

	update_slot_and_card_order()


func _process(_delta: float) -> void:
	if (
		card_being_dragged and not _is_mouse_down
		and not Input.is_mouse_button_pressed(MouseButton.MOUSE_BUTTON_LEFT)
	):
		_handle_card_drop(card_being_dragged)


func _exit_tree() -> void:
	_clear_slot_highlight()
	_clear_discard_pile_highlight()


func _input(event: InputEvent) -> void:
	# 1. Handle mouse button press / release
	if event is InputEventMouseButton and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		_is_mouse_down = event.is_pressed()
		if not event.is_pressed():
			_clicked_candidates.clear()
			if card_being_dragged:
				_handle_card_drop(card_being_dragged)
				var viewport: Viewport = get_viewport()
				if viewport:
					viewport.set_input_as_handled()

	# 2. Update position during drag or arbitrate hover on motion
	elif event is InputEventMouseMotion:
		if card_being_dragged:
			_process_card_drag_motion()
		else:
			_update_hover_on_motion(event.global_position)


# -----------------------------------------------------------------------------
# Card and Slot Registration
# -----------------------------------------------------------------------------
## Subscribes to events emitted from a card instance.
func register_card(card: Card) -> void:
	if not card.card_clicked.is_connected(_on_card_clicked):
		card.card_clicked.connect(_on_card_clicked)
	if not card.card_hovered.is_connected(_on_card_hovered):
		card.card_hovered.connect(_on_card_hovered)
	if not card.card_unhovered.is_connected(_on_card_unhovered):
		card.card_unhovered.connect(_on_card_unhovered)


## Disconnects events for an unregistering card instance.
func unregister_card(card: Card) -> void:
	if card.card_clicked.is_connected(_on_card_clicked):
		card.card_clicked.disconnect(_on_card_clicked)
	if card.card_hovered.is_connected(_on_card_hovered):
		card.card_hovered.disconnect(_on_card_hovered)
	if card.card_unhovered.is_connected(_on_card_unhovered):
		card.card_unhovered.disconnect(_on_card_unhovered)


## Subscribes to events emitted from a card slot instance.
func register_card_slot(card_slot: CardSlot) -> void:
	if not card_slot.card_slot_entered.is_connected(_on_card_slot_entered):
		card_slot.card_slot_entered.connect(_on_card_slot_entered)
	if not card_slot.card_slot_exited.is_connected(_on_card_slot_exited):
		card_slot.card_slot_exited.connect(_on_card_slot_exited)


## Disconnects events for an unregistering card slot instance.
func unregister_card_slot(card_slot: CardSlot) -> void:
	if card_slot.card_slot_entered.is_connected(_on_card_slot_entered):
		card_slot.card_slot_entered.disconnect(_on_card_slot_entered)
	if card_slot.card_slot_exited.is_connected(_on_card_slot_exited):
		card_slot.card_slot_exited.disconnect(_on_card_slot_exited)


## Subscribes to events emitted from a discard pile instance.
func register_discard_pile(pile: DiscardPile) -> void:
	if not pile.discard_pile_entered.is_connected(_on_discard_pile_entered):
		pile.discard_pile_entered.connect(_on_discard_pile_entered)
	if not pile.discard_pile_exited.is_connected(_on_discard_pile_exited):
		pile.discard_pile_exited.connect(_on_discard_pile_exited)
	if not discard_pile:
		discard_pile = pile


## Disconnects events for an unregistering discard pile instance.
func unregister_discard_pile(pile: DiscardPile) -> void:
	if pile.discard_pile_entered.is_connected(_on_discard_pile_entered):
		pile.discard_pile_entered.disconnect(_on_discard_pile_entered)
	if pile.discard_pile_exited.is_connected(_on_discard_pile_exited):
		pile.discard_pile_exited.disconnect(_on_discard_pile_exited)
	_overlapping_discard_piles.erase(pile)
	if _last_highlighted_discard_pile == pile:
		_clear_discard_pile_highlight()
	if discard_pile == pile:
		discard_pile = null


func _on_discard_pile_entered(pile: DiscardPile) -> void:
	if not _overlapping_discard_piles.has(pile):
		_overlapping_discard_piles.append(pile)


func _on_discard_pile_exited(pile: DiscardPile) -> void:
	_overlapping_discard_piles.erase(pile)
	if _last_highlighted_discard_pile == pile:
		_clear_discard_pile_highlight()


func _clear_discard_pile_highlight() -> void:
	if _last_highlighted_discard_pile:
		_last_highlighted_discard_pile.set_highlight(false)
		_last_highlighted_discard_pile = null


# -----------------------------------------------------------------------------
# Z-Index and Stacking Order
# -----------------------------------------------------------------------------
## Enforces consistent, non-overlapping z-indices across all slots and docked cards.
func update_slot_and_card_order() -> void:
	if not is_inside_tree():
		return

	var slots: Array[Node] = get_tree().get_nodes_in_group("card_slots")
	slots.sort_custom(
		func(a: Node, b: Node) -> bool:
			if a.get_parent() == b.get_parent():
				return a.get_index() < b.get_index()
			return (a as CanvasItem).z_index < (b as CanvasItem).z_index,
	)

	for i: int in range(slots.size()):
		var slot: CardSlot = slots[i] as CardSlot
		if not slot:
			continue

		slot.z_index = i * 2
		if slot.card_in_slot:
			slot.card_in_slot.resting_z_index = i * 2 + 1
			if not slot.card_in_slot.is_dragging:
				slot.card_in_slot.z_index = slot.card_in_slot.resting_z_index
			if slot.card_in_slot.get_parent():
				slot.card_in_slot.get_parent().move_child(slot.card_in_slot, -1)


func _on_child_entered_tree(node: Node) -> void:
	if node is Card:
		register_card(node)
		if card_hand and not node.card_slot and not card_hand.has_card(node):
			card_hand.add_card(node, -1, true)
	elif node is CardSlot:
		register_card_slot(node)
	elif node is DiscardPile:
		register_discard_pile(node)
	elif node is CardHand and not card_hand:
		card_hand = node
	update_slot_and_card_order()


func _on_child_exiting_tree(node: Node) -> void:
	if node is Card:
		if node == card_being_dragged:
			card_being_dragged = null
			_drag_source_slot = null
		_clicked_candidates.erase(node)
		_hovered_candidates.erase(node)
		if card_hand:
			card_hand.remove_card(node, false)
		unregister_card(node)
	elif node is CardSlot:
		_overlapping_slots.erase(node)
		unregister_card_slot(node)
	elif node is DiscardPile:
		unregister_discard_pile(node)
	elif node == card_hand:
		card_hand = null
	update_slot_and_card_order()


# -----------------------------------------------------------------------------
# Drag & Drop Resolution
# -----------------------------------------------------------------------------
func _process_card_drag_motion() -> void:
	if not card_being_dragged:
		return

	if is_inside_tree():
		var target_pos: Vector2 = get_global_mouse_position() - card_being_dragged.drag_offset
		var vp_rect: Rect2 = get_viewport_rect()
		card_being_dragged.global_position = target_pos.clamp(Vector2.ZERO, vp_rect.size)

	# Update visual highlight on current slot under mouse
	var current_slot: CardSlot = over_card_slot
	if current_slot != _last_highlighted_slot:
		_clear_slot_highlight()
		if current_slot:
			current_slot.set_highlight(true)
			_last_highlighted_slot = current_slot

	# Update visual highlight on current discard pile under mouse
	var current_discard: DiscardPile = over_discard_pile
	if current_discard != _last_highlighted_discard_pile:
		_clear_discard_pile_highlight()
		if current_discard:
			current_discard.set_highlight(true)
			_last_highlighted_discard_pile = current_discard

	# Dynamic hand reordering & unslotting preview
	if card_hand:
		if current_slot == null and current_discard == null:
			var is_from_slot: bool = _drag_source_slot != null
			var in_hand_zone: bool = card_being_dragged.global_position.y >= card_hand.hand_center.y - 200.0

			if not is_from_slot or in_hand_zone:
				if not card_hand.has_card(card_being_dragged):
					if not card_hand.is_full:
						var insert_idx: int = card_hand.get_insertion_index_for_position(
							card_being_dragged.global_position
						)
						card_hand.add_card(card_being_dragged, insert_idx, true)
				else:
					var target_idx: int = card_hand.get_insertion_index_for_position(
						card_being_dragged.global_position,
						card_being_dragged,
						20.0,
					)
					var current_idx: int = card_hand.get_card_index(card_being_dragged)
					if target_idx != current_idx:
						card_hand.move_card(card_being_dragged, target_idx, true)
			else:
				# Slotted card dragged back above hand zone
				if card_hand.has_card(card_being_dragged):
					card_hand.remove_card(card_being_dragged, true)
		else:
			# Slotted card dragged over a slot or discard pile: withdraw temporary hand preview
			if _drag_source_slot != null and card_hand.has_card(card_being_dragged):
				card_hand.remove_card(card_being_dragged, true)


func _handle_card_drop(card: Card) -> void:
	_clear_slot_highlight()
	_clear_discard_pile_highlight()

	var dropped_card: Card = card
	card_being_dragged = null
	if dropped_card:
		dropped_card.stop_drag()
		_clear_hover_state_for(dropped_card)

	var target_discard: DiscardPile = over_discard_pile
	if target_discard:
		target_discard.discard_card(dropped_card, true)
		_drag_source_slot = null
		update_slot_and_card_order()
		if is_inside_tree():
			_update_hover_on_motion(get_global_mouse_position())
		return

	var target_slot: CardSlot = over_card_slot
	if target_slot:
		if target_slot.is_occupied and target_slot.card_in_slot != dropped_card:
			_swap_cards(dropped_card, target_slot)
		else:
			_dock_card_in_slot(dropped_card, target_slot)
	else:
		_return_card_to_origin(dropped_card)

	_drag_source_slot = null
	if is_inside_tree():
		_update_hover_on_motion(get_global_mouse_position())


func _dock_card_in_slot(card: Card, target_slot: CardSlot) -> void:
	if card_hand and card_hand.has_card(card):
		card_hand.remove_card(card, true)

	var source_slot: CardSlot = card.card_slot if card.card_slot else _drag_source_slot
	# Release from prior slot if moved between slots
	if source_slot and source_slot != target_slot:
		source_slot.clear_card()

	target_slot.assign_card(card)
	card.snap_to_slot(target_slot)
	update_slot_and_card_order()


func _swap_cards(dragged_card: Card, target_slot: CardSlot) -> void:
	var previous_card: Card = target_slot.card_in_slot
	var source_slot: CardSlot = dragged_card.card_slot if dragged_card.card_slot else _drag_source_slot

	if card_hand and card_hand.has_card(dragged_card):
		card_hand.remove_card(dragged_card, false)

	# Dock dragged card into target slot
	target_slot.assign_card(dragged_card)
	dragged_card.snap_to_slot(target_slot)

	# Move previous occupant into dragged card's origin slot or back into hand
	if source_slot:
		source_slot.assign_card(previous_card)
		previous_card.snap_to_slot(source_slot)
	else:
		previous_card.card_slot = null
		if card_hand:
			var insert_idx: int = card_hand.get_insertion_index_for_position(
				dragged_card.global_position
			)
			card_hand.add_card(previous_card, insert_idx, true)
		else:
			previous_card.resting_z_index = 0
			var parent_node: Node2D = previous_card.get_parent() as Node2D
			var return_pos: Vector2 = parent_node.to_local(previous_card.position_before_drag) if parent_node else previous_card.position_before_drag
			previous_card.return_to_position(return_pos)

	if card_hand:
		card_hand.reorganize_hand(true)

	update_slot_and_card_order()


func _return_card_to_origin(card: Card) -> void:
	var source_slot: CardSlot = card.card_slot if card.card_slot else _drag_source_slot
	if source_slot:
		# If hand exists and not full (or card already belongs to hand), unslot back to hand
		if card_hand and (card_hand.has_card(card) or not card_hand.is_full):
			source_slot.clear_card()
			card.card_slot = null
			var insert_idx: int = card_hand.get_insertion_index_for_position(
				card.global_position,
				card if card_hand.has_card(card) else null,
			)
			if card_hand.has_card(card):
				card_hand.move_card(card, insert_idx, false)
				card_hand.reorganize_hand(true)
				CardAudio.place()
			else:
				card_hand.add_card(card, insert_idx, true)
				CardAudio.place()
		else:
			# Return into assigned slot (either hand is full or no hand exists)
			source_slot.assign_card(card)
			card.snap_to_slot(source_slot)
	else:
		# Return to hand/table resting position
		if card_hand:
			var insert_idx: int = card_hand.get_insertion_index_for_position(
				card.global_position,
				card if card_hand.has_card(card) else null,
			)
			if not card_hand.has_card(card):
				if not card_hand.is_full:
					card_hand.add_card(card, insert_idx, true)
					CardAudio.place()
				else:
					card.resting_z_index = 0
					var parent_node: Node2D = card.get_parent() as Node2D
					var return_pos: Vector2 = parent_node.to_local(card.position_before_drag) if parent_node else card.position_before_drag
					card.return_to_position(return_pos)
			else:
				card_hand.move_card(card, insert_idx, false)
				card_hand.reorganize_hand(true)
				CardAudio.place()
		else:
			card.resting_z_index = 0
			var parent_node: Node2D = card.get_parent() as Node2D
			var return_pos: Vector2 = parent_node.to_local(card.position_before_drag) if parent_node else card.position_before_drag
			card.return_to_position(return_pos)

	update_slot_and_card_order()


func _clear_slot_highlight() -> void:
	if _last_highlighted_slot:
		_last_highlighted_slot.set_highlight(false)
		_last_highlighted_slot = null


func _clear_hover_state_for(card: Card) -> void:
	card.set_hovered(false)
	if card_being_hovered == card:
		card_being_hovered = null
	_hovered_candidates.erase(card)


# -----------------------------------------------------------------------------
# Input & Overlap Candidate Arbitrage
# -----------------------------------------------------------------------------
func _on_card_clicked(card: Card) -> void:
	_is_mouse_down = true
	_clicked_candidates.append(card)
	if _clicked_candidates.size() == 1:
		_resolve_click.call_deferred()


func _resolve_click() -> void:
	if _clicked_candidates.is_empty():
		return

	var top_card: Card = _find_top_card(_clicked_candidates)
	_clicked_candidates.clear()

	# If mouse button was already released, do not enter drag state
	if not _is_mouse_down and not Input.is_mouse_button_pressed(MouseButton.MOUSE_BUTTON_LEFT):
		return

	card_being_dragged = top_card
	_drag_source_slot = card_being_dragged.card_slot

	# Free slot occupancy temporarily while dragging
	if card_being_dragged.card_slot:
		card_being_dragged.card_slot.card_in_slot = null

	card_being_dragged.start_drag()
	card_being_dragged.set_hovered(true)
	card_being_hovered = card_being_dragged
	update_slot_and_card_order()


func _on_card_hovered(card: Card) -> void:
	if card_being_dragged or card.is_card_on_card_slot:
		return

	if not _hovered_candidates.has(card):
		_hovered_candidates.append(card)

	if _hovered_candidates.size() == 1:
		_resolve_hover.call_deferred()


func _on_card_unhovered(card: Card) -> void:
	if card == card_being_dragged:
		_hovered_candidates.erase(card)
		return

	# Secondary safety: if mouse is still physically over the card or its resting bounds, ignore unhover chatter
	if is_inside_tree() and card.has_method("contains_global_point") and card.contains_global_point(get_global_mouse_position(), true):
		return

	_hovered_candidates.erase(card)

	if card == card_being_hovered:
		card_being_hovered.set_hovered(false)
		card_being_hovered = null

		if not _hovered_candidates.is_empty():
			_resolve_hover.call_deferred()
		elif is_inside_tree():
			_update_hover_on_motion(get_global_mouse_position())


func _switch_hover_to(card: Card) -> void:
	if card == card_being_hovered:
		return
	if card_being_hovered:
		card_being_hovered.set_hovered(false)
	card_being_hovered = card
	if card_being_hovered:
		card_being_hovered.set_hovered(true)
		CardAudio.hover()
		_suppress_pile_hover()


func _update_hover_on_motion(mouse_pos: Vector2) -> void:
	if card_being_dragged or not is_inside_tree():
		return

	var candidates: Array[Card] = []
	var all_cards: Array[Node] = get_tree().get_nodes_in_group("cards")

	for node: Node in all_cards:
		var c := node as Card
		if not c or not is_instance_valid(c) or c.is_card_on_card_slot or c.current_state == Card.State.RETURNING:
			continue
		var check_margin: bool = (c == card_being_hovered)
		if c.contains_global_point(mouse_pos, check_margin):
			candidates.append(c)

	if candidates.is_empty():
		if card_being_hovered:
			card_being_hovered.set_hovered(false)
			card_being_hovered = null
		_hovered_candidates.clear()
		return

	var top_card: Card = _find_top_card(candidates)
	if card_being_hovered and candidates.has(card_being_hovered):
		# Retain active hover unless top_card is strictly higher and mouse is strictly within its body
		if top_card != card_being_hovered and top_card.contains_global_point(mouse_pos, false):
			var top_val: int = top_card.resting_z_index if top_card.resting_z_index != 0 else top_card.z_index
			var cur_val: int = card_being_hovered.resting_z_index if card_being_hovered.resting_z_index != 0 else card_being_hovered.z_index
			if top_val > cur_val or (top_val == cur_val and top_card.get_index() > card_being_hovered.get_index()):
				_switch_hover_to(top_card)
	else:
		_switch_hover_to(top_card)


func _resolve_hover() -> void:
	if _hovered_candidates.is_empty():
		return

	var top_card: Card = _find_top_card(_hovered_candidates)
	_switch_hover_to(top_card)


func _suppress_pile_hover() -> void:
	if card_being_dragged != null:
		return
	if discard_pile and discard_pile.has_method("cancel_hover"):
		discard_pile.cancel_hover()
	if is_inside_tree():
		var decks := get_tree().get_nodes_in_group("card_decks")
		for d in decks:
			if d.has_method("cancel_hover"):
				d.cancel_hover()


func _find_top_card(candidates: Array[Card]) -> Card:
	var top_card: Card = candidates[0]
	for card: Card in candidates:
		var top_val: int = top_card.resting_z_index if top_card.resting_z_index != 0 else top_card.z_index
		var card_val: int = card.resting_z_index if card.resting_z_index != 0 else card.z_index
		if (
			card_val > top_val
			or (card_val == top_val and card.get_index() > top_card.get_index())
		):
			top_card = card
	return top_card


func _on_card_slot_entered(card_slot: CardSlot) -> void:
	if not _overlapping_slots.has(card_slot):
		_overlapping_slots.append(card_slot)


func _on_card_slot_exited(card_slot: CardSlot) -> void:
	_overlapping_slots.erase(card_slot)
	if _last_highlighted_slot == card_slot:
		_clear_slot_highlight()
