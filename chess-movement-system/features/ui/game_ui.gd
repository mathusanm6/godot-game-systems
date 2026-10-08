class_name GameUI
extends Control

## GameUI for Chess Movement System
## Clean, decoupled HUD displaying current tile coordinate, algebraic notation,
## step counter, and quick control guide with reset trigger.

signal reset_requested

@onready var square_label: Label = %SquareLabel if has_node("%SquareLabel") else null
@onready var coords_label: Label = %CoordsLabel if has_node("%CoordsLabel") else null
@onready var steps_label: Label = %StepsLabel if has_node("%StepsLabel") else null
@onready var reset_button: Button = %ResetButton if has_node("%ResetButton") else null

func _ready() -> void:
	if reset_button != null and not reset_button.pressed.is_connected(_on_reset_pressed):
		reset_button.pressed.connect(_on_reset_pressed)

## Updates the HUD position and step metrics
func update_tile_info(tile: Vector2i, notation: String, steps: int) -> void:
	if square_label != null:
		square_label.text = "Square: %s" % notation
	if coords_label != null:
		coords_label.text = "Grid: (%d, %d)" % [tile.x, tile.y]
	if steps_label != null:
		steps_label.text = "Steps: %d" % steps

func _on_reset_pressed() -> void:
	reset_requested.emit()
