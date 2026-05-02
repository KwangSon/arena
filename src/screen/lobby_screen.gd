## 로비 화면. gserver /queue에 진입하고 referee 주소를 받아 match_found를 발생시킨다.
class_name LobbyScreen extends Node2D

signal match_found(host: String, port: int, match_id: String)
signal shop_requested
signal deck_requested

const POLL_INTERVAL_SEC: float = 2.0

var _player_id: String = ""
var _game_mode: String = "1v1"
var _canvas: CanvasLayer
var _start_button: Button
var _status_label: Label
var _poll_timer: Timer
var _server_ip_input: LineEdit


func _ready() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "LobbyCanvas"
	add_child(_canvas)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(center)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	var ip_hbox := HBoxContainer.new()
	ip_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ip_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(ip_hbox)

	var ip_label := Label.new()
	ip_label.text = "Server IP:"
	ip_hbox.add_child(ip_label)

	_server_ip_input = LineEdit.new()
	_server_ip_input.text = "localhost"
	_server_ip_input.custom_minimum_size = Vector2(150, 40)
	ip_hbox.add_child(_server_ip_input)

	var match_hbox := HBoxContainer.new()
	match_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	match_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(match_hbox)

	_start_button = Button.new()
	_start_button.text = "1:1 매치"
	_start_button.custom_minimum_size = Vector2(180, 64)
	match_hbox.add_child(_start_button)

	var tdm_button := Button.new()
	tdm_button.text = "3:3 매치"
	tdm_button.custom_minimum_size = Vector2(180, 64)
	match_hbox.add_child(tdm_button)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

	var nav_hbox := HBoxContainer.new()
	nav_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(nav_hbox)

	var shop_btn := Button.new()
	shop_btn.text = "상점"
	shop_btn.custom_minimum_size = Vector2(100, 50)
	nav_hbox.add_child(shop_btn)

	var deck_btn := Button.new()
	deck_btn.text = "캐릭터"
	deck_btn.custom_minimum_size = Vector2(100, 50)
	nav_hbox.add_child(deck_btn)

	var err: int = _start_button.pressed.connect(
		_on_match_pressed.bind("1v1")
	)
	assert(err == OK, "LobbyScreen: failed to connect 1v1 btn: %d" % err)
	err = tdm_button.pressed.connect(
		_on_match_pressed.bind("3v3")
	)
	assert(err == OK, "LobbyScreen: failed to connect 3v3 btn: %d" % err)
	err = shop_btn.pressed.connect(shop_requested.emit)
	assert(err == OK, "LobbyScreen: failed to connect shop button: %d" % err)
	err = deck_btn.pressed.connect(deck_requested.emit)
	assert(err == OK, "LobbyScreen: failed to connect deck button: %d" % err)


func _get_gserver_url() -> String:
	var ip: String = _server_ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "localhost"
	return "http://%s:8080" % ip


func _on_match_pressed(mode: String) -> void:
	_game_mode = mode
	_player_id = "p%d" % randi_range(100000, 999999)
	_start_button.disabled = true
	_status_label.text = "큐 진입 중... (%s)" % mode
	_send_queue_request()


func _send_queue_request() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request_completed.connect(_on_queue_response.bind(http))
	assert(err == OK, "LobbyScreen: failed to connect queue http: %d" % err)
	(
		http
		. request(
			"%s/queue" % _get_gserver_url(),
			["Content-Type: application/json"],
			HTTPClient.METHOD_POST,
			JSON.stringify(
				{"player_id": _player_id, "game_mode": _game_mode}
			),
		)
	)


func _start_poll_timer() -> void:
	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_INTERVAL_SEC
	_poll_timer.autostart = true
	add_child(_poll_timer)
	var err: int = _poll_timer.timeout.connect(_poll_status)
	assert(err == OK, "LobbyScreen: failed to connect poll timer: %d" % err)


func _poll_status() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request_completed.connect(_on_poll_response.bind(http))
	assert(err == OK, "LobbyScreen: failed to connect poll http: %d" % err)
	http.request("%s/queue/%s/status" % [_get_gserver_url(), _player_id])


func _on_queue_response(
	_result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest
) -> void:
	http.queue_free()
	if code != 200:
		_status_label.text = "서버 연결 실패 (응답: %d)" % code
		_start_button.disabled = false
		return
	_status_label.text = "상대방 대기 중..."
	_start_poll_timer()


func _on_poll_response(
	_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest
) -> void:
	http.queue_free()
	if code == 404:
		return
	if code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		return
	if data.get("status") == "matched":
		_poll_timer.stop()
		_status_label.text = "매치 찾음! 연결 중..."
		(
			match_found
			. emit(
				str(data.get("referee_host", "localhost")),
				int(data.get("referee_port", 7800)),
				str(data.get("match_id", "")),
			)
		)
