class_name DeckScreen extends Node2D

signal return_to_lobby_requested

const _ALL_SLOTS: Array = [
	CardData.Slot.MAIN_WEAPON,
	CardData.Slot.SUB_WEAPON,
	CardData.Slot.ARMOR,
	CardData.Slot.SHOES,
	CardData.Slot.ULTIMATE,
]

const _SLOT_NAMES: Dictionary = {
	0: "주무기",
	1: "보조무기",
	2: "갑옷",
	3: "신발",
	4: "궁극기",
}

var _canvas: CanvasLayer
var _equipped_labels: Dictionary = {}
var _unequip_buttons: Dictionary = {}
var _selection_panel: PanelContainer
var _selection_title: Label
var _selection_vbox: VBoxContainer
var _active_slot: int = 0


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
	title.text = "덱 관리"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 20
	title.offset_bottom = 70
	root.add_child(title)

	var slots_container := VBoxContainer.new()
	slots_container.add_theme_constant_override("separation", 8)
	slots_container.set_anchors_preset(Control.PRESET_TOP_WIDE)
	slots_container.offset_top = 80
	slots_container.offset_bottom = 80 + _ALL_SLOTS.size() * 68
	slots_container.offset_left = 40
	slots_container.offset_right = -40
	root.add_child(slots_container)

	for slot: Variant in _ALL_SLOTS:
		slots_container.add_child(_build_slot_row(slot as CardData.Slot))

	_setup_selection_panel(root)

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
	assert(err == OK, "DeckScreen: failed to connect back button: %d" % err)


func _setup_selection_panel(root: Control) -> void:
	_selection_panel = PanelContainer.new()
	_selection_panel.anchor_left = 0.1
	_selection_panel.anchor_right = 0.9
	_selection_panel.anchor_top = 0.3
	_selection_panel.anchor_bottom = 0.85
	_selection_panel.visible = false
	root.add_child(_selection_panel)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.add_theme_constant_override("separation", 10)
	_selection_panel.add_child(panel_vbox)

	_selection_title = Label.new()
	_selection_title.add_theme_font_size_override("font_size", 20)
	panel_vbox.add_child(_selection_title)

	_selection_vbox = VBoxContainer.new()
	_selection_vbox.add_theme_constant_override("separation", 8)
	panel_vbox.add_child(_selection_vbox)

	var cancel_btn := Button.new()
	cancel_btn.text = "취소"
	panel_vbox.add_child(cancel_btn)
	var err: int = cancel_btn.pressed.connect(func() -> void: _selection_panel.visible = false)
	assert(err == OK, "DeckScreen: failed to connect cancel button: %d" % err)


func _build_slot_row(slot: CardData.Slot) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 60)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	var slot_label := Label.new()
	slot_label.text = _SLOT_NAMES.get(int(slot), "?")
	slot_label.custom_minimum_size = Vector2(90, 0)
	hbox.add_child(slot_label)

	var equipped_label := Label.new()
	equipped_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equipped_labels[int(slot)] = equipped_label
	hbox.add_child(equipped_label)

	var change_btn := Button.new()
	change_btn.text = "변경"
	change_btn.custom_minimum_size = Vector2(70, 0)
	var s: int = int(slot)
	var err: int = change_btn.pressed.connect(
		func() -> void: _on_change_pressed(s as CardData.Slot)
	)
	assert(err == OK, "DeckScreen: failed to connect change button: %d" % err)
	hbox.add_child(change_btn)

	var unequip_btn := Button.new()
	unequip_btn.text = "해제"
	unequip_btn.custom_minimum_size = Vector2(70, 0)
	_unequip_buttons[int(slot)] = unequip_btn
	err = unequip_btn.pressed.connect(func() -> void: _on_unequip_pressed(s as CardData.Slot))
	assert(err == OK, "DeckScreen: failed to connect unequip button: %d" % err)
	hbox.add_child(unequip_btn)

	_refresh_slot(slot)
	return panel


func _on_change_pressed(slot: CardData.Slot) -> void:
	_active_slot = int(slot)
	_selection_title.text = "%s 선택" % _SLOT_NAMES.get(int(slot), "?")

	for child: Node in _selection_vbox.get_children():
		child.queue_free()

	var owned: Array[CardData] = PlayerData.get_owned_cards_for_slot(slot)
	if owned.is_empty():
		var empty_label := Label.new()
		empty_label.text = "보유한 카드가 없습니다"
		_selection_vbox.add_child(empty_label)
	else:
		for card: CardData in owned:
			var btn := Button.new()
			btn.text = card.display_name
			var card_id: String = card.id
			var err: int = btn.pressed.connect(func() -> void: _on_card_selected(slot, card_id))
			assert(err == OK, "DeckScreen: failed to connect card select: %d" % err)
			_selection_vbox.add_child(btn)

	_selection_panel.visible = true


func _on_unequip_pressed(slot: CardData.Slot) -> void:
	PlayerData.unequip_slot(slot)
	_refresh_all_slots()


func _on_card_selected(slot: CardData.Slot, card_id: String) -> void:
	PlayerData.equip_card(slot, card_id)
	_selection_panel.visible = false
	_refresh_all_slots()


func _refresh_all_slots() -> void:
	for slot: Variant in _ALL_SLOTS:
		_refresh_slot(slot as CardData.Slot)


func _refresh_slot(slot: CardData.Slot) -> void:
	var label: Label = _equipped_labels.get(int(slot)) as Label
	var unequip_btn: Button = _unequip_buttons.get(int(slot)) as Button
	assert(label != null, "DeckScreen._refresh_slot: label missing for slot %d" % slot)
	assert(unequip_btn != null, "DeckScreen._refresh_slot: button missing for slot %d" % slot)

	var card_id: String = PlayerData.get_equipped_card_id(slot)
	if card_id.is_empty():
		label.text = "-"
		unequip_btn.disabled = true
	else:
		var card: CardData = _find_card(card_id)
		label.text = card.display_name if card != null else card_id
		unequip_btn.disabled = false


func _find_card(card_id: String) -> CardData:
	for card: CardData in CardDefinitions.get_all():
		if card.id == card_id:
			return card
	return null
