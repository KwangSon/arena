extends GutTest

const CHARACTER_BASE_SCRIPT: GDScript = preload("res://src/character/character_base.gd")
const TEST_COMBAT_SCRIPT: GDScript = preload("res://test/manual/test_combat.gd")


func test_character_base_moves_only_for_multiplayer_authority() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())

	var authority_character: CharacterBase = autofree(CHARACTER_BASE_SCRIPT.new())
	root.add_child(authority_character)
	authority_character.set_multiplayer_authority(1)
	assert_true(
		authority_character.is_multiplayer_authority(),
		"Peer 1 should be local authority in offline tests"
	)
	var data: CharacterData = CharacterDefinitions.warrior()
	authority_character.assign_character_data(data)
	authority_character.set_move_input(Vector2.RIGHT)

	authority_character._physics_process(0.0)

	assert_eq(authority_character.velocity, Vector2.RIGHT * data.move_speed)

	var remote_character: CharacterBase = autofree(CHARACTER_BASE_SCRIPT.new())
	root.add_child(remote_character)
	remote_character.set_multiplayer_authority(2)
	assert_false(
		remote_character.is_multiplayer_authority(),
		"Peer 2 should not be local authority in offline tests"
	)
	remote_character.set_move_input(Vector2.LEFT)

	remote_character._physics_process(0.0)

	assert_eq(remote_character.velocity, Vector2.ZERO)


func test_apply_referee_movement_assigns_inputs_by_peer_id() -> void:
	var combat: Node2D = TEST_COMBAT_SCRIPT.new()
	autofree(combat)

	var character_container: Node2D = autofree(Node2D.new())
	combat.set("_character_container", character_container)
	combat.add_child(character_container)

	var character_a: CharacterBase = autofree(CHARACTER_BASE_SCRIPT.new())
	character_a.name = "2"
	character_a.set_multiplayer_authority(1)
	character_container.add_child(character_a)

	var character_b: CharacterBase = autofree(CHARACTER_BASE_SCRIPT.new())
	character_b.name = "3"
	character_b.set_multiplayer_authority(1)
	character_container.add_child(character_b)

	combat.set("_move_inputs_by_peer_id", {2: Vector2.RIGHT, 3: Vector2.DOWN})

	combat.call("_apply_referee_movement")

	assert_eq(character_a.get("_move_input"), Vector2.RIGHT)
	assert_eq(character_b.get("_move_input"), Vector2.DOWN)


func test_setup_character_synchronizer_replicates_position() -> void:
	var combat: Node2D = autofree(TEST_COMBAT_SCRIPT.new())
	var character: CharacterBody2D = autofree(CharacterBody2D.new())

	combat.call("_setup_character_synchronizer", character)

	var synchronizer: MultiplayerSynchronizer = (
		character.get_node("StateSynchronizer") as MultiplayerSynchronizer
	)
	assert_not_null(synchronizer, "StateSynchronizer should be added to each spawned character")
	assert_eq(synchronizer.root_path, NodePath(".."))
	assert_eq(synchronizer.get_multiplayer_authority(), 1)

	var config: SceneReplicationConfig = synchronizer.replication_config
	assert_not_null(config, "StateSynchronizer should have a replication config")
	assert_true(config.has_property(NodePath(".:position")))
	assert_true(config.property_get_spawn(NodePath(".:position")))
	assert_eq(
		config.property_get_replication_mode(NodePath(".:position")),
		SceneReplicationConfig.REPLICATION_MODE_ALWAYS
	)


func test_mark_peer_disconnected_stops_character_and_starts_grace_period() -> void:
	var combat: Node2D = TEST_COMBAT_SCRIPT.new()
	autofree(combat)

	var character_container: Node2D = autofree(Node2D.new())
	combat.set("_character_container", character_container)
	combat.add_child(character_container)

	var character: CharacterBase = autofree(CHARACTER_BASE_SCRIPT.new())
	character.name = "2"
	character.set_move_input(Vector2.RIGHT)
	character_container.add_child(character)

	combat.set("_move_inputs_by_peer_id", {2: Vector2.RIGHT})

	combat.call("_mark_peer_disconnected", 2)

	var deadlines: Dictionary = combat.get("_disconnect_deadlines_by_peer_id")
	var inputs: Dictionary = combat.get("_move_inputs_by_peer_id")
	assert_true(deadlines.has(2), "Disconnect grace period should start for the disconnected peer")
	assert_false(inputs.has(2), "Disconnected peer input should be cleared immediately")
	assert_eq(character.get("_move_input"), Vector2.ZERO)


func test_broadcast_match_ended_marks_match_as_finished() -> void:
	var combat: Node2D = TEST_COMBAT_SCRIPT.new()
	autofree(combat)

	combat.call("broadcast_match_ended", "disconnect timeout after 10.0 seconds", 2, 3)

	assert_true(
		combat.get("_match_ended"), "Match should be marked as ended after disconnect timeout"
	)


func test_disconnect_local_client_clears_network_state() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())

	var combat: Node2D = TEST_COMBAT_SCRIPT.new()
	root.add_child(combat)
	autofree(combat)

	# Set up initial state
	combat.set("_has_sent_move_input", true)
	combat.set("_last_sent_move_input", Vector2.RIGHT)

	# Mock the multiplayer peer check by setting _is_server to false
	combat.set("_is_server", false)

	# Call disconnect (it should handle null peer gracefully)
	combat.call("_disconnect_local_client")

	# Verify internal state is cleared
	assert_false(combat.get("_has_sent_move_input"), "Disconnect should reset move input state")
	assert_eq(
		combat.get("_last_sent_move_input"),
		Vector2.ZERO,
		"Disconnect should reset last sent move input"
	)
