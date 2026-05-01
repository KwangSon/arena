extends Node

signal logged_in(user_id: String)
signal login_failed(error: String)

var user_id: String = ""
var username: String = ""
var token: String = ""

var _client: NakamaClient = null
var _session: NakamaSession = null


func is_mock_mode() -> bool:
	return ProjectSettings.get_setting("network/nakama/ip", "") == ""


func get_device_id() -> String:
	return OS.get_unique_id()


func login_async() -> void:
	if is_mock_mode():
		user_id = "mock_%s" % get_device_id().left(8)
		username = "Player_%d" % randi_range(1000, 9999)
		token = "mock_token"
		logged_in.emit(user_id)
		return

	var ip: String = ProjectSettings.get_setting("network/nakama/ip", "")
	var port: int = int(ProjectSettings.get_setting("network/nakama/port", "7350"))
	_client = Nakama.create_client("defaultkey", ip, port, "http")

	var session: NakamaSession = await _client.authenticate_device_async(get_device_id())
	if session.is_exception():
		push_error("NakamaService: login failed: %s" % session)
		login_failed.emit(str(session.get_exception()))
		return
	_session = session
	user_id = session.user_id
	username = session.username
	token = session.token
	logged_in.emit(user_id)


func fetch_player_data_async() -> void:
	if is_mock_mode():
		return

	assert(_session != null, "NakamaService: fetch_player_data called before login")
	var ids: Array = [
		NakamaStorageObjectId.new("player", "profile"),
		NakamaStorageObjectId.new("player", "deck"),
	]
	var result: NakamaAPI.ApiStorageObjects = await _client.read_storage_objects_async(
		_session, ids
	)
	if result.is_exception():
		return

	var profile: Dictionary = {}
	var deck: Dictionary = {}
	for obj: NakamaAPI.ApiStorageObject in result.objects:
		var data: Variant = JSON.parse_string(obj.value)
		if not data is Dictionary:
			continue
		if obj.key == "profile":
			profile = data
		elif obj.key == "deck":
			deck = data

	PlayerData.load_from_nakama(profile, deck)
