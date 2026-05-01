extends Node

signal logged_in(user_id: String)

var user_id: String = ""
var token: String = ""

var _client: NakamaClient = null


func is_mock_mode() -> bool:
	return ProjectSettings.get_setting("network/nakama/ip", "") == ""


func get_device_id() -> String:
	return OS.get_unique_id()


func login_async() -> void:
	if is_mock_mode():
		user_id = "mock_%s" % get_device_id().left(8)
		token = "mock_token"
		logged_in.emit(user_id)
		return

	var ip: String = ProjectSettings.get_setting("network/nakama/ip", "")
	var port: int = int(ProjectSettings.get_setting("network/nakama/port", "7350"))
	_client = Nakama.create_client("defaultkey", ip, port, "http")

	var session: NakamaSession = await _client.authenticate_device_async(get_device_id())
	assert(not session.is_exception(), "NakamaService: login failed: %s" % session)
	user_id = session.user_id
	token = session.token
	logged_in.emit(user_id)
