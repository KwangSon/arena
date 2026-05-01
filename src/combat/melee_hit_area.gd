class_name MeleeHitArea extends Area2D

signal overlap_done(bodies: Array)

const LIFETIME: float = 0.3
const FILL_ALPHA_START: float = 0.4
const RING_WIDTH: float = 3.0

var _radius: float = 80.0
var _base_color: Color = Color(1.0, 0.5, 0.0)
var _elapsed: float = 0.0


func setup(p_radius: float, p_color: Color, p_collision_mask: int) -> void:
	_radius = p_radius
	_base_color = Color(p_color.r, p_color.g, p_color.b)
	collision_layer = 0
	collision_mask = p_collision_mask
	monitorable = false

	var shape := CircleShape2D.new()
	shape.radius = _radius
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)


func _ready() -> void:
	monitoring = is_multiplayer_authority()
	queue_redraw()
	if is_multiplayer_authority():
		await get_tree().physics_frame
		overlap_done.emit(get_overlapping_bodies())


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= LIFETIME:
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
