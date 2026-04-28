extends Control

signal skill_pressed(skill_idx: int)

@onready var _movement_joystick: VirtualJoystick = $"Virtual Joystick" as VirtualJoystick
@onready var _skill_1_button: TouchScreenButton = $HBoxContainer/Skill1Button as TouchScreenButton
@onready var _skill_2_button: TouchScreenButton = $HBoxContainer/Skill2Button as TouchScreenButton
@onready var _special_button: TouchScreenButton = $HBoxContainer/SpecialButton as TouchScreenButton


func _ready() -> void:
	assert(_movement_joystick != null, "PlayerHud: Virtual Joystick child is missing")
	assert(_skill_1_button != null, "PlayerHud: Skill1Button is missing")
	assert(_skill_2_button != null, "PlayerHud: Skill2Button is missing")
	assert(_special_button != null, "PlayerHud: SpecialButton is missing")

	var err: int = _skill_1_button.pressed.connect(_on_skill_1_pressed)
	assert(err == OK, "PlayerHud: failed to connect Skill1Button.pressed: %d" % err)
	err = _skill_2_button.pressed.connect(_on_skill_2_pressed)
	assert(err == OK, "PlayerHud: failed to connect Skill2Button.pressed: %d" % err)
	err = _special_button.pressed.connect(_on_special_pressed)
	assert(err == OK, "PlayerHud: failed to connect SpecialButton.pressed: %d" % err)


func get_move_input() -> Vector2:
	if _movement_joystick != null and _movement_joystick.is_pressed:
		return _movement_joystick.output

	return Vector2.ZERO


func _on_skill_1_pressed() -> void:
	skill_pressed.emit(0)


func _on_skill_2_pressed() -> void:
	skill_pressed.emit(1)


func _on_special_pressed() -> void:
	skill_pressed.emit(2)
