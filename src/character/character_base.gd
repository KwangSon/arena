class_name CharacterBase

extends CharacterBody2D

const SPEED: float = 300.0

var _move_input: Vector2 = Vector2.ZERO
var _uses_external_input: bool = false


func set_move_input(input_vector: Vector2) -> void:
	_uses_external_input = true
	_move_input = input_vector.limit_length()


func _physics_process(_delta: float) -> void:
	if not _uses_external_input:
		_move_input = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = _move_input * SPEED

	move_and_slide()
