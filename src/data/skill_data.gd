class_name SkillData

enum Type { MELEE, PROJECTILE, AOE }

var id: String
var display_name: String
var skill_type: SkillData.Type
var damage: int
var range: float
var cooldown: float
var mp_cost: int = 0
var projectile_speed: float = 0.0
