class_name CardDeck
extends Area2D

## Emitted when a card is drawn from the deck.
signal card_drawn(card_data: CardData, card_instance: Card)
## Emitted when draw pile runs out of cards.
signal deck_depleted
## Emitted whenever the remaining card count changes.
signal deck_count_changed(count: int)

@export_group("Deck Configuration")
## Card scene to instantiate when drawing.
@export var card_scene: PackedScene = preload("res://features/card/Card.tscn")
## Initial list of CardData resources in this deck.
@export var initial_cards: Array[CardData] = []
## Whether to shuffle the draw pile upon initialization.
@export var shuffle_on_ready: bool = true
## Whether clicking the deck directly draws a card.
@export var can_click_to_draw: bool = true

@export_group("Dependencies")
## Reference to CardHand node where drawn cards are placed.
@export var card_hand: CardHand = null
## Reference to CardManager node for registering drawn cards.
@export var card_manager: CardManager = null

@export_group("Visual Feedback")
## Hover scale multiplier.
@export_range(1.0, 1.3, 0.02) var hover_scale: float = 1.06
## Duration of hover transitions.
@export_range(0.05, 0.4, 0.01) var hover_duration: float = 0.16

## Current runtime draw pile.
var draw_pile: Array[CardData] = []

## Whether the deck is empty.
var is_empty: bool:
	get:
		return draw_pile.is_empty()

## Current number of remaining cards in deck.
var remaining_count: int:
	get:
		return draw_pile.size()

var _base_scale: Vector2 = Vector2.ONE
var _hover_tween: Tween
var _pulse_tween: Tween
var _is_hovered: bool = false

@onready var count_label: Label = get_node_or_null("%CountLabel")
@onready var deck_sprite: Sprite2D = get_node_or_null("%DeckSprite")
@onready var stack_sprite_1: Sprite2D = get_node_or_null("%StackSprite1")
@onready var stack_sprite_2: Sprite2D = get_node_or_null("%StackSprite2")


func _ready() -> void:
	add_to_group("card_decks")
	_base_scale = scale

	if not card_hand:
		var hands: Array[Node] = get_tree().get_nodes_in_group("card_hands")
		if not hands.is_empty():
			card_hand = hands[0] as CardHand

	if not card_manager:
		var managers: Array[Node] = get_tree().get_nodes_in_group("card_managers")
		if not managers.is_empty():
			card_manager = managers[0] as CardManager
		elif get_parent() is CardManager:
			card_manager = get_parent() as CardManager

	# Populate draw pile
	draw_pile = initial_cards.duplicate()
	if shuffle_on_ready and not draw_pile.is_empty():
		draw_pile.shuffle()

	_update_display()

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _exit_tree() -> void:
	if _hover_tween:
		_hover_tween.kill()
	if _pulse_tween:
		_pulse_tween.kill()


## Draws a card, instantiates its visual representation, and places it into hand.
func draw_card() -> Card:
	if draw_pile.is_empty():
		deck_depleted.emit()
		_play_empty_shake()
		return null

	var drawn_data: CardData = draw_pile.pop_back()
	deck_count_changed.emit(draw_pile.size())
	_update_display()
	_play_draw_pulse()

	if not card_scene:
		return null

	var card_instance: Card = card_scene.instantiate() as Card
	card_instance.card_data = drawn_data

	# Attach into tree and set initial spawn position at deck
	if card_hand:
		card_hand.add_child(card_instance)
		card_instance.global_position = global_position
		card_instance.rotation = 0.0

		if card_manager:
			card_manager.register_card(card_instance)

		card_hand.add_card(card_instance, -1, true)
	elif card_manager:
		card_manager.add_child(card_instance)
		card_instance.global_position = global_position
		card_manager.register_card(card_instance)

	card_drawn.emit(drawn_data, card_instance)
	return card_instance


## Adds a card back to the deck (e.g. for reshuffle or discard recycling).
func add_card_to_deck(card_data: CardData, shuffle: bool = false) -> void:
	if not card_data:
		return
	draw_pile.append(card_data)
	if shuffle:
		draw_pile.shuffle()
	deck_count_changed.emit(draw_pile.size())
	_update_display()


## Shuffles the current draw pile.
func shuffle_deck() -> void:
	draw_pile.shuffle()


## Refills the deck with given cards.
func reset_deck(new_cards: Array[CardData], shuffle: bool = true) -> void:
	draw_pile = new_cards.duplicate()
	if shuffle:
		draw_pile.shuffle()
	deck_count_changed.emit(draw_pile.size())
	_update_display()


func _update_display() -> void:
	if count_label:
		count_label.text = str(draw_pile.size())

	var has_cards: bool = not draw_pile.is_empty()
	var target_alpha: float = 1.0 if has_cards else 0.4
	modulate.a = target_alpha

	if stack_sprite_1:
		stack_sprite_1.visible = draw_pile.size() > 1
	if stack_sprite_2:
		stack_sprite_2.visible = draw_pile.size() > 3


func _play_draw_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()

	_pulse_tween = create_tween()
	var target_boost: Vector2 = _base_scale * (hover_scale * 1.08 if _is_hovered else 1.08)
	var rest_scale: Vector2 = _base_scale * (hover_scale if _is_hovered else 1.0)
	_pulse_tween.tween_property(self, "scale", target_boost, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(self, "scale", rest_scale, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_empty_shake() -> void:
	if _pulse_tween:
		_pulse_tween.kill()

	var original_pos: Vector2 = position
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "position:x", original_pos.x - 6.0, 0.04)
	_pulse_tween.tween_property(self, "position:x", original_pos.x + 6.0, 0.04)
	_pulse_tween.tween_property(self, "position:x", original_pos.x - 4.0, 0.04)
	_pulse_tween.tween_property(self, "position:x", original_pos.x, 0.04)


func _on_mouse_entered() -> void:
	_is_hovered = true
	if _hover_tween:
		_hover_tween.kill()

	_hover_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "scale", _base_scale * hover_scale, hover_duration)


func _on_mouse_exited() -> void:
	_is_hovered = false
	if _hover_tween:
		_hover_tween.kill()

	_hover_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "scale", _base_scale, hover_duration)


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if not can_click_to_draw:
		return

	if event is InputEventMouseButton and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			draw_card()
