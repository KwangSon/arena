extends Control

signal skill_pressed(skill_idx: int)

const _BUTTON_SIZE: float = 80.0
const _BUTTON_SPACING: float = 30.0
const _BUTTON_Y_OFFSET: float = -120.0
const _BUTTON_X_OFFSET: float = -60.0

var _cooldown_remaining: Array[float] = [0.0, 0.0, 0.0]

@onready var _movement_joystick: VirtualJoystick = $"Virtual Joystick" as VirtualJoystick
@onready var _skill_1_button: TouchScreenButton = $HBoxContainer/Skill1Button as TouchScreenButton
@onready var _skill_2_button: TouchScreenButton = $HBoxContainer/Skill2Button as TouchScreenButton
@onready var _special_button: TouchScreenButton = $HBoxContainer/SpecialButton as TouchScreenButton
@onready var _resource_bars: VBoxContainer = $ResourceBars as VBoxContainer
@onready var _mp_bar: ProgressBar = $ResourceBars/MPBar as ProgressBar
@onready var _bp_bar: ProgressBar = $ResourceBars/BPBar as ProgressBar


func _ready() -> void:
	assert(_movement_joystick != null, "PlayerHud: Virtual Joystick child is missing")
	assert(_skill_1_button != null, "PlayerHud: Skill1Button is missing")
	assert(_skill_2_button != null, "PlayerHud: Skill2Button is missing")
	assert(_special_button != null, "PlayerHud: SpecialButton is missing")
	assert(_resource_bars != null, "PlayerHud: ResourceBars is missing")
	assert(_mp_bar != null, "PlayerHud: MPBar is missing")
	assert(_bp_bar != null, "PlayerHud: BPBar is missing")

	_resource_bars.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_resource_bars.custom_minimum_size = Vector2(160, 0)

	_mp_bar.show_percentage = false
	_mp_bar.custom_minimum_size = Vector2(160, 20)
	_bp_bar.show_percentage = false
	_bp_bar.custom_minimum_size = Vector2(160, 20)

	_position_skill_buttons()

	var err: int = _skill_1_button.pressed.connect(_on_skill_1_pressed)
	assert(err == OK, "PlayerHud: failed to connect Skill1Button.pressed: %d" % err)
	err = _skill_2_button.pressed.connect(_on_skill_2_pressed)
	assert(err == OK, "PlayerHud: failed to connect Skill2Button.pressed: %d" % err)
	err = _special_button.pressed.connect(_on_special_pressed)
	assert(err == OK, "PlayerHud: failed to connect SpecialButton.pressed: %d" % err)


func _position_skill_buttons() -> void:
	var step: float = _BUTTON_SIZE + _BUTTON_SPACING
	_skill_1_button.position = Vector2(_BUTTON_X_OFFSET + -step * 2.0, _BUTTON_Y_OFFSET)
	_skill_2_button.position = Vector2(_BUTTON_X_OFFSET + -step, _BUTTON_Y_OFFSET)
	_special_button.position = Vector2(_BUTTON_X_OFFSET, _BUTTON_Y_OFFSET)


func _process(delta: float) -> void:
	for i: int in range(3):
		if _cooldown_remaining[i] > 0.0:
			_cooldown_remaining[i] -= delta
			if _cooldown_remaining[i] <= 0.0:
				_cooldown_remaining[i] = 0.0
				_get_skill_button(i).visible = true


func start_skill_cooldown(skill_idx: int, duration: float) -> void:
	assert(skill_idx >= 0 and skill_idx <= 2, "PlayerHud: invalid skill_idx %d" % skill_idx)
	if duration <= 0.0:
		return
	_cooldown_remaining[skill_idx] = duration
	_get_skill_button(skill_idx).visible = false


func update_resources(mp: float, max_mp: float, bp: float, max_bp: float) -> void:
	_mp_bar.max_value = max_mp
	_mp_bar.value = mp
	_bp_bar.max_value = max_bp
	_bp_bar.value = bp


func get_move_input() -> Vector2:
	if _movement_joystick != null and _movement_joystick.is_pressed:
		return _movement_joystick.output

	return Vector2.ZERO


func _get_skill_button(skill_idx: int) -> TouchScreenButton:
	match skill_idx:
		0:
			return _skill_1_button
		1:
			return _skill_2_button
		_:
			return _special_button


func _on_skill_1_pressed() -> void:
	skill_pressed.emit(0)


func _on_skill_2_pressed() -> void:
	skill_pressed.emit(1)


func _on_special_pressed() -> void:
	skill_pressed.emit(2)
