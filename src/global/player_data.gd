## Autoload — 플레이어 인게임 데이터. 골드, 보유 카드, 장착 카드를 관리한다.
extends Node

const STARTING_GOLD: int = 2000

var gold: int = STARTING_GOLD
var owned_card_ids: Array[String] = []

## int(CardData.Slot) -> String card_id
var _equipped: Dictionary = {}


func buy_card(card_id: String) -> bool:
	var card: CardData = _find_card(card_id)
	assert(card != null, "PlayerData.buy_card: unknown card_id %s" % card_id)
	if gold < card.cost or owned_card_ids.has(card_id):
		return false
	gold -= card.cost
	owned_card_ids.append(card_id)
	return true


func equip_card(slot: CardData.Slot, card_id: String) -> void:
	assert(owned_card_ids.has(card_id), "PlayerData.equip_card: card not owned %s" % card_id)
	_equipped[int(slot)] = card_id


func unequip_slot(slot: CardData.Slot) -> void:
	_equipped.erase(int(slot))


func get_equipped_card_id(slot: CardData.Slot) -> String:
	return _equipped.get(int(slot), "")


func get_equipped_card_ids() -> Array[String]:
	var result: Array[String] = []
	for card_id: Variant in _equipped.values():
		result.append(str(card_id))
	return result


func get_owned_cards_for_slot(slot: CardData.Slot) -> Array[CardData]:
	var result: Array[CardData] = []
	for card_id: String in owned_card_ids:
		var card: CardData = _find_card(card_id)
		if card != null and card.slot == slot:
			result.append(card)
	return result


func load_from_nakama(profile: Dictionary, deck: Dictionary) -> void:
	gold = int(profile.get("gold", STARTING_GOLD))
	owned_card_ids.clear()
	for id: Variant in profile.get("owned_card_ids", []):
		owned_card_ids.append(str(id))
	_equipped.clear()
	for slot_str: Variant in deck.get("equipped", {}).keys():
		_equipped[int(str(slot_str))] = str(deck["equipped"][slot_str])


func _find_card(card_id: String) -> CardData:
	for card: CardData in CardDefinitions.get_all():
		if card.id == card_id:
			return card
	return null
