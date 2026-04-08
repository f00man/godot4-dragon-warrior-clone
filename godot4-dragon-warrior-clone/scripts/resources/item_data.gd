# ==============================================================================
# item_data.gd
# Part of: godot4-dragon-warrior-clone
# Description: Resource template for an inventory item. Defines the item's
#              effect type and magnitude. BattleManager and inventory systems
#              read these fields to apply effects.
# Attached to: Resource (no node)
# ==============================================================================

class_name ItemData extends Resource

# Display name shown in inventory and shop menus (e.g. "Herb", "Antidote")
@export var item_name = "Item"

# One-line description shown in the item detail view.
# Keep this short enough to fit on a single line in the UI.
@export var description = ""

# Defines what this item does when used. BattleManager and the inventory system
# branch on this string to determine which effect handler to call.
#
# Valid values:
#   "heal_hp"  — restore effect_value HP to the target party member
#   "heal_mp"  — restore effect_value MP to the target party member
#   "revive"   — revive a knocked-out party member with effect_value HP restored
#
# Any value outside this list will be ignored by the effect handlers.
# Must not be empty string if the item is intended to do anything.
@export var effect_type = "heal_hp"

# Magnitude of the effect. Interpretation depends on effect_type.
# Examples: 30 restores 30 HP for "heal_hp", 15 restores 15 MP for "heal_mp".
# Valid range: 0 and up. 0 is valid for key items that have no combat effect.
@export var effect_value = 0

# Texture2D for the item icon shown in menus and the shop UI.
# Null until art assets exist — UI must handle a null icon gracefully
# by showing a generic placeholder sprite.
@export var icon = null
