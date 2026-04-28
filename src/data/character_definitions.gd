class_name CharacterDefinitions


static func warrior() -> CharacterData:
	var data := CharacterData.new()
	data.id = "warrior"
	data.display_name = "검사"
	data.max_hp = 150
	data.max_mp = 80
	data.max_bp = 100
	data.move_speed = 280.0

	var slash := SkillData.new()
	slash.id = "slash"
	slash.display_name = "베기"
	slash.skill_type = SkillData.Type.MELEE
	slash.damage = 30
	slash.range = 80.0
	slash.cooldown = 1.0

	var charge := SkillData.new()
	charge.id = "charge"
	charge.display_name = "돌진"
	charge.skill_type = SkillData.Type.MELEE
	charge.damage = 20
	charge.range = 200.0
	charge.cooldown = 5.0

	var whirlwind := SkillData.new()
	whirlwind.id = "whirlwind"
	whirlwind.display_name = "회전베기"
	whirlwind.skill_type = SkillData.Type.AOE
	whirlwind.damage = 60
	whirlwind.range = 120.0
	whirlwind.cooldown = 12.0
	whirlwind.mp_cost = 50

	data.skill_1 = slash
	data.skill_2 = charge
	data.ultimate = whirlwind
	return data


static func mage() -> CharacterData:
	var data := CharacterData.new()
	data.id = "mage"
	data.display_name = "마법사"
	data.max_hp = 80
	data.max_mp = 120
	data.max_bp = 100
	data.move_speed = 260.0

	var fireball := SkillData.new()
	fireball.id = "fireball"
	fireball.display_name = "파이어볼"
	fireball.skill_type = SkillData.Type.PROJECTILE
	fireball.damage = 35
	fireball.range = 400.0
	fireball.cooldown = 1.5
	fireball.projectile_speed = 400.0

	var frost := SkillData.new()
	frost.id = "frost_nova"
	frost.display_name = "프로스트 노바"
	frost.skill_type = SkillData.Type.AOE
	frost.damage = 20
	frost.range = 150.0
	frost.cooldown = 6.0

	var meteor := SkillData.new()
	meteor.id = "meteor"
	meteor.display_name = "메테오"
	meteor.skill_type = SkillData.Type.AOE
	meteor.damage = 100
	meteor.range = 200.0
	meteor.cooldown = 15.0
	meteor.mp_cost = 80

	data.skill_1 = fireball
	data.skill_2 = frost
	data.ultimate = meteor
	return data
