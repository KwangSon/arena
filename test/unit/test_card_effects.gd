extends GutTest

const CHARACTER_SCENE: PackedScene = preload("res://src/character/character_base.tscn")

const REFEREE_PEER_ID: int = 1
const ATTACKER_ID: int = 2
const TARGET_ID: int = 3


func _make_executor(character_container: Node2D) -> SkillExecutor:
	var executor: SkillExecutor = SkillExecutor.new()
	var spawner: MultiplayerSpawner = MultiplayerSpawner.new()
	character_container.get_parent().add_child(spawner)
	executor.setup(character_container, spawner, REFEREE_PEER_ID)
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
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0))
	attacker.equip_card(CardDefinitions.get_main_weapon())

	var skill: SkillData = _make_melee_skill(50)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)

	var expected_damage: int = int(50 * 1.2)  # 60
	assert_eq(target.hp, target.max_hp - expected_damage)  # 100 - 60 = 40


func test_armor_card_reduces_incoming_damage() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0))
	target.equip_card(CardDefinitions.get_armor())
	target.apply_equipped_cards()

	var skill: SkillData = _make_melee_skill(100)
	executor.try_execute_skill(attacker, ATTACKER_ID, 0, skill, Vector2.RIGHT)

	var expected_damage: int = int(100 * (1.0 - 0.15))  # 85
	assert_eq(target.hp, target.max_hp - expected_damage)


func test_ultimate_card_reduces_cooldown() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var executor: SkillExecutor = _make_executor(root)

	var attacker: CharacterBase = _spawn_character(root, ATTACKER_ID, Vector2.ZERO)
	var target: CharacterBase = _spawn_character(root, TARGET_ID, Vector2(100.0, 0.0))
	attacker.equip_card(CardDefinitions.get_ultimate())

	# 쿨다운 1.0초짜리 ultimate (skill_idx=2)
	var skill: SkillData = _make_melee_skill(10)
	skill.cooldown = 1.0

	executor.try_execute_skill(attacker, ATTACKER_ID, 2, skill, Vector2.RIGHT)
	var hp_after_first: int = target.hp

	# 즉시 재사용 — 카드 없이는 막히지만, 카드 쿨다운(0.8초) 이내여서 막혀야 함
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

	executor.try_execute_skill(attacker, ATTACKER_ID, 2, skill, Vector2.RIGHT)
	assert_almost_eq(attacker.mp, 50.0 - 42.0, 0.01)
