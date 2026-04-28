extends GutTest

const CHARACTER_SCENE: PackedScene = preload("res://src/character/character_base.tscn")

const REFEREE_PEER_ID: int = 1
const PEER_ID: int = 2
const SPAWN_POSITION: Vector2 = Vector2(100.0, 200.0)


func _make_spawn_data(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"peer_id": PEER_ID,
		"position": SPAWN_POSITION,
		"team_id": 1,
		"character_id": "warrior",
	}
	base.merge(overrides, true)
	return base


func test_returns_character_base_instance() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var character: CharacterBase = CharacterSpawner.create_node(_make_spawn_data(), REFEREE_PEER_ID)
	assert_not_null(character, "create_node should return a CharacterBase")
	root.add_child(character)


func test_name_equals_peer_id() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var character: CharacterBase = CharacterSpawner.create_node(_make_spawn_data(), REFEREE_PEER_ID)
	root.add_child(character)
	assert_eq(character.name, str(PEER_ID), "Character name should match peer_id")


func test_position_matches_spawn_data() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var character: CharacterBase = CharacterSpawner.create_node(_make_spawn_data(), REFEREE_PEER_ID)
	root.add_child(character)
	assert_eq(character.position, SPAWN_POSITION)


func test_team_id_assigned() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var character: CharacterBase = CharacterSpawner.create_node(
		_make_spawn_data({"team_id": 2}), REFEREE_PEER_ID
	)
	root.add_child(character)
	assert_eq(character.team_id, 2)


func test_collision_layer_matches_team_id() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var character: CharacterBase = CharacterSpawner.create_node(
		_make_spawn_data({"team_id": 1}), REFEREE_PEER_ID
	)
	root.add_child(character)
	assert_eq(character.collision_layer, 1)


func test_multiplayer_authority_set_to_referee() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var character: CharacterBase = CharacterSpawner.create_node(_make_spawn_data(), REFEREE_PEER_ID)
	root.add_child(character)
	assert_eq(character.get_multiplayer_authority(), REFEREE_PEER_ID)


func test_state_synchronizer_child_exists() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var character: CharacterBase = CharacterSpawner.create_node(_make_spawn_data(), REFEREE_PEER_ID)
	root.add_child(character)
	var synchronizer: Node = character.get_node_or_null("StateSynchronizer")
	assert_not_null(synchronizer, "StateSynchronizer child should be added by CharacterSpawner")
	assert_true(
		synchronizer is MultiplayerSynchronizer,
		"StateSynchronizer should be a MultiplayerSynchronizer"
	)


func test_warrior_character_data_assigned() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var character: CharacterBase = CharacterSpawner.create_node(
		_make_spawn_data({"character_id": "warrior"}), REFEREE_PEER_ID
	)
	root.add_child(character)
	assert_gt(character.max_hp, 0, "CharacterData should be assigned (max_hp > 0)")
