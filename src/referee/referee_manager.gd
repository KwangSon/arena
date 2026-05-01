## Referee-only 게임 로직. MatchSession의 자식으로 referee 인스턴스에만 생성된다.
class_name RefereeManager extends Node

signal hit_occurred(attacker_id: int, target_id: int, damage: int, skill_id: String)
signal match_result_ready(winner_team: int, loser_id: int, winner_id: int)

const REFEREE_PEER_ID: int = 1
const BP_DASH_DRAIN_PER_SEC: float = 25.0
const DISCONNECT_GRACE_PERIOD_SEC: float = 10.0

var _character_container: Node2D
var _spawner: MultiplayerSpawner
var _match_id: String
var _orchestrator_url: String
var _referee_port: int

var _skill_executor: SkillExecutor
var _move_inputs: Dictionary = {}
var _disconnect_deadlines: Dictionary = {}


func setup(
	character_container: Node2D,
	spawner: MultiplayerSpawner,
	projectile_spawner: MultiplayerSpawner,
	melee_hit_spawner: MultiplayerSpawner,
	match_id: String,
	orchestrator_url: String,
	referee_port: int,
) -> void:
	assert(character_container != null, "RefereeManager.setup: character_container is null")
	assert(spawner != null, "RefereeManager.setup: spawner is null")
	assert(projectile_spawner != null, "RefereeManager.setup: projectile_spawner is null")
	assert(melee_hit_spawner != null, "RefereeManager.setup: melee_hit_spawner is null")

	_character_container = character_container
	_spawner = spawner
	_match_id = match_id
	_orchestrator_url = orchestrator_url
	_referee_port = referee_port

	_skill_executor = SkillExecutor.new()
	_skill_executor.setup(
		_character_container, projectile_spawner, melee_hit_spawner, REFEREE_PEER_ID
	)

	var err: int = _skill_executor.hit_occurred.connect(_on_skill_hit_occurred)
	assert(err == OK, "RefereeManager: failed to connect hit_occurred: %d" % err)
	err = _skill_executor.character_died.connect(_on_character_died)
	assert(err == OK, "RefereeManager: failed to connect character_died: %d" % err)

	report_ready()


func report_ready() -> void:
	if _orchestrator_url.is_empty() or _match_id.is_empty():
		return
	var http := HTTPRequest.new()
	http.name = "ReadyHTTP"
	add_child(http)
	var body := JSON.stringify({"port": _referee_port})
	var err := (
		http
		. request(
			"%s/match/%s/ready" % [_orchestrator_url, _match_id],
			["Content-Type: application/json"],
			HTTPClient.METHOD_POST,
			body,
		)
	)
	if err != OK:
		push_error("[RefereeManager] Failed to POST /ready: %d" % err)


func report_result(winner_team: int) -> void:
	if _orchestrator_url.is_empty() or _match_id.is_empty():
		return
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"winner_team": winner_team, "player_stats": []})
	(
		http
		. request(
			"%s/match/%s/result" % [_orchestrator_url, _match_id],
			["Content-Type: application/json"],
			HTTPClient.METHOD_POST,
			body,
		)
	)


func on_peer_connected(peer_id: int) -> void:
	if _disconnect_deadlines.has(peer_id):
		_disconnect_deadlines.erase(peer_id)
		_move_inputs[peer_id] = Vector2.ZERO


func set_character_choice(
	peer_id: int, character_id: String, equipped_card_ids: Array[String] = []
) -> void:
	_spawn_character(peer_id, character_id, equipped_card_ids)


func on_peer_disconnected(peer_id: int) -> void:
	_move_inputs.erase(peer_id)
	_disconnect_deadlines[peer_id] = Time.get_ticks_msec() / 1000.0 + DISCONNECT_GRACE_PERIOD_SEC
	var character: CharacterBase = _find_character_by_peer_id(peer_id)
	if character != null:
		character.set_move_input(Vector2.ZERO)


func set_move_input(peer_id: int, input_vector: Vector2) -> void:
	_move_inputs[peer_id] = input_vector.limit_length()
	_disconnect_deadlines.erase(peer_id)


func set_dashing(peer_id: int) -> void:
	var character: CharacterBase = _find_character_by_peer_id(peer_id)
	if character == null or character.bp <= 0.0:
		return
	character.is_dashing = true


func execute_skill(peer_id: int, skill_idx: int, direction: Vector2) -> void:
	assert(
		skill_idx >= 0 and skill_idx <= 2,
		"RefereeManager.execute_skill: invalid idx %d" % skill_idx
	)
	var attacker: CharacterBase = _find_character_by_peer_id(peer_id)
	if attacker == null:
		return
	var char_data: CharacterData = attacker.get("_character_data") as CharacterData
	if char_data == null:
		return
	var skills: Array = [char_data.skill_1, char_data.skill_2, char_data.ultimate]
	var skill: SkillData = skills[skill_idx] as SkillData
	assert(
		skill != null,
		"RefereeManager.execute_skill: skill %d null for peer %d" % [skill_idx, peer_id]
	)
	_skill_executor.try_execute_skill(attacker, peer_id, skill_idx, skill, direction)


func simulate_movement(delta: float) -> void:
	for child in _character_container.get_children():
		var character: CharacterBase = child as CharacterBase
		assert(character != null, "RefereeManager: expected CharacterBase under CharacterContainer")
		var peer_id: int = int(character.name)
		var input_vector: Vector2 = _move_inputs.get(peer_id, Vector2.ZERO)
		character.set_move_input(input_vector)
		if character.is_dashing:
			if input_vector == Vector2.ZERO:
				character.is_dashing = false
			else:
				character.bp = maxf(0.0, character.bp - BP_DASH_DRAIN_PER_SEC * delta)
				if character.bp <= 0.0:
					character.is_dashing = false
		else:
			character.bp = minf(character.max_bp, character.bp + character.bp_regen * delta)
			character.mp = minf(character.max_mp, character.mp + character.mp_regen * delta)


func process_disconnect_timeouts(match_ended: bool) -> void:
	var now_sec: float = Time.get_ticks_msec() / 1000.0
	var timed_out: Array[int] = []
	for peer_id_variant in _disconnect_deadlines.keys():
		var peer_id: int = int(peer_id_variant)
		if now_sec >= _disconnect_deadlines[peer_id]:
			timed_out.append(peer_id)
	for peer_id in timed_out:
		_handle_disconnect_timeout(peer_id, match_ended)


func remove_character(peer_id: int) -> void:
	_disconnect_deadlines.erase(peer_id)
	_move_inputs.erase(peer_id)
	_skill_executor.clear_peer(peer_id)
	for child in _character_container.get_children():
		if child.name == str(peer_id):
			child.queue_free()
			return


# ============================================================
# Private
# ============================================================


func _spawn_character(
	peer_id: int, character_id: String = "", equipped_card_ids: Array[String] = []
) -> void:
	for child in _character_container.get_children():
		if child.name == str(peer_id):
			return
	var spawn_count: int = _character_container.get_child_count()
	var team_id: int = 1 if spawn_count % 2 == 0 else 2
	if character_id.is_empty():
		character_id = "knight" if spawn_count % 2 == 0 else "mage"
	var position: Vector2 = _get_spawn_position(spawn_count, team_id)
	var spawn_data: Dictionary = {
		"peer_id": peer_id,
		"position": position,
		"character_id": character_id,
		"team_id": team_id,
	}
	var character: Node = _spawner.spawn(spawn_data)
	assert(character != null, "RefereeManager: failed to spawn for peer %d" % peer_id)
	var char_base: CharacterBase = character as CharacterBase
	assert(char_base != null, "RefereeManager: spawned node is not CharacterBase")
	if equipped_card_ids.is_empty():
		_equip_demo_cards(char_base, character_id)
	else:
		_equip_actual_cards(char_base, equipped_card_ids)
	print("[RefereeManager] Spawned %s for peer %d at %s" % [character_id, peer_id, position])


func _equip_actual_cards(character: CharacterBase, card_ids: Array[String]) -> void:
	for card_id: String in card_ids:
		var card: CardData = _find_card_def(card_id)
		if card != null:
			character.equip_card(card)
	character.apply_equipped_cards()


func _find_card_def(card_id: String) -> CardData:
	for card: CardData in CardDefinitions.get_all():
		if card.id == card_id:
			return card
	return null


func _equip_demo_cards(character: CharacterBase, character_id: String) -> void:
	if character_id == "knight":
		character.equip_card(CardDefinitions.get_main_weapon())
		character.equip_card(CardDefinitions.get_armor())
	else:
		character.equip_card(CardDefinitions.get_shoes())
		character.equip_card(CardDefinitions.get_ultimate())
	character.apply_equipped_cards()


func _get_spawn_position(spawn_count: int, team_id: int) -> Vector2:
	var team_slot: int = spawn_count / 2
	if team_id == 1:
		match team_slot:
			0:
				return Vector2(150, 250)
			1:
				return Vector2(150, 420)
			_:
				return Vector2(150, 250 + 120 * team_slot)
	match team_slot:
		0:
			return Vector2(650, 250)
		1:
			return Vector2(650, 420)
		_:
			return Vector2(650, 250 + 120 * team_slot)


func _handle_disconnect_timeout(peer_id: int, match_ended: bool) -> void:
	if match_ended:
		return
	_disconnect_deadlines.erase(peer_id)
	_move_inputs.erase(peer_id)
	var winner_id: int = _find_first_peer_id_except(peer_id)
	var winner_char: CharacterBase = _find_character_by_peer_id(winner_id)
	var winner_team: int = winner_char.team_id if winner_char != null else -1
	match_result_ready.emit(winner_team, peer_id, winner_id)
	remove_character(peer_id)


func _find_character_by_peer_id(peer_id: int) -> CharacterBase:
	for child in _character_container.get_children():
		if child.name == str(peer_id):
			return child as CharacterBase
	return null


func _find_first_peer_id_except(excluded: int) -> int:
	for child in _character_container.get_children():
		var character: CharacterBase = child as CharacterBase
		assert(character != null, "RefereeManager: expected CharacterBase")
		var peer_id: int = int(character.name)
		if peer_id != excluded:
			return peer_id
	return -1


func _on_skill_hit_occurred(
	attacker_id: int, target_id: int, damage: int, skill_id: String
) -> void:
	hit_occurred.emit(attacker_id, target_id, damage, skill_id)


func _on_character_died(loser_id: int, winner_id: int) -> void:
	var winner_char: CharacterBase = _find_character_by_peer_id(winner_id)
	var winner_team: int = winner_char.team_id if winner_char != null else -1
	report_result(winner_team)
	match_result_ready.emit(winner_team, loser_id, winner_id)
