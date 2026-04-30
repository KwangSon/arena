class_name ResultScreen extends Node2D

signal return_to_lobby_requested

var _won: bool = false
var _reason: String = ""

var _canvas: CanvasLayer
var _result_label: Label
var _reason_label: Label
var _lobby_button: Button


func _ready() -> void:
	_setup_ui()


func initialize(data: Dictionary) -> void:
	_won = data.get("won", false)
	_reason = data.get("reason", "")
	_update_ui()


func _setup_ui() -> void:
	_canvas = CanvasLayer.new()
	add_child(_canvas)

	var center: Control = Control.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 48)
	vbox.add_child(_result_label)

	_reason_label = Label.new()
	_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_reason_label)

	_lobby_button = Button.new()
	_lobby_button.text = "Return to Lobby"
	_lobby_button.custom_minimum_size = Vector2(200, 50)
	var err: int = _lobby_button.pressed.connect(_on_lobby_pressed)
	assert(err == OK, "ResultScreen: failed to connect lobby button: %d" % err)
	vbox.add_child(_lobby_button)

	_update_ui()


func _update_ui() -> void:
	if _result_label == null:
		return
	_result_label.text = "Victory!" if _won else "Defeat"
	_result_label.modulate = Color.YELLOW if _won else Color.RED
	_reason_label.text = _reason


func _on_lobby_pressed() -> void:
	return_to_lobby_requested.emit()
