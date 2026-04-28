class_name CharacterBase

extends CharacterBody2D

const DIRECTION_LINE_LENGTH: float = 50.0
const _TEAM_COLORS: Array[Color] = [
	Color(0.5, 0.5, 0.5),  # team 0 (unassigned)
	Color(0.3, 0.5, 1.0),  # team 1 — blue
	Color(1.0, 0.3, 0.3),  # team 2 — red
]

var hp: int = 100:
	set(value):
		hp = value
		if _hp_bar != null:
			_hp_bar.value = hp
var mp: int = 100
var bp: int = 100
var max_hp: int = 100
var max_mp: int = 100
var max_bp: int = 100
var facing_direction: Vector2 = Vector2.RIGHT
var team_id: int = 0

var _character_data: CharacterData = null
var _move_input: Vector2 = Vector2.ZERO
var _move_speed: float = 300.0
var _sprite: AnimatedSprite2D
var _hp_bar: ProgressBar
var _direction_line: Line2D


func _ready() -> void:
	_sprite = get_node("AnimatedSprite2D") as AnimatedSprite2D
	assert(_sprite != null, "CharacterBase: AnimatedSprite2D node missing")

	_hp_bar = get_node("HPBar") as ProgressBar
	assert(_hp_bar != null, "CharacterBase: HPBar node missing")
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(40, 6)
	_hp_bar.size = Vector2(40, 6)
	_hp_bar.position = Vector2(-20, -32)
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp

	var team_color: Color = _TEAM_COLORS[clampi(team_id, 0, _TEAM_COLORS.size() - 1)]
	_sprite.modulate = team_color

	# Placeholder visual until sprite frames are added
	if not _has_sprite_frames():
		var placeholder: Polygon2D = Polygon2D.new()
		placeholder.polygon = PackedVector2Array(
			[
				Vector2(-15, -20),
				Vector2(15, -20),
				Vector2(15, 20),
				Vector2(-15, 20),
			]
		)
		placeholder.color = team_color
		add_child(placeholder)

	_direction_line = Line2D.new()
	_direction_line.width = 3.0
	_direction_line.default_color = Color.YELLOW
	_direction_line.add_point(Vector2.ZERO)
	_direction_line.add_point(facing_direction * DIRECTION_LINE_LENGTH)
	_direction_line.visible = false
	add_child(_direction_line)


func show_facing_indicator() -> void:
	_direction_line.visible = true


func assign_character_data(data: CharacterData) -> void:
	assert(data != null, "CharacterBase.assign_character_data: data is null")
	_character_data = data
	_move_speed = data.move_speed
	max_hp = data.max_hp
	max_mp = data.max_mp
	max_bp = data.max_bp
	hp = max_hp
	mp = max_mp
	bp = max_bp


func set_move_input(input_vector: Vector2) -> void:
	_move_input = input_vector.limit_length()
	if _move_input.length_squared() > 0.0:
		facing_direction = _move_input.normalized()
		if _direction_line != null:
			_direction_line.set_point_position(1, facing_direction * DIRECTION_LINE_LENGTH)


func _has_sprite_frames() -> bool:
	if _sprite.sprite_frames == null:
		return false
	for anim_name in _sprite.sprite_frames.get_animation_names():
		if _sprite.sprite_frames.get_frame_count(anim_name) > 0:
			return true
	return false


func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not is_multiplayer_authority():
		return

	velocity = _move_input * _move_speed
	move_and_slide()
