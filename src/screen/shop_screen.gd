class_name ShopScreen extends Node2D

signal return_to_lobby_requested

var _canvas: CanvasLayer
var _gold_label: Label
var _buy_buttons: Array[Button] = []


func _ready() -> void:
	_setup_ui()


func initialize(_data: Dictionary) -> void:
	pass


func _setup_ui() -> void:
	_canvas = CanvasLayer.new()
	add_child(_canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(root)

	var title := Label.new()
	title.text = "상점"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 20
	title.offset_bottom = 70
	root.add_child(title)

	_gold_label = Label.new()
	_gold_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_gold_label.offset_left = -200
	_gold_label.offset_top = 20
	_gold_label.offset_right = -20
	_gold_label.offset_bottom = 55
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_gold_label)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 80
	scroll.offset_bottom = -70
	root.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	for card: CardData in CardDefinitions.get_all():
		vbox.add_child(_build_card_row(card))

	var back_btn := Button.new()
	back_btn.text = "돌아가기"
	back_btn.custom_minimum_size = Vector2(160, 48)
	back_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back_btn.offset_left = 20
	back_btn.offset_bottom = -20
	back_btn.offset_top = -68
	back_btn.offset_right = 180
	root.add_child(back_btn)
	var err: int = back_btn.pressed.connect(func() -> void: return_to_lobby_requested.emit())
	assert(err == OK, "ShopScreen: failed to connect back button: %d" % err)

	_refresh_gold()


func _build_card_row(card: CardData) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 70)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = card.display_name
	name_label.add_theme_font_size_override("font_size", 18)
	info_vbox.add_child(name_label)

	var stats_label := Label.new()
	stats_label.text = _card_stats_text(card)
	stats_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info_vbox.add_child(stats_label)

	var cost_label := Label.new()
	cost_label.text = "%d G" % card.cost
	cost_label.custom_minimum_size = Vector2(80, 0)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(cost_label)

	var buy_btn := Button.new()
	buy_btn.custom_minimum_size = Vector2(80, 0)
	var card_id: String = card.id
	var err: int = buy_btn.pressed.connect(func() -> void: _on_buy_pressed(card_id))
	assert(err == OK, "ShopScreen: failed to connect buy button: %d" % err)
	hbox.add_child(buy_btn)
	_buy_buttons.append(buy_btn)

	_update_buy_button(buy_btn, card)
	return panel


func _on_buy_pressed(card_id: String) -> void:
	PlayerData.buy_card(card_id)
	_refresh_gold()
	_refresh_all_buy_buttons()


func _refresh_gold() -> void:
	_gold_label.text = "골드: %d" % PlayerData.gold


func _refresh_all_buy_buttons() -> void:
	var all_cards: Array[CardData] = CardDefinitions.get_all()
	for i: int in range(mini(_buy_buttons.size(), all_cards.size())):
		_update_buy_button(_buy_buttons[i], all_cards[i])


func _update_buy_button(btn: Button, card: CardData) -> void:
	var owned: bool = PlayerData.owned_card_ids.has(card.id)
	var can_afford: bool = PlayerData.gold >= card.cost
	btn.text = "보유중" if owned else "구매"
	btn.disabled = owned or not can_afford


func _card_stats_text(card: CardData) -> String:
	var parts: PackedStringArray = []
	if card.damage_mult != 1.0:
		parts.append("대미지 %+d%%" % roundi((card.damage_mult - 1.0) * 100))
	if card.cooldown_mult != 1.0:
		parts.append("쿨다운 %+d%%" % roundi((card.cooldown_mult - 1.0) * 100))
	if card.max_hp_bonus != 0:
		parts.append("체력 %+d" % card.max_hp_bonus)
	if card.damage_reduction != 0.0:
		parts.append("피해감소 %d%%" % roundi(card.damage_reduction * 100))
	if card.move_speed_mult != 1.0:
		parts.append("이동속도 %+d%%" % roundi((card.move_speed_mult - 1.0) * 100))
	if card.bp_regen_mult != 1.0:
		parts.append("BP회복 %+d%%" % roundi((card.bp_regen_mult - 1.0) * 100))
	if card.mp_cost_mult != 1.0:
		parts.append("MP소비 %+d%%" % roundi((card.mp_cost_mult - 1.0) * 100))
	return "  ".join(parts) if not parts.is_empty() else "-"
