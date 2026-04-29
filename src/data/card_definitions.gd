class_name CardDefinitions


static func get_main_weapon() -> CardData:
	var card := CardData.new()
	card.id = "main_weapon"
	card.display_name = "강화 주무기"
	card.slot = CardData.Slot.MAIN_WEAPON
	card.damage_mult = 1.2
	card.cooldown_mult = 0.85
	return card


static func get_sub_weapon() -> CardData:
	var card := CardData.new()
	card.id = "sub_weapon"
	card.display_name = "강화 보조무기"
	card.slot = CardData.Slot.SUB_WEAPON
	card.damage_mult = 1.2
	card.cooldown_mult = 0.85
	return card


static func get_armor() -> CardData:
	var card := CardData.new()
	card.id = "armor"
	card.display_name = "방어 갑옷"
	card.slot = CardData.Slot.ARMOR
	card.max_hp_bonus = 20
	card.damage_reduction = 0.15
	return card


static func get_shoes() -> CardData:
	var card := CardData.new()
	card.id = "shoes"
	card.display_name = "질주 신발"
	card.slot = CardData.Slot.SHOES
	card.move_speed_mult = 1.2
	card.bp_regen_mult = 1.5
	return card


static func get_ultimate() -> CardData:
	var card := CardData.new()
	card.id = "ultimate"
	card.display_name = "강화 궁극기"
	card.slot = CardData.Slot.ULTIMATE
	card.cooldown_mult = 0.8
	card.mp_cost_mult = 0.85
	return card


static func get_all() -> Array[CardData]:
	return [get_main_weapon(), get_sub_weapon(), get_armor(), get_shoes(), get_ultimate()]


static func get_by_slot(slot: CardData.Slot) -> CardData:
	match slot:
		CardData.Slot.MAIN_WEAPON:
			return get_main_weapon()
		CardData.Slot.SUB_WEAPON:
			return get_sub_weapon()
		CardData.Slot.ARMOR:
			return get_armor()
		CardData.Slot.SHOES:
			return get_shoes()
		CardData.Slot.ULTIMATE:
			return get_ultimate()
	assert(false, "CardDefinitions.get_by_slot: unknown slot %d" % slot)
	return CardData.new()
