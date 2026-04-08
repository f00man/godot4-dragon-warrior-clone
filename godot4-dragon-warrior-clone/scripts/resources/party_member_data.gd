# ==============================================================================
# party_member_data.gd
# Part of: godot4-dragon-warrior-clone
# Description: Resource class for a single party member. Holds both base stats
#              and current battle state. One instance per party member — HP and
#              MP are modified in-place during battle and persist afterward.
# Attached to: Resource (no node)
# ==============================================================================

class_name PartyMemberData extends Resource

# Display name shown in battle UI and menus (e.g. "Hero", "Aria")
@export var member_name = "Hero"

# Maximum hit points. Valid range: 1–999.
# Must be > 0. Game will break if this is 0 or negative.
@export var max_hp = 50

# Current HP. Reduced by taking damage, restored by heals and rest.
# 0 = knocked out. Should never exceed max_hp.
# BattleManager is responsible for clamping this after every change.
@export var current_hp = 50

# Maximum magic points. Valid range: 0–999.
# 0 is valid for classes that cannot cast spells.
@export var max_mp = 20

# Current MP. Reduced when spells are cast, restored by items and rest.
# Should never exceed max_mp.
# BattleManager is responsible for clamping this after every change.
@export var current_mp = 20

# Base physical attack power. Compared against enemy defense to calculate damage.
# Valid range: 1–999. Must be > 0.
@export var attack = 10

# Base physical defense. Subtracted from incoming damage before it is applied.
# Valid range: 0–999. 0 means no damage reduction.
@export var defense = 5

# Determines turn order in battle. Higher value acts before lower value.
# Valid range: 1–999. Must be > 0.
@export var speed = 5

# Current level. Increases when enough experience is accumulated.
# Valid range: 1–99.
@export var level = 1

# Total accumulated experience points. Used to determine when the next level-up occurs.
# Valid range: 0 and up. Never decreases.
@export var experience = 0


# Returns true if this party member is still standing (has HP remaining).
# Returns false if the member has been knocked out (HP is 0).
# BattleManager uses this to skip knocked-out members during turn resolution.
func is_alive():
	return current_hp > 0
