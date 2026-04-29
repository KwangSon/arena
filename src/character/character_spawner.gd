class_name CharacterSpawner

const CHARACTER_SCENE: PackedScene = preload("res://src/character/character_base.tscn")

const SYNCED_PROPS: Array[NodePath] = [
	NodePath(".:position"),
	NodePath(".:hp"),
	NodePath(".:mp"),
	NodePath(".:bp"),
	NodePath(".:is_dashing"),
]


static func create_node(data: Dictionary, referee_peer_id: int) -> CharacterBase:
	assert(data.has("peer_id"), "CharacterSpawner: spawn data missing peer_id")
	assert(data.has("position"), "CharacterSpawner: spawn data missing position")

	var character: CharacterBody2D = CHARACTER_SCENE.instantiate() as CharacterBody2D
	assert(character != null, "CharacterSpawner: failed to instantiate CharacterBase scene")
	assert(
		character.has_method("set_move_input"),
		"CharacterSpawner: CharacterBase scene is missing character_base.gd script"
	)

	var character_base: CharacterBase = character as CharacterBase
	assert(character_base != null, "CharacterSpawner: CharacterBody2D is not a CharacterBase")

	var character_id: String = data.get("character_id", "warrior")
	var char_data: CharacterData = CharacterDefinitions.create(character_id)
	character_base.assign_character_data(char_data)
	character_base.team_id = data.get("team_id", 1)
	character_base.collision_layer = character_base.team_id
	character_base.collision_mask = 1 | 2

	character.set_multiplayer_authority(referee_peer_id)
	character.name = str(data["peer_id"])
	character.position = data["position"]

	_setup_synchronizer(character, referee_peer_id)

	return character_base


static func _setup_synchronizer(character: CharacterBody2D, referee_peer_id: int) -> void:
	var synchronizer: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = "StateSynchronizer"
	synchronizer.root_path = NodePath("..")
	synchronizer.replication_interval = 0.0
	synchronizer.delta_interval = 0.0
	synchronizer.set_multiplayer_authority(referee_peer_id)

	var replication_config: SceneReplicationConfig = SceneReplicationConfig.new()

	for prop in SYNCED_PROPS:
		replication_config.add_property(prop)
		replication_config.property_set_spawn(prop, true)
		replication_config.property_set_replication_mode(
			prop, SceneReplicationConfig.REPLICATION_MODE_ALWAYS
		)

	synchronizer.replication_config = replication_config
	character.add_child(synchronizer, true)
