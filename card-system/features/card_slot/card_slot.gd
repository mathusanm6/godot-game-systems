class_name CardSlot
extends Area2D

## Emitted when a pointer enters this slot's collision boundary.
signal card_slot_entered(slot: CardSlot)
## Emitted when a pointer exits this slot's collision boundary.
signal card_slot_exited(slot: CardSlot)
## Emitted when a card is successfully docked into this slot.
signal card_slotted(card: Card, slot: CardSlot)
## Emitted when a card is removed from this slot.
signal card_unslotted(card: Card, slot: CardSlot)

@export_group("Visual Feedback")
## Color applied when a dragged card is hovering over this slot.
@export var highlight_color: Color = Color(1.3, 1.3, 1.3, 1.0)
## Duration for highlight and snap tween transitions.
@export_range(0.05, 0.5, 0.05) var feedback_duration: float = 0.15

## Currently assigned card in this slot, or null if vacant.
var card_in_slot: Card = null

## Whether this slot currently holds a card.
var is_occupied: bool:
	get:
		return card_in_slot != null

var _base_modulate: Color = Color.WHITE
var _base_scale: Vector2 = Vector2.ONE
var _feedback_tween: Tween

@onready var slot_image: Sprite2D = $CardSlotImage
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("card_slots")
	_base_modulate = slot_image.modulate
	_base_scale = scale

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _exit_tree() -> void:
	if _feedback_tween:
		_feedback_tween.kill()


## Checks whether this slot can receive the specified card.
func can_accept_card(_card: Card) -> bool:
	# Default implementation accepts any card; can be extended for slot types
	return true


## Docks a card into this slot and updates occupancy.
func assign_card(card: Card) -> void:
	var previous_card: Card = card_in_slot
	card_in_slot = card

	if previous_card and previous_card != card:
		card_unslotted.emit(previous_card, self)

	if card:
		card_slotted.emit(card, self)
		_play_dock_pulse()
		CardAudio.dock()


## Clears and returns the docked card from this slot.
func clear_card() -> Card:
	var removed_card: Card = card_in_slot
	card_in_slot = null
	if removed_card:
		card_unslotted.emit(removed_card, self)
	return removed_card


## Controls visual hover highlight on the slot.
func set_highlight(active: bool) -> void:
	if _feedback_tween:
		_feedback_tween.kill()

	_feedback_tween = create_tween().set_parallel()
	var target_mod: Color = highlight_color if active else _base_modulate
	var target_scale: Vector2 = _base_scale * (1.05 if active else 1.0)

	_feedback_tween.tween_property(slot_image, "modulate", target_mod, feedback_duration)
	_feedback_tween.tween_property(self, "scale", target_scale, feedback_duration)


## Plays a brief tactile pulse when a card snaps into the slot.
func _play_dock_pulse() -> void:
	if not is_inside_tree():
		return

	if _feedback_tween:
		_feedback_tween.kill()

	_feedback_tween = create_tween()
	_feedback_tween \
			.tween_property(self, "scale", _base_scale * 1.08, 0.08) \
			.set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT)
	_feedback_tween \
			.tween_property(self, "scale", _base_scale, 0.12) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)


func _on_mouse_entered() -> void:
	card_slot_entered.emit(self)


func _on_mouse_exited() -> void:
	card_slot_exited.emit(self)
