## 앱 진입점. 모드에 따라 Player / Referee 흐름을 분기한다.
extends Node2D

var _is_referee: bool = false


func _ready() -> void:
	_is_referee = "--mode=referee" in OS.get_cmdline_args()

	if _is_referee:
		_start_referee()
	else:
		_start_player()


func _start_player() -> void:
	ScreenManager.change_screen(ScreenManager.Screen.LOBBY)


func _start_referee() -> void:
	# TODO: RefereeManager 초기화
	print("[Main] Referee mode — no screens")
