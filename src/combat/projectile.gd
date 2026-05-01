class_name Projectile

extends Area2D

signal body_hit(projectile: Projectile, body: Node2D)

var attacker_id: int = 0
var damage: int = 0
var knockback_power: float = 0.0
var skill_id: String = ""

var _direction: Vector2 = Vector2.RIGHT
var _speed: float = 400.0
var _range: float = 400.0
var _distance_traveled: float = 0.0


func setup(direction: Vector2, speed: float, p_range: float) -> void:
	_direction = direction.normalized()
	_speed = speed
	_range = p_range


func _ready() -> void:
	monitoring = false
	var err: int = body_entered.connect(_on_body_entered)
	assert(err == OK, "Projectile: failed to connect body_entered: %d" % err)
	await get_tree().physics_frame
	monitoring = true


func _draw() -> void:
	draw_circle(Vector2.ZERO, 8.0, Color.CYAN)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var move: Vector2 = _direction * _speed * delta
	position += move
	_distance_traveled += move.length()

	if _distance_traveled >= _range:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if not is_multiplayer_authority():
		return
	body_hit.emit(self, body)
	queue_free()
