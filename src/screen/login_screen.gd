class_name LoginScreen extends Node2D

signal login_completed

var _status_label: Label


func _ready() -> void:
	_setup_ui()
	_start_login()


func initialize(_data: Dictionary) -> void:
	pass


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	_status_label = Label.new()
	_status_label.text = "로그인 중..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_status_label)


func _start_login() -> void:
	var err: int = NakamaService.logged_in.connect(_on_logged_in)
	assert(err == OK, "LoginScreen: failed to connect logged_in: %d" % err)
	err = NakamaService.login_failed.connect(_on_login_failed)
	assert(err == OK, "LoginScreen: failed to connect login_failed: %d" % err)
	NakamaService.login_async()


func _on_logged_in(_user_id: String) -> void:
	_status_label.text = "데이터 불러오는 중..."
	await NakamaService.fetch_player_data_async()
	_status_label.text = "안녕하세요, %s!" % NakamaService.username
	login_completed.emit()


func _on_login_failed(error: String) -> void:
	_status_label.text = "로그인 실패: %s" % error
