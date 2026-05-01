extends GutTest

const CHARACTER_SCENE: PackedScene = preload("res://src/character/character_base.tscn")

const REFEREE_PEER_ID: int = 1
const ATTACKER_ID: int = 2
const TARGET_ID: int = 3


func _make_executor(character_container: Node2D) -> SkillExecutor:
	var executor: SkillExecutor = SkillExecutor.new()
	var proj_spawner: MultiplayerSpawner = MultiplayerSpawner.new()
	# Spawners are siblings of character_container to avoid AOE's CharacterBase assert.
	character_container.get_parent().add_child(proj_spawner)
	var hit_area_container: Node2D = Node2D.new()
	character_container.get_parent().add_child(hit_area_container)
	var melee_spawner: MultiplayerSpawner = MultiplayerSpawner.new()
	character_container.get_parent().add_child(melee_spawner)
	melee_spawner.spawn_path = hit_area_container.get_path()
	executor.setup(character_container, proj_spawner, melee_spawner, REFEREE_PEER_ID)
	return executor


func _make_melee_skill(
	damage: int = 10, range_val: float = 200.0, cooldown: float = 0.0
) -> SkillData:
	var skill: SkillData = SkillData.new()
	skill.id = "melee_test"
	skill.skill_type = SkillData.Type.MELEE
	skill.damage = damage
	skill.range = range_val
	skill.cooldown = cooldown
	skill.mp_cost = 0
	return skill


func _make_aoe_skill(damage: int = 10, range_val: float = 500.0) -> SkillData:
	var skill: SkillData = SkillData.new()
	skill.id = "aoe_test"
	skill.skill_type = SkillData.Type.AOE
	skill.damage = damage
	skill.range = range_val
	skill.cooldown = 0.0
	skill.mp_cost = 0
	return skill


func _spawn_character(root: Node2D, peer_id: int, pos: Vector2, team: int = 1) -> CharacterBase:
	var character: CharacterBase = CHARACTER_SCENE.instantiate() as CharacterBase
	character.name = str(peer_id)
	character.team_id = team
	character.collision_layer = team
	character.collision_mask = 1 | 2
	character.position = pos
	root.add_child(character)
	return character


func test_melee_hits_nearby_target() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)
	watch_signals(executor)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0), 2)
	var skill: SkillData = _make_melee_skill(10, 200.0)

	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)

	assert_eq(target.hp, target.max_hp - skill.damage, "Target should take damage from melee")
	assert_signal_emitted(executor, "hit_occurred")


func test_melee_misses_target_out_of_range() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)
	watch_signals(executor)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(500.0, 0.0), 2)
	var skill: SkillData = _make_melee_skill(10, 100.0)

	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)

	assert_eq(target.hp, target.max_hp, "Target should not take damage when out of range")
	assert_signal_not_emitted(executor, "hit_occurred")


func test_aoe_hits_all_targets_in_range() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target_a: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0))
	var target_b: CharacterBase = _spawn_character(root, 4, Vector2(-100.0, 0.0))
	var skill: SkillData = _make_aoe_skill(10, 500.0)

	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.ZERO)

	assert_eq(target_a.hp, target_a.max_hp - skill.damage)
	assert_eq(target_b.hp, target_b.max_hp - skill.damage)


func test_cooldown_blocks_repeated_skill_use() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0), 2)
	var skill: SkillData = _make_melee_skill(10, 200.0, 999.0)

	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)
	var hp_after_first: int = target.hp
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)

	assert_eq(target.hp, hp_after_first, "Second use should be blocked by cooldown")


func test_clear_peer_resets_cooldown() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0), 2)
	var skill: SkillData = _make_melee_skill(10, 200.0, 999.0)

	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)
	executor.clear_peer(ATTACKER_ID)
	var hp_before: int = target.hp
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)

	assert_eq(target.hp, hp_before - skill.damage, "Cooldown should be reset after clear_peer")


func test_insufficient_mp_blocks_skill() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0))
	attacker.mp = 0.0

	var skill: SkillData = _make_melee_skill(10, 200.0)
	skill.mp_cost = 50

	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)

	assert_eq(target.hp, target.max_hp, "Skill should not fire when attacker has insufficient MP")


func test_skill_deducts_mp_cost() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	_spawn_character(root, TARGET_ID, Vector2(100.0, 0.0))
	attacker.mp = 80.0

	var skill: SkillData = _make_melee_skill(10, 200.0)
	skill.mp_cost = 30

	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)

	assert_eq(attacker.mp, 50.0)


func test_character_died_signal_emitted_when_hp_reaches_zero() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)
	watch_signals(executor)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0), 2)
	target.hp = 1

	var skill: SkillData = _make_melee_skill(100, 200.0)
	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)

	assert_signal_emitted(executor, "character_died")


func test_melee_does_not_hit_self() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)
	watch_signals(executor)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var skill: SkillData = _make_melee_skill(10, 9999.0)

	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)

	assert_eq(attacker.hp, attacker.max_hp, "Attacker should not damage itself")
	assert_signal_not_emitted(executor, "hit_occurred")
