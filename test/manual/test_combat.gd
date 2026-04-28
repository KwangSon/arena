## Manual test scene for multiplayer MVP
##
## Demonstrates ENet connection, MultiplayerSpawner, peer ID recognition,
## and RPC-based button press delivery across 3 Godot instances.
##
## How to run (3 instances):
##
##   Option A - Terminal:
##     Instance 1 (Referee): godot --path . -- --mode=referee
##     Instance 2 (Player):  godot --path .
##     Instance 3 (Player):  godot --path .
##
##   Option B - Godot Editor:
##     1. Set "Run Multiple Instances" to 3 (▶ button dropdown)
##     2. Set Main Run Args to "--mode=referee" (Editor Settings → Run → Main Run Args)
##     3. Press F6 to run the scene
##
## Instance roles:
##   - Instance 1: Referee (server-authoritative, game logic)
##   - Instance 2, 3: Player (client, input handling)
extends Node2D

const SERVER_PORT: int = 7777
const MAX_CLIENTS: int = 4
const CHARACTER_SCENE: PackedScene = preload("res://src/character/character_base.tscn")
const PLAYER_HUD_SCENE: PackedScene = preload("res://src/ui/player_hud.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://src/combat/projectile.tscn")
const REFEREE_PEER_ID: int = 1
const DISCONNECT_GRACE_PERIOD_SEC: float = 10.0

# Network
var _is_server: bool = false
var _match_ended: bool = false
var _ignore_next_server_disconnect: bool = false

# Spawner
var _spawner: MultiplayerSpawner
var _character_container: Node2D
var _projectile_spawner: MultiplayerSpawner
var _projectile_container: Node2D
var _camera: Camera2D
var _local_character: CharacterBase
var _move_inputs_by_peer_id: Dictionary = {}
var _disconnect_deadlines_by_peer_id: Dictionary = {}
var _skill_last_used_by_peer_id: Dictionary = {}
var _last_sent_move_input: Vector2 = Vector2.ZERO
var _has_sent_move_input: bool = false

# UI nodes
var _canvas: CanvasLayer
var _info_panel: PanelContainer
var _info_label: Label
var _ping_button: Button
var _disconnect_button: Button
var _reconnect_button: Button
var _ping_log: RichTextLabel
var _player_hud: Control


func _ready() -> void:
	_is_server = "--mode=referee" in OS.get_cmdline_args()
	_configure_manual_test_input()
	_setup_ui()
	_setup_network()
	_update_info()


func _process(_delta: float) -> void:
	if _match_ended:
		return
	if _is_server:
		return
	if _camera == null:
		return

	if _local_character == null:
		_local_character = _find_local_character()
		if _local_character != null:
			_local_character.show_facing_indicator()
	if _local_character == null:
		return

	_camera.global_position = _local_character.global_position


func _physics_process(_delta: float) -> void:
	if _match_ended:
		return

	if _is_server:
		_apply_referee_movement()
		_process_disconnect_grace_timeouts()
		return

	_submit_local_move_input()


# ============================================================
# Network Setup
# ============================================================


func _setup_network() -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()

	if _is_server:
		var error: int = peer.create_server(SERVER_PORT, MAX_CLIENTS)
		if error != OK:
			push_error("[Network] Failed to create server: %d" % error)
			return
		print("[Network] Server created on port %d" % SERVER_PORT)
	else:
		var error: int = peer.create_client("localhost", SERVER_PORT)
		if error != OK:
			push_error("[Network] Failed to create client: %d" % error)
			return
		print("[Network] Client connecting to localhost:%d..." % SERVER_PORT)

	multiplayer.multiplayer_peer = peer

	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	print(
		(
			"[Network] Setup complete - is_server=%s, my_id=%d"
			% [_is_server, multiplayer.get_unique_id()]
		)
	)

	# Server spawns its own character
	if _is_server:
		_spawn_character(multiplayer.get_unique_id())


func _on_peer_connected(id: int) -> void:
	print("[Network] Peer connected: %d" % id)

	# Server spawns a character for the new peer
	if _is_server:
		if _disconnect_deadlines_by_peer_id.has(id):
			_disconnect_deadlines_by_peer_id.erase(id)
			_move_inputs_by_peer_id[id] = Vector2.ZERO
			print("[Network] Peer %d reconnected within grace period" % id)
			_update_info()
			return
		_spawn_character(id)

	_update_info()


func _on_peer_disconnected(id: int) -> void:
	print("[Network] Peer disconnected: %d" % id)

	if _is_server:
		_mark_peer_disconnected(id)

	_update_info()


func _on_connected_to_server() -> void:
	print("[Network] Successfully connected to server! My id: %d" % multiplayer.get_unique_id())
	_ensure_player_hud()
	_update_info()


func _on_connection_failed() -> void:
	push_error("[Network] Connection to server failed!")
	_update_info()


func _on_server_disconnected() -> void:
	if _ignore_next_server_disconnect:
		_ignore_next_server_disconnect = false
		_add_ping_log(-1, "Local client disconnected from referee.")
		_update_info()
		return

	push_error("[Network] Referee disconnected. Ending match.")
	_match_ended = true
	_add_ping_log(-1, "Referee disconnected. Match ended.")


# ============================================================
# Character Spawning (Server-only)
# ============================================================


func _spawn_character(peer_id: int) -> void:
	# Only the server can spawn via MultiplayerSpawner
	if not _is_server:
		return

	# Check if character already exists for this peer
	for child in _character_container.get_children():
		if child.name == str(peer_id):
			print("[Spawner] Character already exists for peer %d, skipping" % peer_id)
			return

	var spawn_count: int = _character_container.get_child_count()
	var character_id: String = "warrior" if spawn_count % 2 == 0 else "mage"
	var team_id: int = 1 if spawn_count % 2 == 0 else 2
	var spawn_data: Dictionary = {
		"peer_id": peer_id,
		"position": Vector2(randf_range(100, 500), randf_range(100, 400)),
		"character_id": character_id,
		"team_id": team_id,
	}
	var character: Node = _spawner.spawn(spawn_data)
	assert(character != null, "TestCombat: failed to spawn CharacterBase for peer %d" % peer_id)
	print("[Spawner] Spawned %s for peer %d" % [character_id, peer_id])


func _remove_character(peer_id: int) -> void:
	_disconnect_deadlines_by_peer_id.erase(peer_id)
	_move_inputs_by_peer_id.erase(peer_id)
	_skill_last_used_by_peer_id.erase(peer_id)

	for child in _character_container.get_children():
		if child.name == str(peer_id):
			child.queue_free()
			print("[Spawner] Removed CharacterBase for peer %d" % peer_id)
			if _local_character != null and _local_character.name == str(peer_id):
				_local_character = null
			return


# ============================================================
# RPC Functions
# ============================================================

## Client→Server: Request a ping broadcast
@rpc("any_peer", "reliable")
func request_ping() -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	print("[RPC] request_ping() received from peer %d" % sender_id)
	broadcast_ping.rpc(sender_id)


## Server→All: Broadcast ping event to every client
@rpc("authority", "call_local", "reliable")
func broadcast_ping(from_id: int) -> void:
	print("[RPC] broadcast_ping() - peer %d pinged!" % from_id)
	_add_ping_log(from_id, "Peer %d pinged!" % from_id)


@rpc("any_peer", "unreliable_ordered")
func submit_move_input(input_vector: Vector2) -> void:
	assert(_is_server, "TestCombat.submit_move_input must only run on referee")

	var sender_id: int = multiplayer.get_remote_sender_id()
	_move_inputs_by_peer_id[sender_id] = input_vector.limit_length()
	_disconnect_deadlines_by_peer_id.erase(sender_id)


@rpc("any_peer", "reliable")
func request_skill(skill_idx: int, direction: Vector2) -> void:
	assert(_is_server, "TestCombat.request_skill must only run on referee")
	assert(skill_idx >= 0 and skill_idx <= 2, "request_skill: invalid skill_idx %d" % skill_idx)

	var sender_id: int = multiplayer.get_remote_sender_id()
	var attacker: CharacterBase = _find_character_by_peer_id(sender_id)
	if attacker == null:
		return

	var char_data: CharacterData = attacker.get("_character_data") as CharacterData
	if char_data == null:
		return

	var skills: Array = [char_data.skill_1, char_data.skill_2, char_data.ultimate]
	var skill: SkillData = skills[skill_idx] as SkillData
	assert(skill != null, "request_skill: skill %d is null for peer %d" % [skill_idx, sender_id])

	if not _skill_last_used_by_peer_id.has(sender_id):
		_skill_last_used_by_peer_id[sender_id] = {}
	var peer_cooldowns: Dictionary = _skill_last_used_by_peer_id[sender_id]
	var now: float = _get_now_seconds()
	if peer_cooldowns.has(skill_idx) and now - peer_cooldowns[skill_idx] < skill.cooldown:
		return

	if attacker.mp < skill.mp_cost:
		return

	attacker.mp -= skill.mp_cost
	peer_cooldowns[skill_idx] = now

	match skill.skill_type:
		SkillData.Type.MELEE:
			_execute_melee_skill(attacker, sender_id, skill, direction)
		SkillData.Type.AOE:
			_execute_aoe_skill(attacker, sender_id, skill)
		SkillData.Type.PROJECTILE:
			_execute_projectile_skill(attacker, sender_id, skill, direction)


func _execute_melee_skill(
	attacker: CharacterBase, attacker_id: int, skill: SkillData, _direction: Vector2
) -> void:
	var closest_target: CharacterBase = null
	var closest_dist: float = skill.range

	for child in _character_container.get_children():
		var target: CharacterBase = child as CharacterBase
		assert(target != null, "TestCombat: expected CharacterBase under CharacterContainer")
		if target == attacker:
			continue
		var dist: float = attacker.global_position.distance_to(target.global_position)
		if dist <= closest_dist:
			closest_dist = dist
			closest_target = target

	if closest_target == null:
		return

	_apply_damage(attacker_id, int(closest_target.name), closest_target, skill)


func _execute_aoe_skill(attacker: CharacterBase, attacker_id: int, skill: SkillData) -> void:
	for child in _character_container.get_children():
		var target: CharacterBase = child as CharacterBase
		assert(target != null, "TestCombat: expected CharacterBase under CharacterContainer")
		if target == attacker:
			continue
		var dist: float = attacker.global_position.distance_to(target.global_position)
		if dist <= skill.range:
			_apply_damage(attacker_id, int(target.name), target, skill)


func _execute_projectile_skill(
	attacker: CharacterBase, attacker_id: int, skill: SkillData, direction: Vector2
) -> void:
	var enemy_layer: int = 2 if attacker.team_id == 1 else 1
	var spawn_data: Dictionary = {
		"attacker_id": attacker_id,
		"position": attacker.global_position,
		"direction": direction,
		"damage": skill.damage,
		"speed": skill.projectile_speed,
		"range": skill.range,
		"skill_id": skill.id,
		"collision_mask": enemy_layer,
	}
	_projectile_spawner.spawn(spawn_data)


func _spawn_projectile_node(data: Variant) -> Node:
	assert(data is Dictionary, "TestCombat: projectile spawn data must be a Dictionary")
	var spawn_data: Dictionary = data

	var projectile: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	assert(projectile != null, "TestCombat: failed to instantiate Projectile scene")

	projectile.attacker_id = spawn_data["attacker_id"]
	projectile.damage = spawn_data["damage"]
	projectile.skill_id = spawn_data["skill_id"]
	projectile.position = spawn_data["position"]
	projectile.setup(spawn_data["direction"], spawn_data["speed"], spawn_data["range"])
	projectile.collision_layer = 0
	projectile.collision_mask = spawn_data.get("collision_mask", 1)
	projectile.set_multiplayer_authority(REFEREE_PEER_ID)
	_setup_projectile_synchronizer(projectile)

	var err: int = projectile.body_hit.connect(_on_projectile_body_hit)
	assert(err == OK, "TestCombat: failed to connect projectile body_hit: %d" % err)

	return projectile


func _on_projectile_body_hit(projectile: Projectile, body: Node2D) -> void:
	var target: CharacterBase = body as CharacterBase
	if target == null:
		return
	var target_id: int = int(target.name)
	var dummy_skill := SkillData.new()
	dummy_skill.damage = projectile.damage
	dummy_skill.id = projectile.skill_id
	_apply_damage(projectile.attacker_id, target_id, target, dummy_skill)


func _apply_damage(
	attacker_id: int, target_id: int, target: CharacterBase, skill: SkillData
) -> void:
	target.hp = max(0, target.hp - skill.damage)
	broadcast_hit_result.rpc(attacker_id, target_id, skill.damage, skill.id)
	if target.hp <= 0:
		_handle_character_death(target_id)


func _handle_character_death(loser_id: int) -> void:
	if _match_ended:
		return
	var winner_id: int = _find_first_active_peer_id_except(loser_id)
	broadcast_match_ended.rpc("player eliminated", loser_id, winner_id)


@rpc("authority", "call_local", "reliable")
func broadcast_hit_result(attacker_id: int, target_id: int, damage: int, skill_id: String) -> void:
	var msg: String = (
		"Peer %d hit peer %d for %d dmg [%s]" % [attacker_id, target_id, damage, skill_id]
	)
	_add_ping_log(-1, msg)


@rpc("authority", "call_local", "reliable")
func broadcast_match_ended(reason: String, loser_id: int, winner_id: int) -> void:
	_match_ended = true

	var message: String = "Match ended: %s" % reason
	if loser_id > 0:
		message += " loser=%d" % loser_id
	if winner_id > 0:
		message += " winner=%d" % winner_id

	print("[Match] %s" % message)
	_add_ping_log(-1, message)


# ============================================================
# UI Setup
# ============================================================


func _setup_ui() -> void:
	# CanvasLayer - screen-space UI decoupled from camera
	_canvas = CanvasLayer.new()
	add_child(_canvas)

	# Main VBoxContainer for layout
	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 8)
	_canvas.add_child(main_vbox)

	# --- Character Container (Node2D for CharacterBody2D children) ---
	_character_container = Node2D.new()
	_character_container.name = "CharacterContainer"
	add_child(_character_container)

	if not _is_server:
		_setup_local_camera()

	# --- MultiplayerSpawner ---
	# Add spawner to tree first, then set spawn_path
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "CharacterSpawner"
	_spawner.spawn_function = _spawn_character_node
	add_child(_spawner)
	_spawner.spawn_path = _character_container.get_path()

	# --- Projectile Container + Spawner ---
	_projectile_container = Node2D.new()
	_projectile_container.name = "ProjectileContainer"
	add_child(_projectile_container)

	_projectile_spawner = MultiplayerSpawner.new()
	_projectile_spawner.name = "ProjectileSpawner"
	_projectile_spawner.spawn_function = _spawn_projectile_node
	add_child(_projectile_spawner)
	_projectile_spawner.spawn_path = _projectile_container.get_path()

	# --- Debug Info Panel ---
	_info_panel = PanelContainer.new()
	_info_panel.custom_minimum_size = Vector2(300, 80)
	main_vbox.add_child(_info_panel)

	_info_label = Label.new()
	_info_panel.add_child(_info_label)

	# --- Ping Button ---
	_ping_button = Button.new()
	_ping_button.text = "📡 Ping!"
	_ping_button.custom_minimum_size = Vector2(120, 40)
	_ping_button.pressed.connect(_on_ping_pressed)
	main_vbox.add_child(_ping_button)

	if not _is_server:
		_disconnect_button = Button.new()
		_disconnect_button.text = "Force Disconnect"
		_disconnect_button.custom_minimum_size = Vector2(180, 40)
		_disconnect_button.pressed.connect(_on_force_disconnect_pressed)
		main_vbox.add_child(_disconnect_button)

		_reconnect_button = Button.new()
		_reconnect_button.text = "Reconnect"
		_reconnect_button.custom_minimum_size = Vector2(180, 40)
		_reconnect_button.pressed.connect(_on_reconnect_pressed)
		main_vbox.add_child(_reconnect_button)

	# --- Ping Log ---
	_ping_log = RichTextLabel.new()
	_ping_log.custom_minimum_size = Vector2(400, 150)
	_ping_log.bbcode_enabled = true
	_ping_log.scroll_following = true
	main_vbox.add_child(_ping_log)

	if not _is_server:
		_ensure_player_hud()


func _update_info() -> void:
	var mode: String = "REFEREE (Server)" if _is_server else "PLAYER (Client)"

	var my_id: int = 0
	if multiplayer.multiplayer_peer != null:
		my_id = multiplayer.get_unique_id()

	# Check if multiplayer peer exists before accessing peers
	var peer_count: int = 0
	var peers_str: String = "none"
	if multiplayer.multiplayer_peer != null:
		var peers: PackedInt32Array = multiplayer.get_peers()
		peer_count = peers.size()

		# Build connected peers list
		var peers_str_arr: PackedStringArray = []
		for peer_id in peers:
			peers_str_arr.append(str(peer_id))
		peers_str = ", ".join(peers_str_arr)

	# Debug print
	print("=== Debug Info ===")
	print("  Mode: %s" % mode)
	print("  My ID: %d" % my_id)
	print("  Connected peers (%d): %s" % [peer_count, peers_str])

	# UI label
	var text: String = "=== Debug Info ===\n"
	text += "Mode: %s\n" % mode
	text += "My ID: %d\n" % my_id
	text += "Peers (%d): %s" % [peer_count, peers_str]
	_info_label.text = text


func _ensure_player_hud() -> void:
	if _is_server:
		return
	if _player_hud != null:
		return

	_player_hud = PLAYER_HUD_SCENE.instantiate() as Control
	assert(_player_hud != null, "TestCombat: failed to instantiate PlayerHud")
	_player_hud.name = "PlayerHud"
	_player_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_player_hud)

	var err: int = _player_hud.skill_pressed.connect(_on_skill_pressed)
	assert(err == OK, "TestCombat: failed to connect skill_pressed: %d" % err)


func _on_skill_pressed(skill_idx: int) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if _local_character == null:
		return
	request_skill.rpc_id(REFEREE_PEER_ID, skill_idx, _local_character.facing_direction)


func _configure_manual_test_input() -> void:
	Input.set_emulate_touch_from_mouse(true)
	Input.set_emulate_mouse_from_touch(false)


func _setup_local_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "LocalCamera"
	_camera.enabled = true
	add_child(_camera)


func _find_local_character() -> CharacterBase:
	if multiplayer.multiplayer_peer == null:
		return null

	var local_peer_id: int = multiplayer.get_unique_id()
	if local_peer_id <= 0:
		return null

	for child in _character_container.get_children():
		if child.name != str(local_peer_id):
			continue

		var character: CharacterBase = child as CharacterBase
		assert(character != null, "TestCombat: expected CharacterBase for local character")
		return character

	return null


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


func _apply_referee_movement() -> void:
	for child in _character_container.get_children():
		var character: CharacterBase = child as CharacterBase
		assert(character != null, "TestCombat: expected CharacterBase under CharacterContainer")

		var peer_id: int = int(character.name)
		var input_vector: Vector2 = _move_inputs_by_peer_id.get(peer_id, Vector2.ZERO)
		character.set_move_input(input_vector)


func _process_disconnect_grace_timeouts() -> void:
	var now_seconds: float = _get_now_seconds()
	var timed_out_peer_ids: Array[int] = []

	for peer_id_variant in _disconnect_deadlines_by_peer_id.keys():
		var peer_id: int = int(peer_id_variant)
		var deadline: float = _disconnect_deadlines_by_peer_id[peer_id]
		if now_seconds < deadline:
			continue

		timed_out_peer_ids.append(peer_id)

	for peer_id in timed_out_peer_ids:
		_handle_disconnect_timeout(peer_id)


func _mark_peer_disconnected(peer_id: int) -> void:
	_move_inputs_by_peer_id.erase(peer_id)
	_disconnect_deadlines_by_peer_id[peer_id] = _get_now_seconds() + DISCONNECT_GRACE_PERIOD_SEC

	var character: CharacterBase = _find_character_by_peer_id(peer_id)
	if character != null:
		character.set_move_input(Vector2.ZERO)

	print(
		(
			"[Network] Peer %d entered disconnect grace period (%.1fs)"
			% [peer_id, DISCONNECT_GRACE_PERIOD_SEC]
		)
	)


func _handle_disconnect_timeout(peer_id: int) -> void:
	if _match_ended:
		return

	_disconnect_deadlines_by_peer_id.erase(peer_id)
	_move_inputs_by_peer_id.erase(peer_id)

	var winner_id: int = _find_first_active_peer_id_except(peer_id)
	var reason: String = "disconnect timeout after %.1f seconds" % DISCONNECT_GRACE_PERIOD_SEC
	broadcast_match_ended.rpc(reason, peer_id, winner_id)
	_remove_character(peer_id)


func _find_character_by_peer_id(peer_id: int) -> CharacterBase:
	for child in _character_container.get_children():
		if child.name != str(peer_id):
			continue

		var character: CharacterBase = child as CharacterBase
		assert(character != null, "TestCombat: expected CharacterBase for peer lookup")
		return character

	return null


func _find_first_active_peer_id_except(excluded_peer_id: int) -> int:
	for child in _character_container.get_children():
		var character: CharacterBase = child as CharacterBase
		assert(character != null, "TestCombat: expected CharacterBase under CharacterContainer")

		var peer_id: int = int(character.name)
		if peer_id == excluded_peer_id:
			continue

		return peer_id

	return -1


func _setup_character_synchronizer(character: CharacterBody2D) -> void:
	var synchronizer: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = "StateSynchronizer"
	synchronizer.root_path = NodePath("..")
	synchronizer.replication_interval = 0.0
	synchronizer.delta_interval = 0.0
	synchronizer.set_multiplayer_authority(REFEREE_PEER_ID)

	var replication_config: SceneReplicationConfig = SceneReplicationConfig.new()

	for prop in [NodePath(".:position"), NodePath(".:hp")]:
		replication_config.add_property(prop)
		replication_config.property_set_spawn(prop, true)
		replication_config.property_set_replication_mode(
			prop, SceneReplicationConfig.REPLICATION_MODE_ALWAYS
		)

	synchronizer.replication_config = replication_config

	character.add_child(synchronizer, true)


func _setup_projectile_synchronizer(projectile: Node2D) -> void:
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
	assert(data is Dictionary, "TestCombat: spawn data must be a Dictionary")

	var spawn_data: Dictionary = data
	assert(spawn_data.has("peer_id"), "TestCombat: spawn data missing peer_id")
	assert(spawn_data.has("position"), "TestCombat: spawn data missing position")

	var character: CharacterBody2D = CHARACTER_SCENE.instantiate() as CharacterBody2D
	assert(character != null, "TestCombat: failed to instantiate CharacterBase scene")
	assert(
		character.has_method("set_move_input"),
		(
			"TestCombat: CharacterBase scene is not using src/character/character_base.gd;"
			+ " save the scene-script attachment in the editor"
		)
	)

	var character_base: CharacterBase = character as CharacterBase
	assert(character_base != null, "TestCombat: CharacterBody2D is not a CharacterBase")

	var character_id: String = spawn_data.get("character_id", "warrior")
	var char_data: CharacterData = (
		CharacterDefinitions.warrior() if character_id == "warrior" else CharacterDefinitions.mage()
	)
	character_base.assign_character_data(char_data)
	character_base.team_id = spawn_data.get("team_id", 1)
	character_base.collision_layer = character_base.team_id

	var spawn_position: Vector2 = spawn_data["position"]
	character.set_multiplayer_authority(REFEREE_PEER_ID)
	character.name = str(spawn_data["peer_id"])
	character.position = spawn_position
	_setup_character_synchronizer(character)

	return character


func _get_local_move_input() -> Vector2:
	if _player_hud != null and _player_hud.has_method("get_move_input"):
		var hud_input: Variant = _player_hud.call("get_move_input")
		assert(hud_input is Vector2, "TestCombat: PlayerHud.get_move_input must return Vector2")
		var move_input: Vector2 = hud_input
		if move_input != Vector2.ZERO:
			return move_input

	return Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")


func _get_now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func _disconnect_local_client() -> void:
	if _is_server:
		return
	if multiplayer.multiplayer_peer == null:
		return

	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	_ignore_next_server_disconnect = true
	multiplayer.multiplayer_peer = null
	peer.close()
	_has_sent_move_input = false
	_last_sent_move_input = Vector2.ZERO
	_local_character = null
	_add_ping_log(-1, "Forced local disconnect. Reconnect within 10 seconds to test grace period.")
	_update_info()


func _reconnect_local_client() -> void:
	if _is_server:
		return
	if multiplayer.multiplayer_peer != null:
		var status: MultiplayerPeer.ConnectionStatus = (
			multiplayer.multiplayer_peer.get_connection_status()
		)
		if (
			status == MultiplayerPeer.CONNECTION_CONNECTING
			or status == MultiplayerPeer.CONNECTION_CONNECTED
		):
			_add_ping_log(-1, "Reconnect skipped: client is already connecting or connected.")
			return

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: int = peer.create_client("localhost", SERVER_PORT)
	if error != OK:
		push_error("[Network] Failed to reconnect client: %d" % error)
		return

	_match_ended = false
	multiplayer.multiplayer_peer = peer
	_add_ping_log(-1, "Reconnect requested.")
	_update_info()


# ============================================================
# UI Callbacks
# ============================================================


func _on_ping_pressed() -> void:
	print("[UI] Ping button pressed! Sending request_ping() to server")
	request_ping.rpc_id(1)  # Send to server (peer ID 1)


func _on_force_disconnect_pressed() -> void:
	_disconnect_local_client()


func _on_reconnect_pressed() -> void:
	_reconnect_local_client()


func _add_ping_log(from_id: int, text: String) -> void:
	if _ping_log == null:
		return

	var msg: String = text
	if from_id > 0:
		msg = "[color=cyan]%s[/color]" % text
	else:
		msg = "[color=yellow]%s[/color]" % text

	_ping_log.append_text(msg + "\n")
