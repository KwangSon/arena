extends GutTest

const CHARACTER_SCENE: PackedScene = preload(
	"res://src/character/character_base.tscn"
)
const REFEREE_MANAGER_SCRIPT: GDScript = preload(
	"res://src/referee/referee_manager.gd"
)

const REFEREE_PEER_ID: int = 1


func _make_referee(team_size: int = 1) -> Dictionary:
	var referee: Node = autofree(REFEREE_MANAGER_SCRIPT.new())
	var container: Node2D = autofree(Node2D.new())
	referee.set("_character_container", container)
	referee.set("_team_size", team_size)
	referee.set("_team_alive", {})
	var executor: SkillExecutor = SkillExecutor.new()
	referee.set("_skill_executor", executor)
	return {"referee": referee, "container": container}


func _add_character(
	container: Node2D, peer_id: int, team_id: int
) -> CharacterBase:
	var c: CharacterBase = CHARACTER_SCENE.instantiate()
	c.name = str(peer_id)
	c.team_id = team_id
	c.set_multiplayer_authority(REFEREE_PEER_ID)
	container.add_child(c)
	return c


# ============================================================
# Team assignment via _team_alive tracking
# ============================================================


func test_team_alive_tracks_spawned_characters() -> void:
	var d: Dictionary = _make_referee(3)
	var referee: Node = d["referee"]
	var container: Node2D = d["container"]

	_add_character(container, 10, 1)
	_add_character(container, 11, 1)
	_add_character(container, 12, 1)
	_add_character(container, 20, 2)
	_add_character(container, 21, 2)
	_add_character(container, 22, 2)

	referee.set("_team_alive", {1: 3, 2: 3})

	var alive: Dictionary = referee.get("_team_alive")
	assert_eq(alive[1], 3, "Team 1 should have 3 alive")
	assert_eq(alive[2], 3, "Team 2 should have 3 alive")


# ============================================================
# _on_character_died — team-level death tracking
# ============================================================


func test_single_death_does_not_end_3v3_match() -> void:
	var d: Dictionary = _make_referee(3)
	var referee: Node = d["referee"]
	var container: Node2D = d["container"]
	watch_signals(referee)

	_add_character(container, 10, 1)
	_add_character(container, 11, 1)
	_add_character(container, 12, 1)
	_add_character(container, 20, 2)
	_add_character(container, 21, 2)
	_add_character(container, 22, 2)
	referee.set("_team_alive", {1: 3, 2: 3})

	# Kill one member of team 2
	referee.call("_on_character_died", 20, -1)

	var alive: Dictionary = referee.get("_team_alive")
	assert_eq(alive[2], 2, "Team 2 should have 2 alive after 1 death")
	assert_eq(alive[1], 3, "Team 1 should still have 3 alive")
	assert_signal_not_emitted(
		referee, "match_result_ready",
		"Match should NOT end after 1 death in 3v3"
	)


func test_team_wipe_ends_3v3_match() -> void:
	var d: Dictionary = _make_referee(3)
	var referee: Node = d["referee"]
	var container: Node2D = d["container"]
	watch_signals(referee)

	_add_character(container, 10, 1)
	_add_character(container, 11, 1)
	_add_character(container, 12, 1)
	_add_character(container, 20, 2)
	_add_character(container, 21, 2)
	_add_character(container, 22, 2)
	referee.set("_team_alive", {1: 3, 2: 3})

	# Kill all of team 2
	referee.call("_on_character_died", 20, -1)
	referee.call("_on_character_died", 21, -1)
	referee.call("_on_character_died", 22, -1)

	var alive: Dictionary = referee.get("_team_alive")
	assert_eq(alive[2], 0, "Team 2 should have 0 alive")
	assert_signal_emitted(
		referee, "match_result_ready",
		"Match should end when a team is wiped"
	)


func test_1v1_death_ends_match_immediately() -> void:
	var d: Dictionary = _make_referee(1)
	var referee: Node = d["referee"]
	var container: Node2D = d["container"]
	watch_signals(referee)

	_add_character(container, 10, 1)
	_add_character(container, 20, 2)
	referee.set("_team_alive", {1: 1, 2: 1})

	referee.call("_on_character_died", 20, 10)

	assert_signal_emitted(
		referee, "match_result_ready",
		"1v1 death should end match immediately"
	)


# ============================================================
# _handle_disconnect_timeout — forfeit
# ============================================================


func test_disconnect_timeout_removes_player_in_3v3() -> void:
	var d: Dictionary = _make_referee(3)
	var referee: Node = d["referee"]
	var container: Node2D = d["container"]
	watch_signals(referee)

	_add_character(container, 10, 1)
	_add_character(container, 11, 1)
	_add_character(container, 12, 1)
	_add_character(container, 20, 2)
	_add_character(container, 21, 2)
	_add_character(container, 22, 2)
	referee.set("_team_alive", {1: 3, 2: 3})

	# Disconnect one member of team 1
	referee.call("_handle_disconnect_timeout", 10, false)

	var alive: Dictionary = referee.get("_team_alive")
	assert_eq(
		alive[1], 2,
		"Team 1 alive should decrease after disconnect"
	)
	assert_signal_not_emitted(
		referee, "match_result_ready",
		"Match should NOT end from single disconnect in 3v3"
	)


func test_full_team_disconnect_ends_match() -> void:
	var d: Dictionary = _make_referee(3)
	var referee: Node = d["referee"]
	var container: Node2D = d["container"]
	watch_signals(referee)

	_add_character(container, 10, 1)
	_add_character(container, 11, 1)
	_add_character(container, 12, 1)
	_add_character(container, 20, 2)
	referee.set("_team_alive", {1: 3, 2: 1})

	# Disconnect all of team 1
	referee.call("_handle_disconnect_timeout", 10, false)
	referee.call("_handle_disconnect_timeout", 11, false)
	referee.call("_handle_disconnect_timeout", 12, false)

	var alive: Dictionary = referee.get("_team_alive")
	assert_eq(alive[1], 0, "Team 1 should have 0 alive")
	assert_signal_emitted(
		referee, "match_result_ready",
		"Match should end when entire team disconnects"
	)


# ============================================================
# AOE friendly-fire prevention
# ============================================================


func _make_executor(container: Node2D) -> SkillExecutor:
	var executor: SkillExecutor = SkillExecutor.new()
	var proj_spawner: MultiplayerSpawner = MultiplayerSpawner.new()
	container.get_parent().add_child(proj_spawner)
	var ha_container: Node2D = Node2D.new()
	container.get_parent().add_child(ha_container)
	var ha_spawner: MultiplayerSpawner = MultiplayerSpawner.new()
	container.get_parent().add_child(ha_spawner)
	ha_spawner.spawn_path = ha_container.get_path()
	executor.setup(
		container, proj_spawner, ha_spawner, REFEREE_PEER_ID
	)
	return executor


func test_aoe_does_not_hit_allies() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var container: Node2D = Node2D.new()
	root.add_child(container)
	var executor: SkillExecutor = _make_executor(container)

	var attacker: CharacterBase = _add_character(
		container, 10, 1
	)
	attacker.position = Vector2.ZERO
	var ally: CharacterBase = _add_character(container, 11, 1)
	ally.position = Vector2(50, 0)
	var enemy: CharacterBase = _add_character(container, 20, 2)
	enemy.position = Vector2(80, 0)

	var skill: SkillData = SkillData.new()
	skill.id = "aoe_test"
	skill.skill_type = SkillData.Type.AOE
	skill.damage = 25
	skill.range = 500.0
	skill.cooldown = 0.0
	skill.mp_cost = 0

	await wait_physics_frames(2)
	executor.try_execute_skill(
		attacker, 10, 0, skill, Vector2.ZERO
	)

	assert_eq(
		ally.hp, ally.max_hp,
		"Ally should NOT take AOE damage"
	)
	assert_eq(
		enemy.hp, enemy.max_hp - skill.damage,
		"Enemy should take AOE damage"
	)


func test_aoe_still_hits_enemy_in_1v1() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var container: Node2D = Node2D.new()
	root.add_child(container)
	var executor: SkillExecutor = _make_executor(container)

	var attacker: CharacterBase = _add_character(
		container, 10, 1
	)
	attacker.position = Vector2.ZERO
	var enemy: CharacterBase = _add_character(container, 20, 2)
	enemy.position = Vector2(80, 0)

	var skill: SkillData = SkillData.new()
	skill.id = "aoe_test"
	skill.skill_type = SkillData.Type.AOE
	skill.damage = 30
	skill.range = 500.0
	skill.cooldown = 0.0
	skill.mp_cost = 0

	await wait_physics_frames(2)
	executor.try_execute_skill(
		attacker, 10, 0, skill, Vector2.ZERO
	)

	assert_eq(
		enemy.hp, enemy.max_hp - skill.damage,
		"1v1 AOE should still hit enemy"
	)
