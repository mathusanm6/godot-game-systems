class_name CardData
extends Resource

## Enum representing the strategic category of the card.
enum CardType {
	ATTACK,
	SKILL,
	POWER,
}

@export_group("Identity")
## Unique identifier for card lookup and serialization.
@export var id: StringName = &""
## Display title shown on the card banner.
@export var title: String = "Untitled Card"
## Flavor or gameplay effect description.
@export_multiline var description: String = ""
## Strategic classification.
@export var card_type: CardType = CardType.ATTACK

@export_group("Stats")
## Energy / mana cost required to play.
@export_range(0, 10, 1) var cost: int = 1
## Base offensive power or damage value.
@export_range(0, 99, 1) var attack: int = 0
## Base defensive block or shield value.
@export_range(0, 99, 1) var defense: int = 0

@export_group("Visuals")
## Artwork displayed in the center illustration window.
@export var artwork: Texture2D = null
## Accent tint applied to card frame/border.
@export var frame_color: Color = Color(0.85, 0.85, 0.85, 1.0)


## Parameterless constructor for safe Inspector instantiation.
func _init(
	p_id: StringName = &"",
	p_title: String = "Untitled Card",
	p_cost: int = 1,
	p_card_type: CardType = CardType.ATTACK
) -> void:
	id = p_id
	title = p_title
	cost = p_cost
	card_type = p_card_type


## Updates dynamic stats and emits changed signal for reactive UI updates.
func update_stats(new_attack: int, new_defense: int) -> void:
	if attack != new_attack or defense != new_defense:
		attack = new_attack
		defense = new_defense
		emit_changed()


## Returns a concise debug representation.
func _to_string() -> String:
	return "[CardData:%s '%s' Cost:%d Type:%s]" % [id, title, cost, CardType.keys()[card_type]]
