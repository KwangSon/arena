extends GutTest

const DOUBLE_TAP_WINDOW_SEC: float = 0.3


func test_first_tap_does_not_emit_signal() -> void:
	var detector: DashDetector = DashDetector.new()
	autofree(detector)
	watch_signals(detector)

	detector.update(true)

	assert_signal_not_emitted(detector, "dash_requested")


func test_double_tap_within_window_emits_signal() -> void:
	var detector: DashDetector = DashDetector.new()
	autofree(detector)
	watch_signals(detector)

	detector.update(true)
	detector.update(false)
	detector.set(
		"_last_active_time", detector.get("_last_active_time") - DOUBLE_TAP_WINDOW_SEC + 0.05
	)
	detector.update(true)

	assert_signal_emitted(detector, "dash_requested")


func test_double_tap_outside_window_does_not_emit_signal() -> void:
	var detector: DashDetector = DashDetector.new()
	autofree(detector)
	watch_signals(detector)

	detector.update(true)
	detector.update(false)
	detector.set(
		"_last_active_time", detector.get("_last_active_time") - DOUBLE_TAP_WINDOW_SEC - 0.1
	)
	detector.update(true)

	assert_signal_not_emitted(detector, "dash_requested")


func test_held_joystick_does_not_emit_signal() -> void:
	var detector: DashDetector = DashDetector.new()
	autofree(detector)
	watch_signals(detector)

	detector.update(true)
	detector.update(true)
	detector.update(true)

	assert_signal_not_emitted(detector, "dash_requested")


func test_double_tap_resets_timer_so_third_tap_does_not_emit() -> void:
	var detector: DashDetector = DashDetector.new()
	autofree(detector)
	watch_signals(detector)

	detector.update(true)
	detector.update(false)
	detector.set(
		"_last_active_time", detector.get("_last_active_time") - DOUBLE_TAP_WINDOW_SEC + 0.05
	)
	detector.update(true)
	detector.update(false)
	detector.update(true)

	assert_signal_emit_count(detector, "dash_requested", 1)
