## Manual test scene for 3v3 Team Deathmatch
## MatchSession 위에 팀별 alive count / disconnect 디버그 UI를 추가한다.
##
## How to run (7 instances):
##   Option A - Terminal:
##     Instance 1 (Referee): ./godot --path . -- --mode=referee --game-mode=3v3
##     Instance 2-7 (Players): ./godot --path . (6 times)
##
##   Option B - Godot Editor:
##     1. Set "Run Multiple Instances" to 7
##     2. Set Main Run Args to "--mode=referee --game-mode=3v3"
##        (Editor Settings → Run → Main Run Args)
##     3. Press F6 on test_tdm.tscn
extends Node2D

const SERVER_PORT: int = 7777

var _session: MatchSession
var _ping_log: RichTextLabel
var _team_label: Label
var _is_server: bool = false


func _ready() -> void:
	_is_server = "--mode=referee" in OS.get_cmdline_user_args()

	_session = MatchSession.new()
	_session.name = "MatchSession"
	add_child(_session)

	_setup_debug_ui()


func _process(_delta: float) -> void:
	_update_team_label()


func _setup_debug_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vbox.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vbox.add_theme_constant_override("separation", 6)
	canvas.add_child(vbox)

	_team_label = Label.new()
	_team_label.text = "Team: ?"
	_team_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_team_label)

	var ping_btn := Button.new()
	ping_btn.text = "Ping!"
	ping_btn.custom_minimum_size = Vector2(160, 40)
	var err: int = ping_btn.pressed.connect(_on_ping_pressed)
	assert(err == OK, "TestTdm: failed to connect ping button: %d" % err)
	vbox.add_child(ping_btn)

	if not _is_server:
		var disc_btn := Button.new()
		disc_btn.text = "Force Disconnect"
		disc_btn.custom_minimum_size = Vector2(160, 40)
		err = disc_btn.pressed.connect(_on_force_disconnect_pressed)
		assert(err == OK, "TestTdm: failed to connect disconnect button: %d" % err)
		vbox.add_child(disc_btn)

		var reconn_btn := Button.new()
		reconn_btn.text = "Reconnect"
		reconn_btn.custom_minimum_size = Vector2(160, 40)
		err = reconn_btn.pressed.connect(_on_reconnect_pressed)
		assert(err == OK, "TestTdm: failed to connect reconnect button: %d" % err)
		vbox.add_child(reconn_btn)

	_ping_log = RichTextLabel.new()
	_ping_log.custom_minimum_size = Vector2(400, 120)
	_ping_log.bbcode_enabled = true
	_ping_log.scroll_following = true
	canvas.add_child(_ping_log)


func _update_team_label() -> void:
	if _team_label == null:
		return
	var team_id: int = _session.get_local_team_id()
	if team_id > 0:
		var team_name: String = "BLUE" if team_id == 1 else "RED"
		_team_label.text = "Team %d (%s)" % [team_id, team_name]
	elif _is_server:
		_team_label.text = "REFEREE"
	else:
		_team_label.text = "Team: waiting..."


# ============================================================
# Ping RPCs (test-only)
# ============================================================

@rpc("any_peer", "reliable")
func request_ping() -> void:
	broadcast_ping.rpc(multiplayer.get_remote_sender_id())


@rpc("authority", "call_local", "reliable")
func broadcast_ping(from_id: int) -> void:
	_add_log(from_id, "Peer %d pinged!" % from_id)


# ============================================================
# Debug UI callbacks
# ============================================================


func _on_ping_pressed() -> void:
	request_ping.rpc_id(1)


func _on_force_disconnect_pressed() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = null
	peer.close()
	_session._has_sent_move_input = false
	_session._last_sent_move_input = Vector2.ZERO
	_session._local_character = null
	_add_log(-1, "Forced disconnect. Reconnect within 10s to test grace period.")


func _on_reconnect_pressed() -> void:
	if multiplayer.multiplayer_peer != null:
		var status := multiplayer.multiplayer_peer.get_connection_status()
		if (
			status == MultiplayerPeer.CONNECTION_CONNECTING
			or status == MultiplayerPeer.CONNECTION_CONNECTED
		):
			_add_log(-1, "Already connecting or connected.")
			return
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client("localhost", SERVER_PORT) != OK:
		return
	_session._match_ended = false
	multiplayer.multiplayer_peer = peer
	_add_log(-1, "Reconnect requested.")


func _add_log(from_id: int, text: String) -> void:
	if _ping_log == null:
		return
	var color := "cyan" if from_id > 0 else "yellow"
	_ping_log.append_text("[color=%s]%s[/color]\n" % [color, text])
