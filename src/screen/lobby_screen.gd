## 로비 화면. 매치 시작 버튼만 있는 최소 구현.
class_name LobbyScreen
extends Node2D

signal match_requested

var _canvas: CanvasLayer
var _start_button: Button


func _ready() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "LobbyCanvas"
	add_child(_canvas)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(center)

	_start_button = Button.new()
	_start_button.text = "Start Match"
	_start_button.custom_minimum_size = Vector2(200, 60)
	center.add_child(_start_button)

	var err: int = _start_button.pressed.connect(_on_start_pressed)
	assert(err == OK, "LobbyScreen: failed to connect start button: %d" % err)


func _on_start_pressed() -> void:
	match_requested.emit()
