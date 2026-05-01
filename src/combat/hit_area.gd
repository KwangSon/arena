class_name HitArea extends Area2D

signal body_hit(hit_area: HitArea, body: Node2D)

const LIFETIME: float = 0.3
const FILL_ALPHA_START: float = 0.4
const RING_WIDTH: float = 3.0

var attacker_id: int = 0
var damage: int = 0
var skill_id: String = ""

var _radius: float = 80.0
var _base_color: Color = Color(1.0, 0.5, 0.0)
var _elapsed: float = 0.0


func setup(p_radius: float, p_color: Color, p_collision_mask: int) -> void:
	_radius = p_radius
	_base_color = Color(p_color.r, p_color.g, p_color.b)
	collision_mask = p_collision_mask
	collision_layer = 0


func _ready() -> void:
	monitoring = false
	var col := get_node("CollisionShape2D") as CollisionShape2D
	assert(col != null, "HitArea: CollisionShape2D missing")
	var shape := col.shape as CircleShape2D
	assert(shape != null, "HitArea: shape is not CircleShape2D")
	shape.radius = _radius
	var err := body_entered.connect(_on_body_entered)
	assert(err == OK, "HitArea: failed to connect body_entered: %d" % err)
	await get_tree().physics_frame
	monitoring = true
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= LIFETIME:
		monitoring = false
		if is_multiplayer_authority():
			queue_free()
		else:
			set_process(false)
			hide()


func _draw() -> void:
	var t: float = clampf(_elapsed / LIFETIME, 0.0, 1.0)

	var fill_alpha: float = FILL_ALPHA_START * (1.0 - t)
	draw_circle(
		Vector2.ZERO, _radius, Color(_base_color.r, _base_color.g, _base_color.b, fill_alpha)
	)

	var ring_alpha: float = 1.0 - t * 0.7
	var ring_color := Color(_base_color.r, _base_color.g, _base_color.b, ring_alpha).lightened(0.3)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 64, ring_color, RING_WIDTH)

	var pulse_r: float = _radius * (1.0 + t * 0.15)
	var pulse_alpha: float = (1.0 - t) * 0.5
	draw_arc(
		Vector2.ZERO,
		pulse_r,
		0.0,
		TAU,
		64,
		Color(_base_color.r, _base_color.g, _base_color.b, pulse_alpha),
		1.5
	)


func _on_body_entered(body: Node2D) -> void:
	if not is_multiplayer_authority():
		return
	body_hit.emit(self, body)
