class_name CharacterBase

extends CharacterBody2D

const SPEED: float = 300.0

var _move_input: Vector2 = Vector2.ZERO


func set_move_input(input_vector: Vector2) -> void:
	_move_input = input_vector.limit_length()


func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not is_multiplayer_authority():
		return

	velocity = _move_input * SPEED

	move_and_slide()
