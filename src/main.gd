## 앱 진입점. 모드에 따라 Player / Referee 흐름을 분기한다.
extends Node2D

var _is_referee: bool = false


func _ready() -> void:
	_is_referee = "--mode=referee" in OS.get_cmdline_user_args()

	if _is_referee:
		_start_referee()
	else:
		_start_player()


func _start_player() -> void:
	var err: int = ScreenManager.game_ready.connect(_on_game_ready)
	assert(err == OK, "Main: failed to connect game_ready: %d" % err)
	ScreenManager.change_screen(ScreenManager.Screen.LOBBY)


func _start_referee() -> void:
	var session: MatchSession = MatchSession.new()
	session.name = "MatchSession"
	add_child(session)


func _on_game_ready(host: String, port: int, match_id: String) -> void:
	var session: MatchSession = MatchSession.new()
	session.name = "MatchSession"
	session._referee_host = host
	session._referee_port = port
	session._match_id = match_id
	add_child(session)
