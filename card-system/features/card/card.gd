class_name Card
extends Area2D

## Emitted when the card is clicked via left mouse button.
signal card_clicked(card: Card)
## Emitted when pointer enters this card's bounding area.
signal card_hovered(card: Card)
## Emitted when pointer exits this card's bounding area.
signal card_unhovered(card: Card)
## Emitted when dragging starts.
signal drag_started(card: Card)
## Emitted when dragging finishes.
signal drag_ended(card: Card)
## Emitted when the logical state changes.
signal state_changed(card: Card, new_state: State)

enum State {
	IDLE,
	HOVERED,
	DRAGGING,
	SLOTTED,
	RETURNING,
}

@export_group("Card Data")
## Data resource defining identity, cost, and gameplay attributes.
@export var card_data: CardData:
	set(value):
		card_data = value
		if is_node_ready():
			_update_card_display()

@export_group("Motion & Tilt")
## Maximum dynamic tilt angle in degrees caused by mouse movement velocity.
@export_range(5.0, 45.0, 1.0) var max_tilt_deg: float = 18.0
## Sensitivity factor mapping horizontal drag velocity to tilt rotation.
@export_range(0.01, 0.2, 0.005) var tilt_responsiveness: float = 0.05
## Exponential smoothing speed for tilt settling.
@export_range(1.0, 30.0, 1.0) var tilt_recovery_speed: float = 15.0

@export_group("Hover Settings")
## Perspective shader tilt angle applied while hovered (0.0 keeps 2D UI perfectly aligned).
@export_range(0.0, 30.0, 1.0) var hover_tilt_deg: float = 0.0
## Upward vertical displacement when hovered.
@export_range(0.0, 60.0, 2.0) var hover_lift: float = 24.0
## Uniform scale multiplier when hovered.
@export_range(1.0, 1.4, 0.01) var hover_scale: float = 1.04
## Duration of hover transitions in seconds.
@export_range(0.05, 0.4, 0.01) var hover_duration: float = 0.18

## Public state
var current_state: State = State.IDLE:
	set(value):
		if current_state != value:
			current_state = value
			state_changed.emit(self, current_state)

var initial_position: Vector2 = Vector2.ZERO
var position_before_drag: Vector2 = Vector2.ZERO
var resting_z_index: int = 0
var drag_pivot: Vector2 = Vector2.ZERO
var drag_offset: Vector2 = Vector2.ZERO
var card_slot: CardSlot = null
var hand_position: Vector2 = Vector2.ZERO
var hand_rotation: float = 0.0
var card_hand: Node = null

## Convenience query accessors
var is_dragging: bool:
	get:
		return current_state == State.DRAGGING

var is_hovered: bool:
	get:
		return current_state == State.HOVERED or _is_hover_flag

var is_card_on_card_slot: bool:
	get:
		return card_slot != null

# Internal variables
var _last_pos_x: float = 0.0
var _target_rotation: float = 0.0
var _is_hover_flag: bool = false
var _base_card_image_pos: Vector2 = Vector2.ZERO
var _base_card_image_scale: Vector2 = Vector2.ONE
var _hover_tween: Tween
var _return_tween: Tween

@onready var card_image: Sprite2D = %CardImage
@onready var title_label: Label = get_node_or_null("%TitleLabel")
@onready var cost_label: Label = get_node_or_null("%CostLabel")
@onready var description_label: Label = get_node_or_null("%DescriptionLabel")
@onready var ui_overlay: Control = get_node_or_null("%UIOverlay")


func _ready() -> void:
	add_to_group("cards")

	initial_position = position
	position_before_drag = position
	_last_pos_x = global_position.x
	_base_card_image_pos = card_image.position
	_base_card_image_scale = card_image.scale

	if card_image.material:
		card_image.material = card_image.material.duplicate()

	_update_card_display()


func _exit_tree() -> void:
	_kill_tweens()


func _process(delta: float) -> void:
	if is_dragging:
		var velocity_x: float = global_position.x - _last_pos_x
		_last_pos_x = global_position.x

		var max_tilt_rad: float = deg_to_rad(max_tilt_deg)
		var tilt_dir: float = -1.0 if drag_pivot.y > 25.0 else 1.0
		_target_rotation = clampf(
			velocity_x * tilt_responsiveness * tilt_dir,
			-max_tilt_rad,
			max_tilt_rad
		)
	else:
		_target_rotation = 0.0

	# Smoothly interpolate rotation toward target
	card_image.rotation = lerp_angle(
		card_image.rotation,
		_target_rotation,
		1.0 - exp(-tilt_recovery_speed * delta)
	)

	var is_lifted: bool = _is_hover_flag or is_dragging
	var hover_target: Vector2 = _base_card_image_pos + (
		Vector2(0, -hover_lift) if is_lifted else Vector2.ZERO
	)

	if is_dragging or absf(card_image.rotation) > 0.001:
		card_image.position = drag_pivot - (drag_pivot - hover_target).rotated(card_image.rotation)
	else:
		drag_pivot = Vector2.ZERO
		if not _hover_tween or not _hover_tween.is_running():
			card_image.position = hover_target

	if ui_overlay:
		var half_size: Vector2 = ui_overlay.size / 2.0
		ui_overlay.position = card_image.position - half_size
		ui_overlay.rotation = card_image.rotation
		if _base_card_image_scale.x > 0.0 and _base_card_image_scale.y > 0.0:
			ui_overlay.scale = card_image.scale / _base_card_image_scale


## Initiates dragging interaction.
func start_drag() -> void:
	if _return_tween:
		_return_tween.kill()

	current_state = State.DRAGGING
	position_before_drag = global_position
	_last_pos_x = global_position.x
	rotation = 0.0
	if is_inside_tree():
		drag_pivot = get_local_mouse_position()
		drag_offset = get_global_mouse_position() - global_position
	drag_started.emit(self)


## Concludes dragging interaction.
func stop_drag() -> void:
	drag_offset = Vector2.ZERO
	if card_slot:
		current_state = State.SLOTTED
	else:
		current_state = State.IDLE
	drag_ended.emit(self)


## Smoothly tweens card to target position and rotation (e.g. back to hand or table).
func return_to_position(target_pos: Vector2, target_rot: float = 0.0, duration: float = 0.28) -> void:
	if _return_tween:
		_return_tween.kill()

	set_hovered(false)
	current_state = State.RETURNING
	z_index = 100

	_return_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_return_tween.tween_property(self, "position", target_pos, duration)
	_return_tween.tween_property(self, "rotation", target_rot, duration)
	_return_tween.chain().tween_callback(_on_return_completed)


## Smoothly docks card into a slot position.
func snap_to_slot(target_slot: CardSlot, target_pos: Vector2 = Vector2.INF, duration: float = 0.2) -> void:
	if _return_tween:
		_return_tween.kill()

	stop_drag()
	card_slot = target_slot
	current_state = State.SLOTTED
	set_hovered(false)

	var final_pos: Vector2 = target_pos
	if final_pos == Vector2.INF:
		if target_slot:
			var parent_node: Node2D = get_parent() as Node2D
			final_pos = parent_node.to_local(target_slot.global_position) if parent_node else target_slot.global_position
		else:
			final_pos = position

	_return_tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_return_tween.tween_property(self, "position", final_pos, duration)
	_return_tween.tween_property(self, "rotation", 0.0, duration)
	_return_tween.chain().tween_callback(func() -> void:
		z_index = resting_z_index
	)


## Updates hover visual state (lift, scale, shader perspective, and hand straightening).
func set_hovered(on: bool) -> void:
	_is_hover_flag = on
	if not is_dragging and current_state != State.RETURNING:
		current_state = State.HOVERED if on else (State.SLOTTED if card_slot else State.IDLE)

	if not is_inside_tree() or not card_image:
		return

	if _hover_tween:
		_hover_tween.kill()

	_hover_tween = create_tween().set_parallel()
	if on:
		_hover_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_hover_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var target_pos: Vector2 = _base_card_image_pos + (Vector2(0, -hover_lift) if on else Vector2.ZERO)
	var target_scale: Vector2 = _base_card_image_scale * (hover_scale if on else 1.0)
	var target_tilt: float = hover_tilt_deg if on else 0.0

	if not is_dragging:
		_hover_tween.tween_property(card_image, "position", target_pos, hover_duration)
		# Straighten card rotation when hovered in hand, restore curved tilt when unhovered
		var target_rot: float = 0.0 if (on or card_slot) else hand_rotation
		_hover_tween.tween_property(self, "rotation", target_rot, hover_duration)

	_hover_tween.tween_property(card_image, "scale", target_scale, hover_duration)

	if card_image.material:
		_hover_tween.tween_property(
			card_image.material,
			"shader_parameter/tilt_deg",
			target_tilt,
			hover_duration
		)

	z_index = 100 if on else resting_z_index


## Updates presentation labels and styling from CardData.
func _update_card_display() -> void:
	if not is_inside_tree():
		return

	if card_data:
		if title_label:
			title_label.text = card_data.title
		if cost_label:
			cost_label.text = str(card_data.cost)
		if description_label:
			description_label.text = card_data.description
		if card_data.artwork and card_image:
			card_image.texture = card_data.artwork
		if card_data.frame_color != Color.WHITE:
			card_image.modulate = card_data.frame_color
	else:
		if title_label:
			title_label.text = name
		if cost_label:
			cost_label.text = "1"
		if description_label:
			description_label.text = ""


func _kill_tweens() -> void:
	if _hover_tween:
		_hover_tween.kill()
	if _return_tween:
		_return_tween.kill()


func _on_return_completed() -> void:
	z_index = resting_z_index
	current_state = State.SLOTTED if card_slot else State.IDLE


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			if not is_dragging:
				drag_pivot = get_local_mouse_position()
				drag_offset = get_global_mouse_position() - global_position
				card_clicked.emit(self)


func _mouse_enter() -> void:
	card_hovered.emit(self)


func _mouse_exit() -> void:
	card_unhovered.emit(self)
