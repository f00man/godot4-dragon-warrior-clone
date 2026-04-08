# ==============================================================================
# game_state.gd
# Part of: godot4-dragon-warrior-clone
# Description: Single source of truth for all mutable game data. Every piece
#              of data that needs to be saved or shared across systems lives
#              here. Other autoloads read and write their slice through the
#              accessor functions below — never by touching the vars directly.
# Attached to: Autoload (GameState)
# ==============================================================================

extends Node

# ------------------------------------------------------------------------------
# Signals — emitted whenever data changes so UI and other systems can react
# without polling. Declare all signals at the top per project convention.
# ------------------------------------------------------------------------------

# Fired when gold amount changes (e.g. buying an item, finding treasure)
signal gold_changed(new_amount)

# Fired when the party array is modified (member added, removed, or reordered)
signal party_changed()

# Fired when the inventory array changes (item added, removed, or quantity updated)
signal inventory_changed()

# Fired when any world flag is set or cleared
signal world_flag_changed(flag_key, new_value)

# Fired when a town's state dictionary is modified
signal town_data_changed(town_id)

# Fired when the current scene path changes so any system tracking location
# can update — e.g. a minimap that labels the region, or a HUD element that
# shows the current area name. SceneManager emits this via set_current_scene()
# after every successful transition.
signal scene_changed(path)

# Fired when a party member gains enough XP to advance a level.
# member_name is the display name (String) from PartyMemberData.
# new_level is the level they just reached (int).
# BattleManager connects to this to show a level-up message in the battle log.
signal level_up_occurred(member_name, new_level)

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------

# Maximum number of party members allowed at once
const MAX_PARTY_SIZE = 4

# Current save-file format version. Bump this when the save schema changes
# so _migrate_save() in SaveManager knows what transformations to apply.
const GAME_VERSION = "0.1.0"

# Cumulative XP required to reach each level. The array index equals the level.
# Index 0 is unused (there is no level 0). Index 1 = 0 XP because every new
# member starts at level 1 already. Index 10 = 900 XP to reach level 10.
# Any level beyond the last index in this table is uncapped — the member stays
# at the table's maximum level. Add more entries here as design requires.
const XP_TABLE = [0, 0, 10, 25, 50, 100, 175, 275, 400, 600, 900]

# ------------------------------------------------------------------------------
# Party Data
# ------------------------------------------------------------------------------

# Array of PartyMemberData resources representing the active party.
# Maximum MAX_PARTY_SIZE entries. Index 0 is the party leader.
var party = []

# The player's current gold. Valid range: 0 – 999999 (no negative gold).
var gold = 0

# Total seconds the player has spent in-game. Updated every frame in _process
# while not in battle. Displayed on the save screen as hours:minutes.
var playtime = 0.0

# ------------------------------------------------------------------------------
# Inventory Data
# ------------------------------------------------------------------------------

# Array of dictionaries, each shaped { "item_id": String, "quantity": int }.
# item_id maps to an ItemData resource in resources/items/.
# Example: [{ "item_id": "herb", "quantity": 3 }, { "item_id": "key", "quantity": 1 }]
var inventory = []

# ------------------------------------------------------------------------------
# World State
# ------------------------------------------------------------------------------

# Tracks boolean/int/String flags that record player choices and world events.
# Keys are descriptive snake_case strings. Values are bool, int, or String.
# Example: world_flags["rescued_village_of_kale"] = true
# Example: world_flags["times_rested_at_inn"] = 4
var world_flags = {}

# The player's current tile position on the active map. Stored as a Vector2
# so it can be restored when returning from battle or loading a save.
var player_position = Vector2.ZERO

# Resource path of the scene the player is currently in.
# Example: "res://scenes/world/overworld.tscn"
# Used by SaveManager so load_game() can restore the correct scene.
var current_scene = "res://scenes/world/overworld.tscn"

# True while a battle is in progress. SaveManager checks this before writing
# to disk — saving mid-battle would capture a transient state that can't be
# cleanly restored.
var in_battle = false

# Array of EnemyData resources queued for the next battle. Set by EncounterManager
# before transitioning to the battle scene; cleared by BattleManager on start.
# NOT saved to disk — this is transient battle setup state only. SaveManager
# intentionally omits this field from serialization.
var pending_battle_enemies = []

# When true, playtime accumulation is paused regardless of in_battle.
# Set via pause_playtime() / resume_playtime(). Use this for cutscenes,
# main menus, pause screens, or any moment where real wall-clock time
# should not count against the player's recorded play hours.
var is_playtime_paused = false

# ------------------------------------------------------------------------------
# Town Data
# ------------------------------------------------------------------------------

# Maps town_id (snake_case String) to a state dictionary.
# Each entry is shaped:
#   {
#     "owner":     String,   # "player", a faction name, or "neutral"
#     "loyalty":   int,      # 0–100; affects prices, quests, and events
#     "buildings": Array     # list of constructed building id strings
#   }
# Example: towns["riverkeep"] = { "owner": "player", "loyalty": 75, "buildings": ["inn"] }
var towns = {}

# ------------------------------------------------------------------------------
# Meta / Save Slot
# ------------------------------------------------------------------------------

# Which save slot (0, 1, or 2) this session was loaded from.
# Set by SaveManager.load_game() so the game knows where to quick-save.
var save_slot = 0

# The game version string at the time this state was last saved.
# Populated from GAME_VERSION on new games; read from disk on load.
var game_version = GAME_VERSION

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# GameState has no nodes to reference, so _ready just confirms boot.
	# Other autoloads that need to seed default data should call reset_to_defaults().
	pass

func _process(delta):
	# Accumulate playtime every frame, but only when the player is actually
	# in the world — not during battles, not while explicitly paused.
	# Battle scenes set in_battle = true/false. Menus and cutscenes should
	# call pause_playtime() / resume_playtime() rather than relying on in_battle.
	if not in_battle and not is_playtime_paused:
		playtime += delta

# ------------------------------------------------------------------------------
# Playtime Pause Helpers
# ------------------------------------------------------------------------------

# Stops playtime from accumulating until resume_playtime() is called.
# Call this when opening the pause menu, entering a cutscene, showing the
# title screen, or any other moment where the player is not actively playing
# and shouldn't be charged play-hours. Safe to call multiple times — redundant
# calls while already paused are silently ignored.
func pause_playtime():
	is_playtime_paused = true

# Allows playtime to resume accumulating after a pause_playtime() call.
# Call this when returning control to the player — e.g. closing the pause menu,
# ending a cutscene, or dismissing the title screen. Safe to call when not
# paused; has no effect in that case.
func resume_playtime():
	is_playtime_paused = false

# ------------------------------------------------------------------------------
# Reset / New Game
# ------------------------------------------------------------------------------

# Resets all game state to clean defaults for a new game.
# Call this before starting a fresh playthrough or after wiping a save slot.
func reset_to_defaults():
	# Seed the party with the hero resource so the party is never empty at the
	# start of a new game. An empty party breaks save/load (SaveManager would
	# serialize an empty array and restore it, leaving every downstream system —
	# battle, HUD, stat screens — with no party members to work with) and forces
	# every other system to defensively handle the empty-party edge case. Starting
	# with the hero here is the single authoritative place that guarantees a
	# non-empty party from the very first frame of a new playthrough.
	party = [load("res://resources/party_members/hero.tres")]
	gold = 0
	playtime = 0.0
	inventory = []
	world_flags = {}
	# Tile (16, 11) matches the Player node's starting position in overworld.tscn
	# (Vector2(512, 352) / 32 = tile col 16, row 11) — safely inside the grass,
	# clear of all perimeter walls. Vector2.ZERO would land on the top-left wall tile.
	player_position = Vector2(16, 11)
	current_scene = "res://scenes/world/overworld.tscn"
	in_battle = false
	is_playtime_paused = false
	towns = {}
	save_slot = 0
	game_version = GAME_VERSION

	# Notify all listeners so any open UI refreshes cleanly
	emit_signal("gold_changed", gold)
	emit_signal("party_changed")
	emit_signal("inventory_changed")

# ------------------------------------------------------------------------------
# Gold Accessors
# ------------------------------------------------------------------------------

# Returns the player's current gold amount.
func get_gold():
	return gold

# Adds `amount` gold. Pass a negative value to subtract.
# Clamps to 0 on the low end — the player can never go into debt.
# Emits gold_changed so the HUD updates immediately.
func modify_gold(amount):
	gold = max(0, gold + amount)
	emit_signal("gold_changed", gold)

# ------------------------------------------------------------------------------
# Party Accessors
# ------------------------------------------------------------------------------

# Returns the full party array (read-only by convention — use add/remove below).
func get_party():
	return party

# Adds a PartyMemberData resource to the party, up to MAX_PARTY_SIZE.
# Returns true if the member was added, false if the party is already full.
func add_party_member(member_data):
	if party.size() >= MAX_PARTY_SIZE:
		push_warning("GameState.add_party_member: party is full (%d members)" % MAX_PARTY_SIZE)
		return false
	party.append(member_data)
	emit_signal("party_changed")
	return true

# Removes a party member by their PartyMemberData reference.
# Does nothing if the member isn't in the party.
func remove_party_member(member_data):
	var index = party.find(member_data)
	if index == -1:
		push_warning("GameState.remove_party_member: member not found in party")
		return
	party.remove_at(index)
	emit_signal("party_changed")

# ------------------------------------------------------------------------------
# Inventory Accessors
# ------------------------------------------------------------------------------

# Returns the full inventory array.
func get_inventory():
	return inventory

# Adds `quantity` of `item_id` to the inventory.
# If the item is already present, increments the existing stack's quantity.
# Emits inventory_changed so the inventory UI can refresh.
func add_item(item_id, quantity):
	# Look for an existing stack of this item
	for entry in inventory:
		if entry["item_id"] == item_id:
			entry["quantity"] += quantity
			emit_signal("inventory_changed")
			return
	# No existing stack found — create a new entry
	inventory.append({ "item_id": item_id, "quantity": quantity })
	emit_signal("inventory_changed")

# Removes `quantity` of `item_id` from the inventory.
# If the resulting quantity would reach zero, removes the entry entirely.
# Returns true on success, false if the player doesn't have enough.
func remove_item(item_id, quantity):
	for i in range(inventory.size()):
		if inventory[i]["item_id"] == item_id:
			if inventory[i]["quantity"] < quantity:
				# Not enough of this item to fulfill the request
				return false
			inventory[i]["quantity"] -= quantity
			if inventory[i]["quantity"] <= 0:
				# Stack is empty — remove the entry so the inventory stays tidy
				inventory.remove_at(i)
			emit_signal("inventory_changed")
			return true
	# Item not found in inventory at all
	return false

# Returns the quantity of `item_id` in the inventory, or 0 if not present.
func get_item_quantity(item_id):
	for entry in inventory:
		if entry["item_id"] == item_id:
			return entry["quantity"]
	return 0

# ------------------------------------------------------------------------------
# World Flag Accessors
# ------------------------------------------------------------------------------

# Returns the value of a world flag, or `default_value` if the flag isn't set.
# Use this instead of direct dictionary access to avoid KeyError crashes.
func get_flag(flag_key, default_value = false):
	return world_flags.get(flag_key, default_value)

# Sets a world flag to `value` and emits world_flag_changed.
# value can be a bool, int, or String depending on what the event system needs.
func set_flag(flag_key, value):
	world_flags[flag_key] = value
	emit_signal("world_flag_changed", flag_key, value)

# Returns true if the flag exists AND its value is truthy (non-zero, non-false, non-empty).
# Convenient shorthand for the common boolean-flag pattern.
func has_flag(flag_key):
	if not world_flags.has(flag_key):
		return false
	return bool(world_flags[flag_key])

# ------------------------------------------------------------------------------
# Town Accessors
# ------------------------------------------------------------------------------

# Returns the state dictionary for `town_id`, or an empty dict if unknown.
# Callers should treat a missing town as "neutral with 50 loyalty" by default.
func get_town(town_id):
	return towns.get(town_id, {})

# Overwrites the state dictionary for `town_id` and emits town_data_changed.
# `town_data` should include at minimum: owner, loyalty, buildings.
func set_town(town_id, town_data):
	towns[town_id] = town_data
	emit_signal("town_data_changed", town_id)

# Adjusts a town's loyalty by `delta` (positive or negative).
# Clamps the result to the valid 0–100 range.
# Emits town_data_changed so the overworld can update visuals.
func modify_town_loyalty(town_id, delta):
	# Ensure the town entry exists before modifying it
	if not towns.has(town_id):
		towns[town_id] = { "owner": "neutral", "loyalty": 50, "buildings": [] }
	towns[town_id]["loyalty"] = clamp(towns[town_id]["loyalty"] + delta, 0, 100)
	emit_signal("town_data_changed", town_id)

# Sets the owner of a town (e.g. "player", "bandits", "neutral").
# Emits town_data_changed after updating.
func set_town_owner(town_id, owner):
	if not towns.has(town_id):
		towns[town_id] = { "owner": "neutral", "loyalty": 50, "buildings": [] }
	towns[town_id]["owner"] = owner
	emit_signal("town_data_changed", town_id)

# Adds a building id to a town's buildings list if not already present.
# Emits town_data_changed after updating.
func add_town_building(town_id, building_id):
	if not towns.has(town_id):
		towns[town_id] = { "owner": "neutral", "loyalty": 50, "buildings": [] }
	if building_id not in towns[town_id]["buildings"]:
		towns[town_id]["buildings"].append(building_id)
		emit_signal("town_data_changed", town_id)

# ------------------------------------------------------------------------------
# Position / Scene Helpers
# ------------------------------------------------------------------------------

# Updates both the player's tile position and the current scene path together.
# Call this whenever the player transitions to a new map or scene.
func set_location(scene_path, tile_position):
	current_scene = scene_path
	player_position = tile_position

# Returns the player's last known tile position as a Vector2.
func get_player_position():
	return player_position

# Returns the resource path of the scene the player is currently in.
func get_current_scene():
	return current_scene

# Sets the current scene path and emits scene_changed. Call this instead of
# writing current_scene directly so all listeners (HUD, minimap, etc.) are
# notified. SceneManager calls this after every transition so the rest of the
# game always has an up-to-date location without polling.
func set_current_scene(path):
	current_scene = path
	emit_signal("scene_changed", path)

# ------------------------------------------------------------------------------
# Experience and Level-Up
# ------------------------------------------------------------------------------

# Awards `amount` experience points to `member` (a PartyMemberData resource).
# Checks whether the new total crosses the threshold for the next level and
# calls _apply_level_up() for each level gained — this handles the edge case
# where a single battle award vaults a member past multiple level thresholds
# at once (e.g. a fresh level-1 character earning 200 XP would reach level 7).
# Emits party_changed once after all level-ups are processed so the UI refreshes
# a single time rather than once per level gained.
func award_experience(member, amount):
	# Add the raw XP. experience should never decrease, so no clamping needed here.
	member.experience += amount

	# Level-up loop: keep promoting the member for as long as they have enough
	# cumulative XP to reach the next level AND the next level exists in the table.
	# We stop at XP_TABLE.size() - 1 because that is the highest defined level.
	while member.level < XP_TABLE.size() - 1:
		var xp_needed_for_next = XP_TABLE[member.level + 1]
		if member.experience >= xp_needed_for_next:
			# Member has crossed the threshold — promote them.
			_apply_level_up(member)
		else:
			# Not enough XP for the next level yet — stop checking.
			break

	# Notify all listeners (party screen, HUD) that party data changed.
	emit_signal("party_changed")


# Applies one level of stat growth to `member` and announces it via signal.
# Called once per level gained inside the award_experience loop.
# Stat increases are fixed values intentionally kept conservative at this stage
# of development; they can be made data-driven later if a designer wants per-
# class growth rates. HP and MP are fully restored so a level-up mid-battle feels
# rewarding (mirrors classic Dragon Warrior / Dragon Quest behaviour).
func _apply_level_up(member):
	# Advance the level counter first so the signal carries the new level number.
	member.level += 1

	# Apply fixed stat growth per level. These constants are the current design
	# defaults — adjust here (or make data-driven via PartyMemberData exports)
	# once the balance pass begins.
	member.max_hp    += 10   # Primary survivability stat; meaningful per level
	member.max_mp    += 5    # Smaller gain; MP is a scarce resource by design
	member.attack    += 3    # Offensive growth; keeps damage scaling with level
	member.defense   += 2    # Defensive growth; slightly slower than offense
	member.speed     += 1    # Turn-order stat; slow drift so it stays meaningful

	# Restore HP and MP to the new maximums. This is the classic JRPG level-up
	# feel — gaining a level heals you. It also prevents the awkward state of
	# max_hp increasing while current_hp stays at the old (now lower) cap.
	member.current_hp = member.max_hp
	member.current_mp = member.max_mp

	# Broadcast the level-up event. BattleManager connects to this to show a
	# message in the battle log. The UI party screen will rebuild from party_changed
	# (emitted by the caller, award_experience) — we do NOT emit party_changed here
	# to avoid multiple redundant refreshes when multi-levelling occurs.
	emit_signal("level_up_occurred", member.member_name, member.level)
