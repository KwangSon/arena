extends GutTest

const CHARACTER_SCENE: PackedScene = preload("res://src/character/character_base.tscn")

const REFEREE_PEER_ID: int = 1
const ATTACKER_ID: int = 2
const TARGET_ID: int = 3


func _make_executor(character_container: Node2D) -> SkillExecutor:
	var executor: SkillExecutor = SkillExecutor.new()
	var proj_spawner: MultiplayerSpawner = MultiplayerSpawner.new()
	character_container.get_parent().add_child(proj_spawner)
	var hit_area_container: Node2D = Node2D.new()
	character_container.get_parent().add_child(hit_area_container)
	var melee_spawner: MultiplayerSpawner = MultiplayerSpawner.new()
	character_container.get_parent().add_child(melee_spawner)
	melee_spawner.spawn_path = hit_area_container.get_path()
	executor.setup(character_container, proj_spawner, melee_spawner, REFEREE_PEER_ID)
	return executor


func _make_melee_skill(damage: int = 100, range_val: float = 300.0) -> SkillData:
	var skill: SkillData = SkillData.new()
	skill.id = "test_melee"
	skill.skill_type = SkillData.Type.MELEE
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


# --- CardDefinitions ---


func test_card_definitions_main_weapon_values() -> void:
	var card := CardDefinitions.get_main_weapon()
	assert_eq(card.slot, CardData.Slot.MAIN_WEAPON)
	assert_eq(card.damage_mult, 1.2)
	assert_eq(card.cooldown_mult, 0.85)


func test_card_definitions_sub_weapon_values() -> void:
	var card := CardDefinitions.get_sub_weapon()
	assert_eq(card.slot, CardData.Slot.SUB_WEAPON)
	assert_eq(card.damage_mult, 1.2)
	assert_eq(card.cooldown_mult, 0.85)


func test_card_definitions_armor_values() -> void:
	var card := CardDefinitions.get_armor()
	assert_eq(card.slot, CardData.Slot.ARMOR)
	assert_eq(card.max_hp_bonus, 20)
	assert_eq(card.damage_reduction, 0.15)


func test_card_definitions_shoes_values() -> void:
	var card := CardDefinitions.get_shoes()
	assert_eq(card.slot, CardData.Slot.SHOES)
	assert_eq(card.move_speed_mult, 1.2)
	assert_eq(card.bp_regen_mult, 1.5)


func test_card_definitions_ultimate_values() -> void:
	var card := CardDefinitions.get_ultimate()
	assert_eq(card.slot, CardData.Slot.ULTIMATE)
	assert_eq(card.cooldown_mult, 0.8)
	assert_eq(card.mp_cost_mult, 0.85)


func test_get_all_returns_five_cards() -> void:
	assert_eq(CardDefinitions.get_all().size(), 5)


func test_get_by_slot_returns_correct_card() -> void:
	var card := CardDefinitions.get_by_slot(CardData.Slot.ARMOR)
	assert_eq(card.slot, CardData.Slot.ARMOR)


# --- CharacterBase.equip_card / apply_equipped_cards ---


func test_equip_card_stores_in_equipped_cards() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var character: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var card := CardDefinitions.get_main_weapon()
	character.equip_card(card)
	assert_eq(character.equipped_cards[CardData.Slot.MAIN_WEAPON], card)


func test_apply_armor_card_increases_max_hp() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var character: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var base_hp: int = character.max_hp
	character.equip_card(CardDefinitions.get_armor())
	character.apply_equipped_cards()
	assert_eq(character.max_hp, base_hp + 20)
	assert_eq(character.hp, base_hp + 20)


func test_apply_armor_card_sets_damage_reduction() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var character: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	character.equip_card(CardDefinitions.get_armor())
	character.apply_equipped_cards()
	assert_eq(character.damage_reduction, 0.15)


func test_apply_shoes_card_increases_move_speed() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var character: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var base_speed: float = character._move_speed
	character.equip_card(CardDefinitions.get_shoes())
	character.apply_equipped_cards()
	assert_almost_eq(character._move_speed, base_speed * 1.2, 0.01)


func test_apply_shoes_card_increases_bp_regen() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var character: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var base_regen: float = character.bp_regen
	character.equip_card(CardDefinitions.get_shoes())
	character.apply_equipped_cards()
	assert_almost_eq(character.bp_regen, base_regen * 1.5, 0.01)


func test_no_cards_no_stat_change() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var character: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var base_hp: int = character.max_hp
	var base_speed: float = character._move_speed
	character.apply_equipped_cards()
	assert_eq(character.max_hp, base_hp)
	assert_eq(character._move_speed, base_speed)
	assert_eq(character.damage_reduction, 0.0)


# --- 전투 중 카드 효과 ---


func test_main_weapon_card_increases_melee_damage() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0), 2)
	attacker.equip_card(CardDefinitions.get_main_weapon())

	var skill: SkillData = _make_melee_skill(50)
	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)
	await wait_physics_frames(2)

	var expected_damage: int = int(50 * 1.2)  # 60
	assert_eq(target.hp, target.max_hp - expected_damage)  # 100 - 60 = 40


func test_armor_card_reduces_incoming_damage() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0), 2)
	target.equip_card(CardDefinitions.get_armor())
	target.apply_equipped_cards()

	var skill: SkillData = _make_melee_skill(100)
	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)
	await wait_physics_frames(2)

	var expected_damage: int = int(100 * (1.0 - 0.15))  # 85
	assert_eq(target.hp, target.max_hp - expected_damage)


func test_ultimate_card_reduces_cooldown() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0), 2)
	attacker.equip_card(CardDefinitions.get_ultimate())

	# 쿨다운 1.0초짜리 ultimate (skill_idx=2)
	var skill: SkillData = _make_melee_skill(10)
	skill.cooldown = 1.0

	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 2, skill, Vector2.RIGHT)
	await wait_physics_frames(2)
	var hp_after_first: int = target.hp

	# 즉시 재사용 — 카드 쿨다운(0.8초) 이내여서 막혀야 함
	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 2, skill, Vector2.RIGHT)
	assert_eq(target.hp, hp_after_first, "Cooldown should still block immediate reuse")


func test_ultimate_card_reduces_mp_cost() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	_spawn_character(root, TARGET_ID, Vector2(100.0, 0.0))
	attacker.equip_card(CardDefinitions.get_ultimate())

	attacker.mp = 50.0
	var skill: SkillData = _make_melee_skill(10)
	skill.mp_cost = 50  # base cost
	# 카드 적용 시 effective_cost = int(50 * 0.85) = 42

	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 2, skill, Vector2.RIGHT)
	assert_almost_eq(attacker.mp, 50.0 - 42.0, 0.01)


func _make_aoe_skill(damage: int = 100, range_val: float = 200.0) -> SkillData:
	var skill: SkillData = SkillData.new()
	skill.id = "test_aoe"
	skill.skill_type = SkillData.Type.AOE
	skill.damage = damage
	skill.range = range_val
	skill.cooldown = 0.0
	skill.mp_cost = 0
	return skill


func test_sub_weapon_card_increases_melee_damage() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0), 2)
	attacker.equip_card(CardDefinitions.get_sub_weapon())

	var skill: SkillData = _make_melee_skill(50)
	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 1, skill, Vector2.RIGHT)
	await wait_physics_frames(2)

	var expected_damage: int = int(50 * 1.2)  # 60
	assert_eq(target.hp, target.max_hp - expected_damage)


func test_aoe_skill_applies_weapon_damage_mult() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0))
	attacker.equip_card(CardDefinitions.get_main_weapon())

	var skill: SkillData = _make_aoe_skill(50, 300.0)
	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)

	var expected_damage: int = int(50 * 1.2)  # 60
	assert_eq(target.hp, target.max_hp - expected_damage)


func test_aoe_skill_hits_multiple_targets_in_range() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target_near1: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0))
	var target_near2: CharacterBase = _spawn_character(root, TARGET_ID + 1, Vector2(0.0, 100.0))
	var target_far: CharacterBase = _spawn_character(root, TARGET_ID + 2, Vector2(1000.0, 0.0))

	var skill: SkillData = _make_aoe_skill(30, 200.0)
	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.ZERO)

	assert_eq(target_near1.hp, target_near1.max_hp - 30, "range 안 타겟1은 피해를 받아야 함")
	assert_eq(target_near2.hp, target_near2.max_hp - 30, "range 안 타겟2는 피해를 받아야 함")
	assert_eq(target_far.hp, target_far.max_hp, "range 밖 타겟은 피해를 받으면 안 됨")


func test_combined_weapon_and_armor_reduces_net_damage() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0), 2)
	attacker.equip_card(CardDefinitions.get_main_weapon())  # damage_mult=1.2
	target.equip_card(CardDefinitions.get_armor())  # damage_reduction=0.15
	target.apply_equipped_cards()

	var skill: SkillData = _make_melee_skill(100)
	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)
	await wait_physics_frames(2)

	# raw=int(100*1.2)=120, final=int(120*(1-0.15))=102
	var expected_damage: int = int(int(100 * 1.2) * (1.0 - 0.15))
	assert_eq(target.hp, target.max_hp - expected_damage)


func test_wrong_slot_card_does_not_boost_damage() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0), 2)
	# ARMOR 카드를 장착하지만 skill_idx=0 → MAIN_WEAPON 슬롯 참조 → 카드 없음
	attacker.equip_card(CardDefinitions.get_armor())

	var skill: SkillData = _make_melee_skill(50)
	await wait_physics_frames(2)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)
	await wait_physics_frames(2)

	assert_eq(target.hp, target.max_hp - 50, "다른 슬롯 카드는 데미지에 영향 없어야 함")
