class_name CharacterBase

extends CharacterBody2D

enum AnimState { IDLE, RUN, ATTACK }

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
var mp: float = 100.0
var bp: float = 100.0
var max_hp: int = 100
var max_mp: float = 100.0
var max_bp: float = 100.0
var bp_regen: float = 5.0
var mp_regen: float = 1.0
var is_dashing: bool = false
var facing_direction: Vector2 = Vector2.RIGHT
var team_id: int = 0

var _character_data: CharacterData = null
var _move_input: Vector2 = Vector2.ZERO
var _move_speed: float = 300.0
var _anim_state: AnimState = AnimState.IDLE
var _sprite: AnimatedSprite2D
var _hp_bar: ProgressBar
var _direction_line: Line2D


func _ready() -> void:
	_sprite = get_node("AnimatedSprite2D") as AnimatedSprite2D
	assert(_sprite != null, "CharacterBase: AnimatedSprite2D node missing")

	_hp_bar = get_node("HPBar") as ProgressBar
	assert(_hp_bar != null, "CharacterBase: HPBar node missing")
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(80, 8)
	_hp_bar.size = Vector2(80, 8)
	_hp_bar.position = Vector2(-40, -56)
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp

	var team_color: Color = _TEAM_COLORS[clampi(team_id, 0, _TEAM_COLORS.size() - 1)]
	_sprite.modulate = team_color

	var err := _sprite.animation_finished.connect(_on_animation_finished)
	assert(err == OK, "CharacterBase: failed to connect animation_finished: %d" % err)

	# assign_character_data may have been called before _ready — apply sprite now that _sprite is ready
	_apply_sprite_frames()

	if not _has_sprite_frames():
		var placeholder: Polygon2D = Polygon2D.new()
		placeholder.polygon = PackedVector2Array(
			[
				Vector2(-48, -48),
				Vector2(48, -48),
				Vector2(48, 48),
				Vector2(-48, 48),
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
	bp_regen = data.bp_regen
	mp_regen = data.mp_regen
	hp = max_hp
	mp = max_mp
	bp = max_bp
	# _sprite is null here when called before _ready; _ready will call _apply_sprite_frames again
	_apply_sprite_frames()


func _apply_sprite_frames() -> void:
	if _sprite == null or _character_data == null or _character_data.sprite_frames == null:
		return
	_sprite.sprite_frames = _character_data.sprite_frames
	var anim: String = _character_data.default_animation
	if _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)


func set_move_input(input_vector: Vector2) -> void:
	_move_input = input_vector.limit_length()
	if _move_input.length_squared() > 0.0:
		facing_direction = _move_input.normalized()
		if _direction_line != null:
			_direction_line.set_point_position(1, facing_direction * DIRECTION_LINE_LENGTH)
	_update_movement_animation()


func play_attack_animation(anim_prefix: String) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var anim_name := anim_prefix + "_" + _get_direction_suffix()
	if not _sprite.sprite_frames.has_animation(anim_name):
		return
	_anim_state = AnimState.ATTACK
	_sprite.play(anim_name)


func _update_movement_animation() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	if _anim_state == AnimState.ATTACK:
		return
	var prefix := "run" if _move_input.length_squared() > 0.0 else "idle"
	var anim_name := prefix + "_" + _get_direction_suffix()
	if _sprite.sprite_frames.has_animation(anim_name) and _sprite.animation != anim_name:
		_sprite.play(anim_name)


func _get_direction_suffix() -> String:
	if absf(facing_direction.x) >= absf(facing_direction.y):
		return "right" if facing_direction.x >= 0.0 else "left"
	return "down" if facing_direction.y >= 0.0 else "up"


func _on_animation_finished() -> void:
	if _anim_state == AnimState.ATTACK:
		_anim_state = AnimState.IDLE
		_update_movement_animation()


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

	var speed: float = _move_speed * 2.0 if is_dashing else _move_speed
	velocity = _move_input * speed
	move_and_slide()
