class_name CharacterBase

extends CharacterBody2D

var hp: int = 100
var mp: int = 100
var bp: int = 100
var max_hp: int = 100
var max_mp: int = 100
var max_bp: int = 100

var _character_data: CharacterData = null
var _move_input: Vector2 = Vector2.ZERO
var _move_speed: float = 300.0


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


func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not is_multiplayer_authority():
		return

	velocity = _move_input * _move_speed
	move_and_slide()
