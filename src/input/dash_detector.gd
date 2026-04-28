class_name DashDetector

signal dash_requested

const DOUBLE_TAP_WINDOW_SEC: float = 0.3

var _last_active_time: float = -1.0
var _was_active: bool = false


func update(joystick_active: bool) -> void:
	if joystick_active and not _was_active:
		var now: float = Time.get_ticks_msec() / 1000.0
		if _last_active_time >= 0.0 and now - _last_active_time <= DOUBLE_TAP_WINDOW_SEC:
			dash_requested.emit()
			_last_active_time = -1.0
		else:
			_last_active_time = now
	_was_active = joystick_active
