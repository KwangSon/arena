extends GutTest

var _service: Node


func before_each() -> void:
	_service = add_child_autofree(NakamaService.new())


# ============================================================
# Mock mode (항상 실행)
# ============================================================


func test_mock_mode_when_ip_empty() -> void:
	assert_true(_service.is_mock_mode(), "ip가 비어있으면 mock mode여야 함")


func test_device_id_is_non_empty() -> void:
	assert_ne(_service.get_device_id(), "", "device_id는 비어있으면 안 됨")


func test_mock_login_sets_user_id() -> void:
	await _service.login_async()
	assert_ne(_service.user_id, "", "mock login 후 user_id가 설정돼야 함")


func test_mock_login_sets_token() -> void:
	await _service.login_async()
	assert_ne(_service.token, "", "mock login 후 token이 설정돼야 함")


func test_mock_login_emits_logged_in_signal() -> void:
	watch_signals(_service)
	await _service.login_async()
	assert_signal_emitted(_service, "logged_in")


# ============================================================
# Real mode (nakama/ip 설정 시에만 실행)
# ============================================================


func test_real_login_sets_user_id() -> void:
	if _service.is_mock_mode():
		pending("nakama/ip not set — skipping real login test")
		return
	await _service.login_async()
	assert_ne(_service.user_id, "", "real login 후 user_id가 설정돼야 함")


func test_real_login_sets_token() -> void:
	if _service.is_mock_mode():
		pending("nakama/ip not set — skipping real token test")
		return
	await _service.login_async()
	assert_ne(_service.token, "", "real login 후 token이 설정돼야 함")
