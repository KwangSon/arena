extends GutTest

const PlayerDataScript: GDScript = preload("res://src/global/player_data.gd")

var _pd  # Node — PlayerData instance


func before_each() -> void:
	_pd = add_child_autofree(PlayerDataScript.new())
	assert(_pd != null, "test_player_data: failed to create PlayerData")


func test_initial_gold() -> void:
	assert_eq(_pd.gold, PlayerDataScript.STARTING_GOLD)


func test_initial_no_owned_cards() -> void:
	assert_eq(_pd.owned_card_ids.size(), 0)


func test_buy_card_success() -> void:
	var card: CardData = CardDefinitions.get_armor()
	_pd.gold = card.cost
	var result: bool = _pd.buy_card(card.id)
	assert_true(result, "buy should succeed when gold == cost")
	assert_eq(_pd.gold, 0)
	assert_true(_pd.owned_card_ids.has(card.id))


func test_buy_card_deducts_gold() -> void:
	var card: CardData = CardDefinitions.get_shoes()
	_pd.gold = card.cost + 100
	_pd.buy_card(card.id)
	assert_eq(_pd.gold, 100)


func test_buy_card_insufficient_gold() -> void:
	var card: CardData = CardDefinitions.get_main_weapon()
	_pd.gold = card.cost - 1
	var result: bool = _pd.buy_card(card.id)
	assert_false(result, "buy should fail when gold < cost")
	assert_false(_pd.owned_card_ids.has(card.id))
	assert_eq(_pd.gold, card.cost - 1, "gold unchanged on failed buy")


func test_buy_card_already_owned() -> void:
	var card: CardData = CardDefinitions.get_armor()
	_pd.gold = card.cost * 3
	_pd.buy_card(card.id)
	var gold_after_first: int = _pd.gold
	var result: bool = _pd.buy_card(card.id)
	assert_false(result, "buy should fail when already owned")
	assert_eq(_pd.owned_card_ids.size(), 1, "no duplicate entries")
	assert_eq(_pd.gold, gold_after_first, "gold unchanged on duplicate buy")


func test_equip_and_get_card() -> void:
	_pd.owned_card_ids.append("armor")
	_pd.equip_card(CardData.Slot.ARMOR, "armor")
	assert_eq(_pd.get_equipped_card_id(CardData.Slot.ARMOR), "armor")


func test_empty_slot_returns_empty_string() -> void:
	assert_eq(_pd.get_equipped_card_id(CardData.Slot.MAIN_WEAPON), "")


func test_unequip_slot() -> void:
	_pd.owned_card_ids.append("shoes")
	_pd.equip_card(CardData.Slot.SHOES, "shoes")
	_pd.unequip_slot(CardData.Slot.SHOES)
	assert_eq(_pd.get_equipped_card_id(CardData.Slot.SHOES), "")


func test_get_equipped_card_ids() -> void:
	_pd.owned_card_ids.append("armor")
	_pd.owned_card_ids.append("shoes")
	_pd.equip_card(CardData.Slot.ARMOR, "armor")
	_pd.equip_card(CardData.Slot.SHOES, "shoes")
	var ids: Array[String] = _pd.get_equipped_card_ids()
	assert_eq(ids.size(), 2)
	assert_true(ids.has("armor"))
	assert_true(ids.has("shoes"))


func test_get_equipped_card_ids_empty() -> void:
	var ids: Array[String] = _pd.get_equipped_card_ids()
	assert_eq(ids.size(), 0)


func test_get_owned_cards_for_slot() -> void:
	_pd.owned_card_ids.append("armor")
	_pd.owned_card_ids.append("shoes")
	var armor_cards: Array[CardData] = _pd.get_owned_cards_for_slot(CardData.Slot.ARMOR)
	assert_eq(armor_cards.size(), 1)
	assert_eq(armor_cards[0].id, "armor")


func test_get_owned_cards_for_slot_empty() -> void:
	var cards: Array[CardData] = _pd.get_owned_cards_for_slot(CardData.Slot.MAIN_WEAPON)
	assert_eq(cards.size(), 0)
