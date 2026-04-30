## Autoload — 화면 전환 관리자.
## add_child / queue_free 패턴으로 화면을 동적으로 교체한다.
## Referee 모드에서는 화면을 생성하지 않는다.
extends Node2D

## 화면 전환이 완료되었을 때 발생한다.
signal screen_changed(from_screen: Screen, to_screen: Screen)

## 로비에서 매치가 확정되어 게임 노드를 만들어야 할 때 발생한다.
signal game_ready(host: String, port: int, match_id: String)

enum Screen {
	NONE,
	LOBBY,
	GAME,
	RESULT,
}

## 현재 활성 화면 타입.
var current_screen: Screen = Screen.NONE

## 현재 활성 화면 노드. null이면 화면 없음.
var _current_screen_node: Node = null


## 화면을 전환한다.
## 기존 화면을 queue_free 한 뒤, 새 화면을 생성하여 add_child 한다.
## data 딕셔너리는 새 화면의 initialize() 메서드에 전달된다.
func change_screen(target: Screen, data: Dictionary = {}) -> void:
	assert(target != Screen.NONE, "ScreenManager: cannot change to NONE screen")

	var from: Screen = current_screen

	_cleanup_current_screen()

	var new_screen: Node = _create_screen(target)
	assert(new_screen != null, "ScreenManager: failed to create screen %d" % target)

	_current_screen_node = new_screen
	current_screen = target
	add_child(new_screen)

	if new_screen.has_method("initialize"):
		new_screen.initialize(data)

	_connect_screen_signals(new_screen, target)

	screen_changed.emit(from, target)


## 현재 화면 노드를 반환한다.
func get_current_screen_node() -> Node:
	return _current_screen_node


# ============================================================
# 화면 생성
# ============================================================


func _create_screen(target: Screen) -> Node:
	match target:
		Screen.LOBBY:
			return _create_lobby_screen()
		Screen.GAME:
			return _create_game_screen()
		Screen.RESULT:
			return _create_result_screen()
		_:
			assert(false, "ScreenManager: unknown screen type %d" % target)
			return null


func _create_lobby_screen() -> Node:
	var screen: LobbyScreen = LobbyScreen.new()
	screen.name = "LobbyScreen"
	return screen


func _create_game_screen() -> Node:
	# TODO: GameScreen 구현 후 교체
	var placeholder: Node2D = Node2D.new()
	placeholder.name = "GameScreen"
	return placeholder


func _create_result_screen() -> Node:
	# TODO: ResultScreen 구현 후 교체
	var placeholder: Node2D = Node2D.new()
	placeholder.name = "ResultScreen"
	return placeholder


# ============================================================
# 화면별 시그널 연결
# ============================================================


func _connect_screen_signals(screen_node: Node, screen_type: Screen) -> void:
	match screen_type:
		Screen.LOBBY:
			if screen_node.has_signal("match_found"):
				var err: int = screen_node.match_found.connect(_on_match_found)
				assert(err == OK, "ScreenManager: failed to connect match_found: %d" % err)
		Screen.RESULT:
			if screen_node.has_signal("return_to_lobby_requested"):
				var err: int = screen_node.return_to_lobby_requested.connect(
					_on_return_to_lobby_requested
				)
				assert(
					err == OK,
					"ScreenManager: failed to connect return_to_lobby_requested: %d" % err
				)


# ============================================================
# 시그널 콜백
# ============================================================


func _on_match_found(host: String, port: int, match_id: String) -> void:
	_cleanup_current_screen()
	game_ready.emit(host, port, match_id)


func _on_return_to_lobby_requested() -> void:
	change_screen(Screen.LOBBY)


# ============================================================
# 정리
# ============================================================


func _cleanup_current_screen() -> void:
	if _current_screen_node == null:
		return

	_disconnect_screen_signals(_current_screen_node, current_screen)

	if _current_screen_node.has_method("cleanup"):
		_current_screen_node.cleanup()

	_current_screen_node.queue_free()
	_current_screen_node = null
	current_screen = Screen.NONE


func _disconnect_screen_signals(screen_node: Node, screen_type: Screen) -> void:
	match screen_type:
		Screen.LOBBY:
			if screen_node.has_signal("match_found"):
				if screen_node.match_found.is_connected(_on_match_found):
					screen_node.match_found.disconnect(_on_match_found)
		Screen.RESULT:
			if screen_node.has_signal("return_to_lobby_requested"):
				if screen_node.return_to_lobby_requested.is_connected(
					_on_return_to_lobby_requested
				):
					screen_node.return_to_lobby_requested.disconnect(_on_return_to_lobby_requested)
