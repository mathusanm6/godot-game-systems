class_name CardHand
extends Node2D

## Emitted when a card is added to the hand.
signal card_added(card: Card)
## Emitted when a card is removed from the hand.
signal card_removed(card: Card)
## Emitted whenever the hand layout is recalculated and cards are rearranged.
signal hand_reorganized

@export_group("Layout Geometry")
## Center position of the hand arc (highest point of the curve).
@export var hand_center: Vector2 = Vector2(640, 640):
	set(value):
		hand_center = value
		if is_node_ready():
			reorganize_hand(false)

## Maximum horizontal spacing between card centers.
@export_range(50.0, 250.0, 5.0) var max_card_spacing: float = 140.0:
	set(value):
		max_card_spacing = value
		if is_node_ready():
			reorganize_hand(false)

## Maximum total width of the hand. Spacing compresses if cards exceed this.
@export_range(200.0, 1200.0, 10.0) var max_hand_width: float = 720.0:
	set(value):
		max_hand_width = value
		if is_node_ready():
			reorganize_hand(false)

## Parabolic vertical drop from center to the outermost cards in pixels.
@export_range(0.0, 80.0, 1.0) var arc_height: float = 28.0:
	set(value):
		arc_height = value
		if is_node_ready():
			reorganize_hand(false)

## Rotation angle step per card in degrees.
@export_range(1.0, 15.0, 0.5) var card_angle_step_deg: float = 5.5:
	set(value):
		card_angle_step_deg = value
		if is_node_ready():
			reorganize_hand(false)

## Maximum total angular spread (first to last card) in degrees.
@export_range(10.0, 70.0, 1.0) var max_angle_spread_deg: float = 36.0:
	set(value):
		max_angle_spread_deg = value
		if is_node_ready():
			reorganize_hand(false)

## Base Z-index for cards in hand. Each card receives base_z_index + index.
@export var base_z_index: int = 10:
	set(value):
		base_z_index = value
		if is_node_ready():
			reorganize_hand(false)

@export_group("Animation")
## Duration in seconds for card movement transitions when hand rearranges.
@export_range(0.1, 0.8, 0.05) var transition_duration: float = 0.25

## Ordered list of cards currently held in hand.
var cards: Array[Card] = []


func _ready() -> void:
	add_to_group("card_hands")

	# Register all existing Card children into the hand
	for child: Node in get_children():
		if child is Card:
			if not cards.has(child):
				cards.append(child)
				child.card_hand = self

	reorganize_hand(false)


## Adds a card to the hand at the given index (or end if -1).
func add_card(card: Card, at_index: int = -1, animate: bool = true) -> void:
	if not card:
		return

	if cards.has(card):
		card.card_hand = self
		reorganize_hand(animate)
		return

	if card.get_parent() != self:
		if card.get_parent():
			card.reparent(self)
		else:
			add_child(card)

	card.card_hand = self
	card.card_slot = null

	if at_index >= 0 and at_index < cards.size():
		cards.insert(at_index, card)
	else:
		cards.append(card)

	reorganize_hand(animate)
	card_added.emit(card)


## Removes a card from the hand.
func remove_card(card: Card, animate: bool = true) -> bool:
	if not card or not cards.has(card):
		return false

	cards.erase(card)
	if card.card_hand == self:
		card.card_hand = null

	reorganize_hand(animate)
	card_removed.emit(card)
	return true


## Checks if card is in the hand.
func has_card(card: Card) -> bool:
	return cards.has(card)


## Returns the index of a card in hand, or -1 if not found.
func get_card_index(card: Card) -> int:
	return cards.find(card)


## Returns the number of cards in hand.
func get_card_count() -> int:
	return cards.size()


## Calculates target transform (position, rotation, z_index) for a card at index.
func calculate_card_transform(index: int, total_cards: int) -> Dictionary:
	if total_cards <= 0:
		return {"position": hand_center, "rotation": 0.0, "z_index": base_z_index}

	if total_cards == 1:
		return {"position": hand_center, "rotation": 0.0, "z_index": base_z_index}

	var u: float = float(index) - (float(total_cards - 1) / 2.0)
	var half_span: float = float(total_cards - 1) / 2.0
	var norm: float = u / half_span

	# Dynamic horizontal spacing with max_hand_width cap
	var spacing: float = minf(max_card_spacing, max_hand_width / float(total_cards - 1))
	var pos_x: float = hand_center.x + u * spacing

	# Parabolic vertical drop: center card at hand_center.y, outer cards drop by arc_height
	var pos_y: float = hand_center.y + (norm * norm) * arc_height

	# Dynamic angular spread
	var angle_step: float = minf(card_angle_step_deg, max_angle_spread_deg / float(total_cards - 1))
	var rot: float = deg_to_rad(u * angle_step)

	var card_z: int = base_z_index + index

	return {
		"position": Vector2(pos_x, pos_y),
		"rotation": rot,
		"z_index": card_z,
	}


## Re-calculates and applies curved hand layout across all cards in hand.
func reorganize_hand(animate: bool = true) -> void:
	# Purge any invalid/freed instances
	cards = cards.filter(func(c: Card) -> bool: return is_instance_valid(c))
	var total: int = cards.size()

	for i: int in range(total):
		var card: Card = cards[i]
		var trans: Dictionary = calculate_card_transform(i, total)
		card.hand_position = trans.position
		card.hand_rotation = trans.rotation
		card.resting_z_index = trans.z_index

		var should_tween: bool = animate and not Engine.is_editor_hint() and card.is_inside_tree()

		if not card.is_dragging:
			if not card.is_hovered:
				card.z_index = card.resting_z_index

			if should_tween:
				if not card.is_hovered:
					card.return_to_position(card.hand_position, card.hand_rotation, transition_duration)
			else:
				card.position = card.hand_position
				if not card.is_hovered:
					card.rotation = card.hand_rotation

	hand_reorganized.emit()


## Convenience method to return a card into the hand with animation.
func return_card_to_hand(card: Card, animate: bool = true) -> void:
	if not card:
		return
	if not cards.has(card):
		add_card(card, -1, animate)
	else:
		reorganize_hand(animate)
