extends GutTest

const CHARACTER_SCENE: PackedScene = preload("res://src/character/character_base.tscn")
const MATCH_SESSION_SCRIPT: GDScript = preload("res://src/game/match_session.gd")
const REFEREE_MANAGER_SCRIPT: GDScript = preload("res://src/referee/referee_manager.gd")


func test_character_base_moves_only_for_multiplayer_authority() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var data: CharacterData = CharacterDefinitions.warrior()

	var authority_character: CharacterBase = CHARACTER_SCENE.instantiate() as CharacterBase
	authority_character.assign_character_data(data)
	root.add_child(authority_character)
	authority_character.set_multiplayer_authority(1)
	assert_true(
		authority_character.is_multiplayer_authority(),
		"Peer 1 should be local authority in offline tests"
	)
	authority_character.set_move_input(Vector2.RIGHT)
	authority_character._physics_process(0.0)
	assert_eq(authority_character.velocity, Vector2.RIGHT * data.move_speed)

	var remote_character: CharacterBase = CHARACTER_SCENE.instantiate() as CharacterBase
	remote_character.assign_character_data(data)
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
	var referee: Node = autofree(REFEREE_MANAGER_SCRIPT.new())
	var character_container: Node2D = autofree(Node2D.new())

	referee.set("_character_container", character_container)

	var character_a: CharacterBase = CHARACTER_SCENE.instantiate() as CharacterBase
	character_a.name = "2"
	character_a.set_multiplayer_authority(1)
	character_container.add_child(character_a)

	var character_b: CharacterBase = CHARACTER_SCENE.instantiate() as CharacterBase
	character_b.name = "3"
	character_b.set_multiplayer_authority(1)
	character_container.add_child(character_b)

	referee.set("_move_inputs", {2: Vector2.RIGHT, 3: Vector2.DOWN})

	referee.call("simulate_movement", 0.0)

	assert_eq(character_a.get("_move_input"), Vector2.RIGHT)
	assert_eq(character_b.get("_move_input"), Vector2.DOWN)


func test_mark_peer_disconnected_stops_character_and_starts_grace_period() -> void:
	var referee: Node = autofree(REFEREE_MANAGER_SCRIPT.new())
	var character_container: Node2D = autofree(Node2D.new())

	referee.set("_character_container", character_container)

	var character: CharacterBase = CHARACTER_SCENE.instantiate() as CharacterBase
	character.name = "2"
	character.set_move_input(Vector2.RIGHT)
	character_container.add_child(character)

	referee.set("_move_inputs", {2: Vector2.RIGHT})
	referee.call("on_peer_disconnected", 2)

	var deadlines: Dictionary = referee.get("_disconnect_deadlines")
	var inputs: Dictionary = referee.get("_move_inputs")
	assert_true(deadlines.has(2), "Disconnect grace period should start for the disconnected peer")
	assert_false(inputs.has(2), "Disconnected peer input should be cleared immediately")
	assert_eq(character.get("_move_input"), Vector2.ZERO)


func test_broadcast_match_ended_marks_match_as_finished() -> void:
	var session: Node2D = autofree(MATCH_SESSION_SCRIPT.new())

	session.call("broadcast_match_ended", "disconnect timeout after 10.0 seconds", 1)

	assert_true(
		session.get("_match_ended"), "Match should be marked as ended after disconnect timeout"
	)
