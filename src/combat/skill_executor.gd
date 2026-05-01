class_name SkillExecutor extends RefCounted

signal hit_occurred(attacker_id: int, target_id: int, damage: int, skill_id: String)
signal character_died(loser_id: int, winner_id: int)

const PROJECTILE_SCENE: PackedScene = preload("res://src/combat/projectile.tscn")
const HIT_AREA_SCENE: PackedScene = preload("res://src/combat/hit_area.tscn")
const _TEAM_COLORS: Array[Color] = [
	Color(0.5, 0.5, 0.5),
	Color(0.3, 0.5, 1.0),
	Color(1.0, 0.3, 0.3),
]

var _character_container: Node2D
var _projectile_spawner: MultiplayerSpawner
var _hit_area_spawner: MultiplayerSpawner
var _referee_peer_id: int
var _skill_last_used: Dictionary = {}


func setup(
	character_container: Node2D,
	projectile_spawner: MultiplayerSpawner,
	hit_area_spawner: MultiplayerSpawner,
	referee_peer_id: int
) -> void:
	assert(character_container != null, "SkillExecutor.setup: character_container is null")
	assert(projectile_spawner != null, "SkillExecutor.setup: projectile_spawner is null")
	assert(hit_area_spawner != null, "SkillExecutor.setup: hit_area_spawner is null")
	_character_container = character_container
	_projectile_spawner = projectile_spawner
	_hit_area_spawner = hit_area_spawner
	_referee_peer_id = referee_peer_id
	_projectile_spawner.spawn_function = create_projectile_node
	_hit_area_spawner.spawn_function = create_hit_area_node


func try_execute_skill(
	attacker: CharacterBase, attacker_id: int, skill_idx: int, skill: SkillData, direction: Vector2
) -> void:
	assert(attacker != null, "SkillExecutor.try_execute_skill: attacker is null")
	assert(skill != null, "SkillExecutor.try_execute_skill: skill is null")

	if not _skill_last_used.has(attacker_id):
		_skill_last_used[attacker_id] = {}
	var peer_cooldowns: Dictionary = _skill_last_used[attacker_id]
	var now: float = Time.get_ticks_msec() / 1000.0

	var card_slot: CardData.Slot = _skill_idx_to_card_slot(skill_idx)
	var card: CardData = attacker.equipped_cards.get(card_slot) as CardData

	var effective_cooldown: float = skill.cooldown * (card.cooldown_mult if card != null else 1.0)
	if peer_cooldowns.has(skill_idx) and now - peer_cooldowns[skill_idx] < effective_cooldown:
		return

	var effective_mp_cost: int = int(skill.mp_cost * (card.mp_cost_mult if card != null else 1.0))
	if attacker.mp < effective_mp_cost:
		return

	attacker.mp -= effective_mp_cost
	peer_cooldowns[skill_idx] = now

	match skill.skill_type:
		SkillData.Type.MELEE:
			_execute_melee(attacker, attacker_id, skill, card_slot)
		SkillData.Type.AOE:
			_execute_aoe(attacker, attacker_id, skill, card_slot)
		SkillData.Type.PROJECTILE:
			_execute_projectile(attacker, attacker_id, skill, direction, card_slot)


func clear_peer(peer_id: int) -> void:
	_skill_last_used.erase(peer_id)


func create_hit_area_node(data: Variant) -> Node:
	assert(data is Dictionary, "SkillExecutor: hit area spawn data must be a Dictionary")
	var d: Dictionary = data

	var area := HIT_AREA_SCENE.instantiate() as HitArea
	assert(area != null, "SkillExecutor: failed to instantiate HitArea scene")

	area.position = d["position"]
	area.attacker_id = d["attacker_id"]
	area.damage = d["damage"]
	area.skill_id = d["skill_id"]
	area.knockback_power = d.get("knockback_power", 0.0)
	area.set_multiplayer_authority(_referee_peer_id)
	area.setup(
		d["radius"], Color(d["color_r"], d["color_g"], d["color_b"], 0.35), d["collision_mask"]
	)

	var err := area.body_hit.connect(_on_melee_body_hit)
	assert(err == OK, "SkillExecutor: failed to connect melee body_hit: %d" % err)

	return area


func create_projectile_node(data: Variant) -> Node:
	assert(data is Dictionary, "SkillExecutor: projectile spawn data must be a Dictionary")
	var spawn_data: Dictionary = data

	var projectile: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	assert(projectile != null, "SkillExecutor: failed to instantiate Projectile scene")

	projectile.attacker_id = spawn_data["attacker_id"]
	projectile.damage = spawn_data["damage"]
	projectile.skill_id = spawn_data["skill_id"]
	projectile.knockback_power = spawn_data.get("knockback_power", 0.0)
	projectile.position = spawn_data["position"]
	projectile.setup(spawn_data["direction"], spawn_data["speed"], spawn_data["range"])
	projectile.collision_layer = 0
	projectile.collision_mask = spawn_data.get("collision_mask", 1)
	projectile.set_multiplayer_authority(_referee_peer_id)
	_setup_projectile_synchronizer(projectile)

	var err: int = projectile.body_hit.connect(_on_projectile_body_hit)
	assert(err == OK, "SkillExecutor: failed to connect projectile body_hit: %d" % err)

	return projectile


func _execute_melee(
	attacker: CharacterBase, attacker_id: int, skill: SkillData, card_slot: CardData.Slot
) -> void:
	var card: CardData = attacker.equipped_cards.get(card_slot) as CardData
	var effective_damage: int = int(skill.damage * (card.damage_mult if card != null else 1.0))
	var enemy_layer: int = 2 if attacker.team_id == 1 else 1
	var team_color: Color = _TEAM_COLORS[clampi(attacker.team_id, 0, _TEAM_COLORS.size() - 1)]

	(
		_hit_area_spawner
		. spawn(
			{
				"position": attacker.global_position,
				"attacker_id": attacker_id,
				"damage": effective_damage,
				"skill_id": skill.id,
				"knockback_power": skill.knockback_power,
				"radius": skill.range,
				"collision_mask": enemy_layer,
				"color_r": team_color.r,
				"color_g": team_color.g,
				"color_b": team_color.b,
			}
		)
	)


func _execute_aoe(
	attacker: CharacterBase, attacker_id: int, skill: SkillData, card_slot: CardData.Slot
) -> void:
	for child in _character_container.get_children():
		var target: CharacterBase = child as CharacterBase
		assert(target != null, "SkillExecutor: expected CharacterBase under CharacterContainer")
		if target == attacker:
			continue
		var dist: float = attacker.global_position.distance_to(target.global_position)
		if dist <= skill.range:
			var dir: Vector2 = (target.global_position - attacker.global_position).normalized()
			_apply_damage(attacker_id, int(target.name), target, skill, attacker, card_slot, dir)


func _execute_projectile(
	attacker: CharacterBase,
	attacker_id: int,
	skill: SkillData,
	direction: Vector2,
	card_slot: CardData.Slot,
) -> void:
	var card: CardData = attacker.equipped_cards.get(card_slot) as CardData
	var effective_damage: int = (
		int(skill.damage * card.damage_mult) if card != null else skill.damage
	)

	var enemy_layer: int = 2 if attacker.team_id == 1 else 1
	(
		_projectile_spawner
		. spawn(
			{
				"attacker_id": attacker_id,
				"position": attacker.global_position,
				"direction": direction,
				"damage": effective_damage,
				"speed": skill.projectile_speed,
				"range": skill.range,
				"skill_id": skill.id,
				"knockback_power": skill.knockback_power,
				"collision_mask": enemy_layer,
			}
		)
	)


func _on_melee_body_hit(hit_area: HitArea, body: Node2D) -> void:
	var target := body as CharacterBase
	if target == null:
		return
	var dummy_skill := SkillData.new()
	dummy_skill.damage = hit_area.damage
	dummy_skill.id = hit_area.skill_id
	dummy_skill.knockback_power = hit_area.knockback_power
	var dir: Vector2 = (target.global_position - hit_area.global_position).normalized()
	_apply_damage(hit_area.attacker_id, int(target.name), target, dummy_skill, null, CardData.Slot.MAIN_WEAPON, dir)


func _on_projectile_body_hit(projectile: Projectile, body: Node2D) -> void:
	var target: CharacterBase = body as CharacterBase
	if target == null:
		return
	var dummy_skill := SkillData.new()
	dummy_skill.damage = projectile.damage
	dummy_skill.id = projectile.skill_id
	dummy_skill.knockback_power = projectile.knockback_power
	var dir: Vector2 = projectile._direction
	_apply_damage(projectile.attacker_id, int(target.name), target, dummy_skill, null, CardData.Slot.MAIN_WEAPON, dir)


func _apply_damage(
	attacker_id: int,
	target_id: int,
	target: CharacterBase,
	skill: SkillData,
	attacker: CharacterBase = null,
	card_slot: CardData.Slot = CardData.Slot.MAIN_WEAPON,
	knockback_dir: Vector2 = Vector2.ZERO
) -> void:
	var raw_damage: int = skill.damage
	if attacker != null:
		var card: CardData = attacker.equipped_cards.get(card_slot) as CardData
		if card != null:
			raw_damage = int(raw_damage * card.damage_mult)
	var final_damage: int = max(0, int(raw_damage * (1.0 - target.damage_reduction)))
	target.hp = max(0, target.hp - final_damage)
	
	if skill.knockback_power > 0.0 and knockback_dir != Vector2.ZERO:
		target.apply_knockback(knockback_dir * skill.knockback_power)
		
	hit_occurred.emit(attacker_id, target_id, final_damage, skill.id)
	if target.hp <= 0:
		character_died.emit(target_id, _find_first_alive_except(target_id))


func _skill_idx_to_card_slot(skill_idx: int) -> CardData.Slot:
	match skill_idx:
		0:
			return CardData.Slot.MAIN_WEAPON
		1:
			return CardData.Slot.SUB_WEAPON
		2:
			return CardData.Slot.ULTIMATE
	assert(false, "SkillExecutor._skill_idx_to_card_slot: unknown skill_idx %d" % skill_idx)
	return CardData.Slot.MAIN_WEAPON


func _find_first_alive_except(excluded_id: int) -> int:
	for child in _character_container.get_children():
		var character: CharacterBase = child as CharacterBase
		assert(character != null, "SkillExecutor: expected CharacterBase under CharacterContainer")
		var peer_id: int = int(character.name)
		if peer_id != excluded_id:
			return peer_id
	return -1


func _setup_projectile_synchronizer(projectile: Node2D) -> void:
	var synchronizer: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = "StateSynchronizer"
	synchronizer.root_path = NodePath("..")
	synchronizer.replication_interval = 0.0
	synchronizer.delta_interval = 0.0
	synchronizer.set_multiplayer_authority(_referee_peer_id)

	var replication_config: SceneReplicationConfig = SceneReplicationConfig.new()
	var pos_path := NodePath(".:position")
	replication_config.add_property(pos_path)
	replication_config.property_set_spawn(pos_path, true)
	replication_config.property_set_replication_mode(
		pos_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS
	)

	synchronizer.replication_config = replication_config
	projectile.add_child(synchronizer, true)
