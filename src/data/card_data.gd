class_name CardData extends Resource

enum Slot { MAIN_WEAPON, SUB_WEAPON, ARMOR, SHOES, ULTIMATE }

var id: String
var display_name: String
var slot: Slot

var damage_mult: float = 1.0
var cooldown_mult: float = 1.0
var max_hp_bonus: int = 0
var damage_reduction: float = 0.0
var move_speed_mult: float = 1.0
var bp_regen_mult: float = 1.0
var mp_cost_mult: float = 1.0
