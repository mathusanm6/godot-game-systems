class_name DiscardPile
extends Area2D

## Emitted when a card is added to the discard pile.
signal card_discarded(card_data: CardData, card_instance: Card)
## Emitted when the number of discarded cards changes.
signal discard_count_changed(count: int)
## Emitted when the discard pile is cleared or recycled into a deck.
signal discard_pile_cleared
## Emitted when pointer enters this discard pile's boundary.
signal discard_pile_entered(pile: DiscardPile)
## Emitted when pointer exits this discard pile's boundary.
signal discard_pile_exited(pile: DiscardPile)

@export_group("Card Presentation")
## Card back texture shown when pile is facedown or empty (e.g. lattice_red.png).
@export var card_back_texture: Texture2D = preload("res://art/decks/backs/hd/lattice_red.png"):
	set(value):
		card_back_texture = value
		if is_node_ready():
			_update_display()

## Whether the top discarded card shows its face artwork (true) or card back (false).
@export var show_top_card_face_up: bool = true:
	set(value):
		show_top_card_face_up = value
		if is_node_ready():
			_update_display()

@export_group("Dependencies")
## Optional reference to a deck to recycle into.
@export var target_deck: Node = null

@export_group("Visual Feedback")
## Hover scale multiplier.
@export_range(1.0, 1.3, 0.02) var hover_scale: float = 1.06
## Duration of hover transitions in seconds.
@export_range(0.05, 0.4, 0.01) var hover_duration: float = 0.16
## Highlight color when dragged card hovers over this pile.
@export var highlight_color: Color = Color(1.3, 1.1, 1.1, 1.0)

## Internal list of discarded CardData in chronological order (last item is top of pile).
var discard_pile: Array[CardData] = []

## Current count of cards in the discard pile.
var remaining_count: int:
	get:
		return discard_pile.size()

## Whether the discard pile is empty.
var is_empty: bool:
	get:
		return discard_pile.is_empty()

var _base_scale: Vector2 = Vector2.ONE
var _base_modulate: Color = Color.WHITE
var _hover_tween: Tween
var _is_hovered: bool = false
var _is_highlighted: bool = false

@onready var top_card_sprite: Sprite2D = get_node_or_null("%TopCardSprite")
@onready var stack_sprite_1: Sprite2D = get_node_or_null("%StackSprite1")
@onready var stack_sprite_2: Sprite2D = get_node_or_null("%StackSprite2")
@onready var empty_slot_sprite: Sprite2D = get_node_or_null("%EmptySlotSprite")
@onready var count_label: Label = get_node_or_null("%CountLabel")


func _ready() -> void:
	add_to_group("discard_piles")
	_base_scale = scale
	_base_modulate = modulate

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	_update_display()


func _exit_tree() -> void:
	if _hover_tween:
		_hover_tween.kill()


## Discards an active Card instance into this pile.
func discard_card(card: Card, animate: bool = true) -> void:
	if not card or not is_instance_valid(card):
		return

	var data: CardData = card.card_data

	# Release from slot if docked
	if card.card_slot:
		card.card_slot.clear_card()
		card.card_slot = null

	# Release from hand if currently held
	if card.card_hand and card.card_hand.has_method("remove_card"):
		card.card_hand.remove_card(card, true)

	if data:
		discard_pile.append(data)

	if animate and is_inside_tree() and not Engine.is_editor_hint():
		card.stop_drag()
		card.z_index = 200
		var tween := card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "global_position", global_position, 0.22)
		tween.tween_property(card, "rotation", 0.0, 0.22)
		tween.tween_property(card, "scale", Vector2(0.65, 0.65), 0.22)
		tween.chain().tween_callback(
			func() -> void:
				if is_instance_valid(card):
					card.queue_free()
				_update_display(),
		)
	else:
		card.queue_free()
		_update_display()

	card_discarded.emit(data, card)
	discard_count_changed.emit(discard_pile.size())


## Adds CardData directly to the discard pile without a scene instance.
func discard_card_data(data: CardData) -> void:
	if not data:
		return
	discard_pile.append(data)
	_update_display()
	discard_count_changed.emit(discard_pile.size())


## Recycles all cards in the discard pile back into a target deck.
func recycle_into_deck(deck: Node = target_deck, shuffle: bool = true) -> int:
	if not deck or discard_pile.is_empty():
		return 0

	var count: int = discard_pile.size()
	while not discard_pile.is_empty():
		var data: CardData = discard_pile.pop_back()
		if deck.has_method("add_card_to_deck"):
			deck.add_card_to_deck(data, false)

	if shuffle and deck.has_method("shuffle_deck"):
		deck.shuffle_deck()

	_update_display()
	discard_pile_cleared.emit()
	discard_count_changed.emit(0)
	return count


## Clears all cards in the discard pile.
func clear_discard_pile() -> void:
	discard_pile.clear()
	_update_display()
	discard_pile_cleared.emit()
	discard_count_changed.emit(0)


## Sets visual highlight state (e.g. when dragged card hovers over pile).
func set_highlight(on: bool) -> void:
	_is_highlighted = on
	if _hover_tween:
		_hover_tween.kill()

	_hover_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var target_mod: Color = highlight_color if on else _base_modulate
	var target_sc: Vector2 = _base_scale * (hover_scale if on or _is_hovered else 1.0)
	_hover_tween.tween_property(self, "modulate", target_mod, hover_duration)
	_hover_tween.tween_property(self, "scale", target_sc, hover_duration)


## Updates visual elements based on current pile state.
func _update_display() -> void:
	if not is_inside_tree():
		return

	var count: int = discard_pile.size()
	if count_label:
		count_label.text = str(count)

	if count == 0:
		if empty_slot_sprite:
			empty_slot_sprite.visible = true
		if top_card_sprite:
			top_card_sprite.visible = false
		if stack_sprite_1:
			stack_sprite_1.visible = false
		if stack_sprite_2:
			stack_sprite_2.visible = false
	else:
		if empty_slot_sprite:
			empty_slot_sprite.visible = false

		var top_data: CardData = discard_pile.back()
		if top_card_sprite:
			top_card_sprite.visible = true
			if show_top_card_face_up and top_data and top_data.artwork:
				top_card_sprite.texture = top_data.artwork
			else:
				top_card_sprite.texture = card_back_texture

		if stack_sprite_1:
			stack_sprite_1.visible = count > 1
			stack_sprite_1.texture = card_back_texture
		if stack_sprite_2:
			stack_sprite_2.visible = count > 3
			stack_sprite_2.texture = card_back_texture


func _on_mouse_entered() -> void:
	_is_hovered = true
	discard_pile_entered.emit(self)
	if not _is_highlighted:
		_animate_scale(_base_scale * hover_scale)


func _on_mouse_exited() -> void:
	_is_hovered = false
	discard_pile_exited.emit(self)
	if not _is_highlighted:
		_animate_scale(_base_scale)


func _animate_scale(target: Vector2) -> void:
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "scale", target, hover_duration)
