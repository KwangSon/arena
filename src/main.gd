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
	ScreenManager.change_screen(ScreenManager.Screen.SPLASH)


func _start_referee() -> void:
	var session: MatchSession = MatchSession.new()
	session.name = "MatchSession"
	add_child(session)


func _on_game_ready(host: String, port: int, match_id: String, character_id: String) -> void:
	var session: MatchSession = MatchSession.new()
	session.name = "MatchSession"
	session._referee_host = host
	session._referee_port = port
	session._match_id = match_id
	session._character_id = character_id
	var err: int = session.match_completed.connect(_on_match_completed.bind(session))
	assert(err == OK, "Main: failed to connect match_completed: %d" % err)
	add_child(session)


func _on_match_completed(
	reason: String, loser_id: int, winner_id: int, session: MatchSession
) -> void:
	var local_id: int = multiplayer.get_unique_id()
	var won: bool = winner_id == local_id
	session.queue_free()
	ScreenManager.change_screen(
		ScreenManager.Screen.RESULT,
		{"won": won, "winner_id": winner_id, "loser_id": loser_id, "reason": reason}
	)
