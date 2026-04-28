extends CharacterBody2D

const SPEED: float = 300.0


func _physics_process(_delta: float) -> void:
	var input_direction: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_direction * SPEED

	move_and_slide()
