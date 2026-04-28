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

# Network
var _is_server: bool = false

# Spawner
var _spawner: MultiplayerSpawner
var _character_container: Node2D

# UI nodes
var _canvas: CanvasLayer
var _info_panel: PanelContainer
var _info_label: Label
var _ping_button: Button
var _ping_log: RichTextLabel
var _player_hud: Control


func _ready() -> void:
	_is_server = "--mode=referee" in OS.get_cmdline_args()
	_configure_manual_test_input()
	_setup_ui()
	_setup_network()
	_update_info()


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
		_spawn_character(id)

	_update_info()


func _on_peer_disconnected(id: int) -> void:
	print("[Network] Peer disconnected: %d" % id)

	# Server removes the character for the disconnected peer
	if _is_server:
		_remove_character(id)

	_update_info()


func _on_connected_to_server() -> void:
	print("[Network] Successfully connected to server! My id: %d" % multiplayer.get_unique_id())
	_ensure_player_hud()
	_update_info()


func _on_connection_failed() -> void:
	push_error("[Network] Connection to server failed!")
	_update_info()


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

	# Manually instantiate so we can set the name BEFORE adding to the tree.
	# MultiplayerSpawner auto-replicates children added to spawn_path on the server.
	var character: CharacterBody2D = CHARACTER_SCENE.instantiate() as CharacterBody2D
	assert(character != null, "TestCombat: failed to instantiate CharacterBase scene")
	assert(
		character.has_method("set_move_input"),
		"TestCombat: CharacterBase scene is not using src/character/character_base.gd; save the scene-script attachment in the editor"
	)
	character.name = str(peer_id)
	# Random spawn position for now
	character.position = Vector2(randf_range(100, 500), randf_range(100, 400))
	_character_container.add_child(character, true)
	print("[Spawner] Spawned CharacterBase for peer %d" % peer_id)


func _remove_character(peer_id: int) -> void:
	for child in _character_container.get_children():
		if child.name == str(peer_id):
			child.queue_free()
			print("[Spawner] Removed CharacterBase for peer %d" % peer_id)
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
	_add_ping_log(from_id)


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

	# --- MultiplayerSpawner ---
	# Add spawner to tree first, then set spawn_path
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "CharacterSpawner"
	_spawner.add_spawnable_scene(CHARACTER_SCENE.resource_path)
	add_child(_spawner)
	_spawner.spawn_path = _character_container.get_path()

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
	var my_id: int = multiplayer.get_unique_id()
	var peer_count: int = multiplayer.get_peers().size()

	# Build connected peers list
	var peers: PackedInt32Array = multiplayer.get_peers()
	var peers_str_arr: PackedStringArray = []
	for peer_id in peers:
		peers_str_arr.append(str(peer_id))
	var peers_str: String = ", ".join(peers_str_arr)

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


func _configure_manual_test_input() -> void:
	Input.set_emulate_touch_from_mouse(true)
	Input.set_emulate_mouse_from_touch(false)


# ============================================================
# UI Callbacks
# ============================================================


func _on_ping_pressed() -> void:
	print("[UI] Ping button pressed! Sending request_ping() to server")
	request_ping.rpc_id(1)  # Send to server (peer ID 1)


func _add_ping_log(from_id: int) -> void:
	var msg: String = "[color=cyan]Peer %d pinged![/color]" % from_id
	_ping_log.append_text(msg + "\n")
