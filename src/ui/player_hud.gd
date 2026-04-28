extends Control

@onready var _movement_joystick: VirtualJoystick = $"Virtual Joystick" as VirtualJoystick


func _ready() -> void:
	assert(_movement_joystick != null, "PlayerHud: Virtual Joystick child is missing")


func get_move_input() -> Vector2:
	if _movement_joystick != null and _movement_joystick.is_pressed:
		return _movement_joystick.output

	return Vector2.ZERO
