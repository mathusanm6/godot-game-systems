class_name CardManager
extends Node2D

## Optional explicit reference to the CardHand node.
@export var card_hand: CardHand = null

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

# Internal tracking
var _overlapping_slots: Array[CardSlot] = []
var _clicked_candidates: Array[Card] = []
var _hovered_candidates: Array[Card] = []
var _last_highlighted_slot: CardSlot = null


func _ready() -> void:
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

	if card_hand:
		card_hand.reorganize_hand(false)

	update_slot_and_card_order()


func _exit_tree() -> void:
	_clear_slot_highlight()


var _is_mouse_down: bool = false


func _process(_delta: float) -> void:
	if card_being_dragged and not _is_mouse_down and not Input.is_mouse_button_pressed(MouseButton.MOUSE_BUTTON_LEFT):
		_handle_card_drop(card_being_dragged)


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

	elif not card_being_dragged:
		return

	# 2. Update position during drag
	elif event is InputEventMouseMotion:
		_process_card_drag_motion()


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


func _on_child_entered_tree(node: Node) -> void:
	if node is Card:
		register_card(node)
		if card_hand and not node.card_slot and not card_hand.has_card(node):
			card_hand.add_card(node, -1, true)
	elif node is CardSlot:
		register_card_slot(node)
	elif node is CardHand and not card_hand:
		card_hand = node
	update_slot_and_card_order()


func _on_child_exiting_tree(node: Node) -> void:
	if node is Card:
		_clicked_candidates.erase(node)
		_hovered_candidates.erase(node)
		if card_hand:
			card_hand.remove_card(node, false)
		unregister_card(node)
	elif node is CardSlot:
		_overlapping_slots.erase(node)
		unregister_card_slot(node)
	elif node == card_hand:
		card_hand = null
	update_slot_and_card_order()


# -----------------------------------------------------------------------------
# Drag & Drop Resolution
# -----------------------------------------------------------------------------

func _process_card_drag_motion() -> void:
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


func _handle_card_drop(card: Card) -> void:
	_clear_slot_highlight()

	var dropped_card: Card = card
	card_being_dragged = null
	if dropped_card:
		dropped_card.stop_drag()
		_clear_hover_state_for(dropped_card)

	var target_slot: CardSlot = over_card_slot
	if target_slot:
		if target_slot.is_occupied and target_slot.card_in_slot != dropped_card:
			_swap_cards(dropped_card, target_slot)
		else:
			_dock_card_in_slot(dropped_card, target_slot)
	else:
		_return_card_to_origin(dropped_card)


func _dock_card_in_slot(card: Card, target_slot: CardSlot) -> void:
	if card_hand and card_hand.has_card(card):
		card_hand.remove_card(card, true)

	# Release from prior slot if moved between slots
	if card.card_slot and card.card_slot != target_slot:
		card.card_slot.clear_card()

	target_slot.assign_card(card)
	card.snap_to_slot(target_slot)
	update_slot_and_card_order()


func _swap_cards(dragged_card: Card, target_slot: CardSlot) -> void:
	var previous_card: Card = target_slot.card_in_slot
	var source_slot: CardSlot = dragged_card.card_slot

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
			card_hand.add_card(previous_card, -1, true)
		else:
			previous_card.resting_z_index = 0
			var parent_node: Node2D = previous_card.get_parent() as Node2D
			var return_pos: Vector2 = parent_node.to_local(previous_card.position_before_drag) if parent_node else previous_card.position_before_drag
			previous_card.return_to_position(return_pos)

	if card_hand:
		card_hand.reorganize_hand(true)

	update_slot_and_card_order()


func _return_card_to_origin(card: Card) -> void:
	if card.card_slot:
		# If hand exists, dropping outside slots unslots the card back to hand
		if card_hand:
			var slot: CardSlot = card.card_slot
			slot.clear_card()
			card.card_slot = null
			card_hand.add_card(card, -1, true)
		else:
			# Return into assigned slot
			card.card_slot.assign_card(card)
			card.snap_to_slot(card.card_slot)
	else:
		# Return to hand/table resting position
		if card_hand:
			if not card_hand.has_card(card):
				card_hand.add_card(card, -1, true)
			else:
				card_hand.reorganize_hand(true)
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
	_hovered_candidates.erase(card)

	if card == card_being_dragged:
		return

	if card == card_being_hovered:
		card_being_hovered.set_hovered(false)
		card_being_hovered = null

		if not _hovered_candidates.is_empty():
			_resolve_hover.call_deferred()


func _resolve_hover() -> void:
	if _hovered_candidates.is_empty():
		return

	var top_card: Card = _find_top_card(_hovered_candidates)
	if top_card != card_being_hovered:
		if card_being_hovered:
			card_being_hovered.set_hovered(false)
		card_being_hovered = top_card
		card_being_hovered.set_hovered(true)


func _find_top_card(candidates: Array[Card]) -> Card:
	var top_card: Card = candidates[0]
	for card: Card in candidates:
		if (
			card.z_index > top_card.z_index
			or (card.z_index == top_card.z_index and card.get_index() > top_card.get_index())
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


# -----------------------------------------------------------------------------
# Z-Index and Stacking Order
# -----------------------------------------------------------------------------

## Enforces consistent, non-overlapping z-indices across all slots and docked cards.
func update_slot_and_card_order() -> void:
	if not is_inside_tree():
		return

	var slots: Array[Node] = get_tree().get_nodes_in_group("card_slots")
	slots.sort_custom(func(a: Node, b: Node) -> bool:
		if a.get_parent() == b.get_parent():
			return a.get_index() < b.get_index()
		return (a as CanvasItem).z_index < (b as CanvasItem).z_index
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
