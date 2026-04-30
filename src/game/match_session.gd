## 매치 세션. referee와 client 모두 이 노드를 같은 경로에 추가해 RPC 경로를 일치시킨다.
class_name MatchSession extends Node2D

signal match_completed(reason: String, loser_id: int, winner_id: int)

const PLAYER_HUD_SCENE: PackedScene = preload("res://src/ui/player_hud.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://src/combat/projectile.tscn")
const REFEREE_PEER_ID: int = 1
const MAX_CLIENTS: int = 8

# 설정값 — referee: _ready()에서 CLI 파싱, client: add_child 전에 부모가 설정
var _is_server: bool = false
var _referee_host: String = "localhost"
var _referee_port: int = 7777
var _match_id: String = ""
var _orchestrator_url: String = ""
var _character_id: String = ""

var _match_ended: bool = false

# Scene nodes
var _spawner: MultiplayerSpawner
var _character_container: Node2D
var _projectile_spawner: MultiplayerSpawner
var _projectile_container: Node2D
var _camera: Camera2D
var _local_character: CharacterBase

# Subsystems
var _referee_manager: RefereeManager
var _dash_detector: DashDetector

# Client movement dedup
var _last_sent_move_input: Vector2 = Vector2.ZERO
var _has_sent_move_input: bool = false

# UI
var _canvas: CanvasLayer
var _info_label: Label
var _log_label: RichTextLabel
var _player_hud: Control


func _ready() -> void:
	_is_server = "--mode=referee" in OS.get_cmdline_user_args()
	if _is_server:
		_parse_referee_args()
	Input.set_emulate_touch_from_mouse(true)
	Input.set_emulate_mouse_from_touch(false)
	_setup_scene()
	if _is_server:
		_setup_referee()
	else:
		_setup_client()
	_setup_network()
	_update_info()


func _parse_referee_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			_referee_port = arg.split("=")[1].to_int()
		elif arg.begins_with("--match-id="):
			_match_id = arg.split("=")[1]
		elif arg.begins_with("--orchestrator-url="):
			_orchestrator_url = arg.split("=")[1]
	assert(_referee_port > 0, "MatchSession: referee requires --port=<number>")


func _process(_delta: float) -> void:
	if _match_ended or _is_server or _camera == null:
		return
	if _local_character == null:
		_local_character = _find_local_character()
		if _local_character != null:
			_local_character.show_facing_indicator()
	if _local_character == null:
		return
	_camera.global_position = _local_character.global_position
	if _player_hud != null:
		(
			_player_hud
			. update_resources(
				_local_character.mp,
				_local_character.max_mp,
				_local_character.bp,
				_local_character.max_bp,
			)
		)


func _physics_process(delta: float) -> void:
	if _match_ended:
		return
	if _is_server:
		_referee_manager.simulate_movement(delta)
		_referee_manager.process_disconnect_timeouts(_match_ended)
		return
	_submit_local_move_input()
	_detect_joystick_dash()


# ============================================================
# Setup
# ============================================================


func _setup_scene() -> void:
	_canvas = CanvasLayer.new()
	add_child(_canvas)

	_character_container = Node2D.new()
	_character_container.name = "CharacterContainer"
	add_child(_character_container)

	if not _is_server:
		_camera = Camera2D.new()
		_camera.name = "LocalCamera"
		_camera.enabled = true
		add_child(_camera)

	_spawner = MultiplayerSpawner.new()
	_spawner.name = "CharacterSpawner"
	add_child(_spawner)
	_spawner.spawn_path = _character_container.get_path()
	_spawner.spawn_function = _spawn_character_node

	_projectile_container = Node2D.new()
	_projectile_container.name = "ProjectileContainer"
	add_child(_projectile_container)

	_projectile_spawner = MultiplayerSpawner.new()
	_projectile_spawner.name = "ProjectileSpawner"
	add_child(_projectile_spawner)
	_projectile_spawner.spawn_path = _projectile_container.get_path()
	_projectile_spawner.spawn_function = _spawn_projectile_node

	var info_panel := PanelContainer.new()
	info_panel.custom_minimum_size = Vector2(320, 50)
	_canvas.add_child(info_panel)
	_info_label = Label.new()
	info_panel.add_child(_info_label)

	_log_label = RichTextLabel.new()
	_log_label.custom_minimum_size = Vector2(400, 100)
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_canvas.add_child(_log_label)


func _setup_referee() -> void:
	_referee_manager = RefereeManager.new()
	_referee_manager.name = "RefereeManager"
	add_child(_referee_manager)
	(
		_referee_manager
		. setup(
			_character_container,
			_spawner,
			_projectile_spawner,
			_match_id,
			_orchestrator_url,
			_referee_port,
		)
	)
	var err: int = _referee_manager.hit_occurred.connect(_on_hit_occurred)
	assert(err == OK, "MatchSession: failed to connect hit_occurred: %d" % err)
	err = _referee_manager.match_result_ready.connect(_on_referee_match_result)
	assert(err == OK, "MatchSession: failed to connect match_result_ready: %d" % err)


func _setup_client() -> void:
	_dash_detector = DashDetector.new()
	var err: int = _dash_detector.dash_requested.connect(_on_dash_requested)
	assert(err == OK, "MatchSession: failed to connect dash_requested: %d" % err)
	_ensure_player_hud()


# ============================================================
# Network
# ============================================================


func _setup_network() -> void:
	var peer := ENetMultiplayerPeer.new()
	if _is_server:
		var error: int = peer.create_server(_referee_port, MAX_CLIENTS)
		if error != OK:
			push_error(
				(
					"[MatchSession] Failed to create ENet server on port %d: %d"
					% [_referee_port, error]
				)
			)
			return
		print("[MatchSession] Referee server listening on port %d" % _referee_port)
	else:
		var error: int = peer.create_client(_referee_host, _referee_port)
		if error != OK:
			push_error(
				(
					"[MatchSession] Failed to connect to %s:%d: %d"
					% [_referee_host, _referee_port, error]
				)
			)
			return
		print("[MatchSession] Connecting to %s:%d..." % [_referee_host, _referee_port])

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ============================================================
# Peer events
# ============================================================


func _on_peer_connected(id: int) -> void:
	print("[MatchSession] Peer connected: %d" % id)
	if _is_server:
		_referee_manager.on_peer_connected(id)
	_update_info()


func _on_peer_disconnected(id: int) -> void:
	print("[MatchSession] Peer disconnected: %d" % id)
	if _is_server:
		_referee_manager.on_peer_disconnected(id)
	_update_info()


func _on_connected_to_server() -> void:
	print("[MatchSession] Connected to referee — my id: %d" % multiplayer.get_unique_id())
	_ensure_player_hud()
	_update_info()
	request_character.rpc_id(REFEREE_PEER_ID, _character_id, PlayerData.get_equipped_card_ids())


func _on_connection_failed() -> void:
	push_error("[MatchSession] Connection to referee failed")
	_update_info()


func _on_server_disconnected() -> void:
	push_error("[MatchSession] Referee disconnected")
	_match_ended = true
	_add_log(-1, "Referee disconnected. Match ended.")


# ============================================================
# RPCs
# ============================================================

@rpc("any_peer", "reliable")
func request_character(character_id: String, equipped_card_ids: Array[String] = []) -> void:
	assert(_is_server, "MatchSession.request_character must only run on referee")
	_referee_manager.set_character_choice(
		multiplayer.get_remote_sender_id(), character_id, equipped_card_ids
	)


@rpc("any_peer", "reliable")
func request_dash() -> void:
	assert(_is_server, "MatchSession.request_dash must only run on referee")
	_referee_manager.set_dashing(multiplayer.get_remote_sender_id())


@rpc("any_peer", "unreliable_ordered")
func submit_move_input(input_vector: Vector2) -> void:
	assert(_is_server, "MatchSession.submit_move_input must only run on referee")
	_referee_manager.set_move_input(multiplayer.get_remote_sender_id(), input_vector)


@rpc("any_peer", "reliable")
func request_skill(skill_idx: int, direction: Vector2) -> void:
	assert(_is_server, "MatchSession.request_skill must only run on referee")
	assert(skill_idx >= 0 and skill_idx <= 2, "request_skill: invalid idx %d" % skill_idx)
	_referee_manager.execute_skill(multiplayer.get_remote_sender_id(), skill_idx, direction)


@rpc("authority", "call_local", "reliable")
func broadcast_hit_result(attacker_id: int, target_id: int, damage: int, skill_id: String) -> void:
	_add_log(-1, "Peer %d hit peer %d — %d dmg [%s]" % [attacker_id, target_id, damage, skill_id])


@rpc("authority", "call_local", "reliable")
func broadcast_match_ended(reason: String, loser_id: int, winner_id: int) -> void:
	_match_ended = true
	var msg := "Match over: %s" % reason
	if loser_id > 0:
		msg += "  loser=%d" % loser_id
	if winner_id > 0:
		msg += "  winner=%d" % winner_id
	print("[MatchSession] %s" % msg)
	_add_log(-1, msg)
	if not _is_server:
		match_completed.emit(reason, loser_id, winner_id)


# ============================================================
# Signal callbacks
# ============================================================


func _on_hit_occurred(attacker_id: int, target_id: int, damage: int, skill_id: String) -> void:
	broadcast_hit_result.rpc(attacker_id, target_id, damage, skill_id)


func _on_referee_match_result(_winner_team: int, loser_id: int, winner_id: int) -> void:
	if _match_ended:
		return
	broadcast_match_ended.rpc("player eliminated", loser_id, winner_id)


func _on_dash_requested() -> void:
	request_dash.rpc_id(REFEREE_PEER_ID)


# ============================================================
# Movement & Input (client)
# ============================================================


func _submit_local_move_input() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if multiplayer.get_unique_id() <= 0:
		return
	var input_vector: Vector2 = _get_local_move_input()
	if _local_character != null:
		_local_character.set_move_input(input_vector)
	if _has_sent_move_input and input_vector == _last_sent_move_input:
		return
	_has_sent_move_input = true
	_last_sent_move_input = input_vector
	submit_move_input.rpc_id(REFEREE_PEER_ID, input_vector)


func _detect_joystick_dash() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_dash_detector.update(_get_local_move_input() != Vector2.ZERO)


func _get_local_move_input() -> Vector2:
	if _player_hud != null and _player_hud.has_method("get_move_input"):
		var hud_input: Variant = _player_hud.call("get_move_input")
		assert(hud_input is Vector2, "MatchSession: PlayerHud.get_move_input must return Vector2")
		var move_input: Vector2 = hud_input
		if move_input != Vector2.ZERO:
			return move_input
	return Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")


# ============================================================
# Helpers
# ============================================================


func _spawn_projectile_node(data: Variant) -> Node:
	assert(data is Dictionary, "MatchSession: projectile spawn data must be Dictionary")
	var spawn_data: Dictionary = data
	var projectile: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	assert(projectile != null, "MatchSession: failed to instantiate Projectile scene")
	projectile.attacker_id = spawn_data["attacker_id"]
	projectile.damage = spawn_data["damage"]
	projectile.skill_id = spawn_data["skill_id"]
	projectile.position = spawn_data["position"]
	projectile.setup(spawn_data["direction"], spawn_data["speed"], spawn_data["range"])
	projectile.collision_layer = 0
	projectile.collision_mask = spawn_data.get("collision_mask", 1)
	projectile.set_multiplayer_authority(REFEREE_PEER_ID)
	_add_projectile_synchronizer(projectile)
	return projectile


func _add_projectile_synchronizer(projectile: Node2D) -> void:
	var synchronizer: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = "StateSynchronizer"
	synchronizer.root_path = NodePath("..")
	synchronizer.replication_interval = 0.0
	synchronizer.delta_interval = 0.0
	synchronizer.set_multiplayer_authority(REFEREE_PEER_ID)
	var replication_config: SceneReplicationConfig = SceneReplicationConfig.new()
	var pos_path := NodePath(".:position")
	replication_config.add_property(pos_path)
	replication_config.property_set_spawn(pos_path, true)
	replication_config.property_set_replication_mode(
		pos_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS
	)
	synchronizer.replication_config = replication_config
	projectile.add_child(synchronizer, true)


func _spawn_character_node(data: Variant) -> Node:
	assert(data is Dictionary, "MatchSession: spawn data must be Dictionary")
	return CharacterSpawner.create_node(data, REFEREE_PEER_ID)


func _find_local_character() -> CharacterBase:
	if multiplayer.multiplayer_peer == null:
		return null
	var local_id: int = multiplayer.get_unique_id()
	if local_id <= 0:
		return null
	for child in _character_container.get_children():
		if child.name == str(local_id):
			return child as CharacterBase
	return null


func _find_character_by_peer_id(peer_id: int) -> CharacterBase:
	for child in _character_container.get_children():
		if child.name == str(peer_id):
			return child as CharacterBase
	return null


# ============================================================
# UI
# ============================================================


func _update_info() -> void:
	if _info_label == null:
		return
	var mode: String = "REFEREE" if _is_server else "CLIENT"
	var my_id: int = 0
	var peers_str: String = "none"
	if multiplayer.multiplayer_peer != null:
		my_id = multiplayer.get_unique_id()
		var arr: PackedStringArray = []
		for peer_id in multiplayer.get_peers():
			arr.append(str(peer_id))
		peers_str = ", ".join(arr)
	_info_label.text = "%s | ID: %d | Peers: %s" % [mode, my_id, peers_str]


func _ensure_player_hud() -> void:
	if _is_server or _player_hud != null:
		return
	_player_hud = PLAYER_HUD_SCENE.instantiate() as Control
	assert(_player_hud != null, "MatchSession: failed to instantiate PlayerHud")
	_player_hud.name = "PlayerHud"
	_player_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_player_hud)
	var err: int = _player_hud.skill_pressed.connect(_on_skill_pressed)
	assert(err == OK, "MatchSession: failed to connect skill_pressed: %d" % err)


func _on_skill_pressed(skill_idx: int) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if _local_character == null:
		return
	var char_data: CharacterData = _local_character.get("_character_data") as CharacterData
	if char_data != null:
		var skills: Array = [char_data.skill_1, char_data.skill_2, char_data.ultimate]
		var skill: SkillData = skills[skill_idx] as SkillData
		if skill != null and skill.animation_name != "":
			_local_character.play_attack_animation(skill.animation_name)
		if skill != null and _player_hud != null:
			_player_hud.start_skill_cooldown(skill_idx, skill.cooldown)
	request_skill.rpc_id(REFEREE_PEER_ID, skill_idx, _local_character.facing_direction)


func _add_log(from_id: int, text: String) -> void:
	if _log_label == null:
		return
	var color: String = "cyan" if from_id > 0 else "yellow"
	_log_label.append_text("[color=%s]%s[/color]\n" % [color, text])
