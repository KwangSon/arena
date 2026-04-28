extends GutTest

const CHARACTER_BASE_SCRIPT: GDScript = preload("res://src/character/character_base.gd")
const TEST_COMBAT_SCRIPT: GDScript = preload("res://test/manual/test_combat.gd")


func test_character_base_moves_only_for_multiplayer_authority() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())

	var authority_character: CharacterBase = autofree(CHARACTER_BASE_SCRIPT.new())
	root.add_child(authority_character)
	authority_character.set_multiplayer_authority(1)
	assert_true(authority_character.is_multiplayer_authority(), "Peer 1 should be local authority in offline tests")
	authority_character.set_move_input(Vector2.RIGHT)

	authority_character._physics_process(0.0)

	assert_eq(authority_character.velocity, Vector2.RIGHT * CharacterBase.SPEED)

	var remote_character: CharacterBase = autofree(CHARACTER_BASE_SCRIPT.new())
	root.add_child(remote_character)
	remote_character.set_multiplayer_authority(2)
	assert_false(remote_character.is_multiplayer_authority(), "Peer 2 should not be local authority in offline tests")
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

	var synchronizer: MultiplayerSynchronizer = character.get_node("StateSynchronizer") as MultiplayerSynchronizer
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
