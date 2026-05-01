class_name CharacterSelectScreen extends Node2D

signal character_chosen(character_id: String)

const _CHARACTERS: Array[Dictionary] = [
	{"id": "warrior", "name": "검사", "hp": 150, "mp": 80, "speed": 280},
	{"id": "knight", "name": "기사", "hp": 130, "mp": 80, "speed": 290},
	{"id": "mage", "name": "마법사", "hp": 80, "mp": 120, "speed": 260},
	{"id": "prince", "name": "왕자", "hp": 110, "mp": 150, "speed": 280},
]

var _canvas: CanvasLayer


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
	title.text = "캐릭터 선택"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 60
	title.offset_bottom = 110
	root.add_child(title)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
	hbox.set_anchors_preset(Control.PRESET_CENTER)
	hbox.offset_left = -360
	hbox.offset_right = 360
	hbox.offset_top = -120
	hbox.offset_bottom = 120
	root.add_child(hbox)

	for char_info in _CHARACTERS:
		hbox.add_child(_build_card(char_info))


func _build_card(info: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 240)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var name_label := Label.new()
	name_label.text = info["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(name_label)

	var stats_label := Label.new()
	stats_label.text = "HP %d  MP %d\n이동속도 %d" % [info["hp"], info["mp"], info["speed"]]
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats_label)

	var btn := Button.new()
	btn.text = "선택"
	btn.custom_minimum_size = Vector2(120, 40)
	var character_id: String = info["id"]
	var err: int = btn.pressed.connect(func() -> void: character_chosen.emit(character_id))
	assert(err == OK, "CharacterSelectScreen: failed to connect button: %d" % err)
	vbox.add_child(btn)

	return panel
