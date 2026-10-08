class_name CardData
extends Resource

## Enum representing classic card suits.
enum Suit {
	NONE,
	CLUBS,
	DIAMONDS,
	HEARTS,
	SPADES,
}

## Enum representing classic card ranks.
enum Rank {
	NONE,
	TWO = 2,
	THREE = 3,
	FOUR = 4,
	FIVE = 5,
	SIX = 6,
	SEVEN = 7,
	EIGHT = 8,
	NINE = 9,
	TEN = 10,
	JACK = 11,
	QUEEN = 12,
	KING = 13,
	ACE = 14,
	JOKER = 15,
}

@export_group("Identity")
## Unique identifier for card lookup and serialization.
@export var id: StringName = &""
## Display title shown in inspector or tooltips.
@export var title: String = "Untitled Card"
## Classic card suit.
@export var suit: Suit = Suit.NONE
## Classic card rank.
@export var rank: Rank = Rank.NONE

@export_group("Gameplay")
## Numeric value for gameplay rules (e.g. blackjack, poker, war).
@export var value: int = 0

@export_group("Visuals")
## Artwork displayed on the card face.
@export var artwork: Texture2D = null


## Constructor for programmatic and Inspector instantiation.
func _init(
	p_id: StringName = &"",
	p_title: String = "Untitled Card",
	p_artwork: Texture2D = null,
	p_suit: Suit = Suit.NONE,
	p_rank: Rank = Rank.NONE,
	p_value: int = 0,
) -> void:
	id = p_id
	title = p_title
	artwork = p_artwork
	suit = p_suit
	rank = p_rank
	value = p_value


## Returns a concise debug representation.
func _to_string() -> String:
	return "[CardData:%s '%s' Suit:%s Rank:%s Value:%d]" % [
		id,
		title,
		Suit.keys()[suit] if suit in range(Suit.size()) else str(suit),
		Rank.keys()[rank] if rank in range(Rank.size()) else str(rank),
		value,
	]
