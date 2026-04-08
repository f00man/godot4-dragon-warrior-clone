# ==============================================================================
# enemy_data.gd
# Part of: godot4-dragon-warrior-clone
# Description: Resource template for an enemy type. NOT mutated during battle —
#              BattleManager tracks runtime HP separately so the same resource
#              can be reused across multiple encounters.
# Attached to: Resource (no node)
# ==============================================================================

class_name EnemyData extends Resource

# Display name shown in battle UI (e.g. "Slime", "Dragon Knight")
@export var enemy_name = "Enemy"

# Maximum (and starting) HP for this enemy type.
# BattleManager copies this into a runtime variable at encounter start —
# this field itself is never decremented during battle.
# Must be > 0. Game will break if this is 0 or negative.
@export var max_hp = 10

# Base physical attack. Compared against a party member's defense to calculate damage.
# Valid range: 1–999. Must be > 0.
@export var attack = 5

# Base physical defense. Subtracted from incoming party damage before it is applied.
# Valid range: 0–999. 0 means no damage reduction.
@export var defense = 2

# Determines turn order in battle. Higher value acts before lower value.
# Compared against party member speed values during turn queue construction.
# Valid range: 1–999. Must be > 0.
@export var speed = 3

# XP awarded to each surviving party member when this enemy is defeated.
# Valid range: 0 and up. 0 is valid for non-combat or scripted encounters.
@export var experience_reward = 3

# Gold added to GameState.gold when this enemy (or its group) is defeated.
# Valid range: 0 and up.
@export var gold_reward = 2

# Texture2D for the battle sprite displayed facing the player (Dragon Warrior style).
# Null until art assets exist — BattleManager must handle a null sprite gracefully
# by showing a placeholder or hiding the sprite node entirely.
@export var sprite = null
