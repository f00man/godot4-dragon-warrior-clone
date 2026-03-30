# ==============================================================================
# town_manager.gd
# Part of: godot4-dragon-warrior-clone
# Description: Manages town ownership, loyalty, and building construction.
#              Reads and writes town state through GameState.towns. Emits
#              signals when town state changes so the overworld can update
#              visuals (flags, building sprites, etc.)
# Attached to: Autoload (TownManager)
# ==============================================================================

extends Node


# ------------------------------------------------------------------------------
# Signals
# Declare all signals at the top before any variables, per CLAUDE.md convention.
# Consumers connect to these in their own _ready() — TownManager never polls.
# ------------------------------------------------------------------------------

# Emitted when a town changes hands. Overworld listens to update flag sprites.
signal town_ownership_changed(town_id, new_owner)

# Emitted when loyalty changes. UI listens to update loyalty bars.
signal town_loyalty_changed(town_id, new_loyalty)

# Emitted when a new building finishes construction. Used to update overworld visuals.
signal building_constructed(town_id, building_id)


# ------------------------------------------------------------------------------
# Private State
# ------------------------------------------------------------------------------

# Local cache of town state. Mirrors GameState.towns.
# Always write changes back to GameState via GameState.set_town() to keep saves
# consistent. This cache exists so callers don't need to reach into GameState
# directly — all reads go through get_town() and all writes through the public
# mutation functions below.
var _towns = {}


# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Seed local cache from GameState on startup. If GameState.towns is empty
	# (new game), _towns starts empty and towns are populated as the player
	# discovers them.
	_towns = GameState.towns

	# Stay in sync with any external writes to GameState.towns (e.g. EventManager
	# applying event outcomes that modify a town directly). When that signal fires
	# we refresh the affected cache entry so TownManager never serves stale data.
	GameState.town_data_changed.connect(_on_town_data_changed)


# ------------------------------------------------------------------------------
# Public API — Read
# ------------------------------------------------------------------------------

# Returns the full state dict for town_id from the local cache.
# If the town isn't in the cache yet (player hasn't visited), returns a default
# neutral town dict: { owner: "neutral", loyalty: 50, buildings: [] }.
# Callers should treat the returned dict as read-only; use the mutation functions
# below (set_owner, adjust_loyalty, construct_building) to make changes.
func get_town(town_id):
	# TODO: Once TownData resources exist, populate the default dict from the
	# resource so town_name, population, etc. are correct for unseen towns.
	if _towns.has(town_id):
		return _towns[town_id]

	# Return a safe default so callers never receive null.
	# loyalty 50 = Neutral tier (41-60): normal prices, basic quests available.
	return {
		"owner": "neutral",
		"loyalty": 50,
		"constructed_buildings": []
	}


# Convenience check — returns true if the town's current owner is "player".
# Used by UI to show/hide management options and by SaveManager indirectly
# via GameState.
func is_player_owned(town_id):
	# TODO: Consider caching ownership separately for fast batch queries
	# (e.g. "how many towns does the player own?").
	var town = get_town(town_id)
	return town.get("owner", "neutral") == "player"


# Returns a lightweight summary dict for display in the town info panel or
# overworld tooltip. Shape: { "name": String, "owner": String,
# "loyalty": int, "building_count": int }.
# TODO: "name" should come from a TownData resource (not yet created); for now
# use town_id.capitalize() as a display label.
func get_town_summary(_town_id):
	# TODO: Populate from TownData resource once that system exists.
	return {}


# Returns a list of building_id strings that can be constructed in town_id
# right now. Intended to drive the building selection UI so it only shows
# options the player can actually choose.
# TODO: Filter against a BuildingData resource catalogue (not yet created)
# checking: not already built, prerequisites met, player owns town.
# The loyalty thresholds that gate buildings are:
#   inn / blacksmith — loyalty >= 41 (Neutral tier)
#   market / guard_tower — loyalty >= 61 (Friendly tier)
#   temple — loyalty >= 71 (high end of Friendly tier)
#   castle_gate — loyalty >= 81 (Devoted tier)
# For now returns empty array until the BuildingData catalogue is created.
func get_available_buildings(_town_id):
	# TODO: Replace stub with catalogue lookup once building_data.gd exists.
	return []


# ------------------------------------------------------------------------------
# Public API — Mutation
# ------------------------------------------------------------------------------

# Sets the owner of a town and writes the change back to GameState.
# new_owner should be "player", a faction id string ("merchant_guild",
# "bandit_clan", "royal_crown"), or "neutral".
# After updating, emits town_ownership_changed so the overworld can swap flag
# sprites without polling.
# TODO: Add faction relationship consequences — e.g. when the player takes a
# town from "royal_crown", that faction's other towns should lose loyalty toward
# the player, and rival factions may gain loyalty. That logic belongs here, not
# in the UI or in individual event scripts.
func set_town_owner(_town_id, _new_owner):
	# TODO: Implement full ownership transfer logic.
	pass


# Adds delta to the town's loyalty (positive or negative). Clamps result to
# 0–100. Writes back to GameState and emits town_loyalty_changed.
#
# Loyalty thresholds and their gameplay effects (document here so every caller
# knows what they are changing):
#   0–20   Hostile     — Shops closed, enemies may appear inside town
#   21–40  Unfriendly  — Shops open but prices +50%, no quests offered
#   41–60  Neutral     — Normal prices, basic quests available
#   61–80  Friendly    — Prices -10%, more quests, inn discount
#   81–100 Devoted     — Prices -20%, unique quests, special buildings unlocked
#
# TODO: Check for loyalty thresholds that should trigger events when crossed.
# For example: loyalty drops to 0 → emit a "town revolts" event; loyalty
# crosses from 60 to 61 → notify EventManager so it can unlock Friendly quests.
# That threshold-crossing logic should live in a private helper here, not in
# the callers.
func adjust_loyalty(_town_id, _delta):
	# TODO: Implement loyalty adjustment and threshold detection.
	pass


# Attempts to construct building_id in town_id.
# Returns false if any of the following are true:
#   - The building already exists in constructed_buildings
#   - The player does not own the town (only player-owned towns can build)
#   - Prerequisites are not met (e.g. market requires inn to exist first)
# On success: adds building_id to the town's constructed_buildings list,
# writes the updated town to GameState, emits building_constructed, and
# returns true.
# TODO: Define prerequisite system. The building catalogue (BuildingData
# resource, not yet created) will carry prereq lists. Until that exists this
# function always returns false so no buildings can be accidentally created
# with incomplete validation.
func construct_building(_town_id, _building_id):
	# TODO: Implement construction validation and execution once BuildingData
	# catalogue exists.
	return false


# ------------------------------------------------------------------------------
# Private Handlers
# ------------------------------------------------------------------------------

# Called when GameState emits town_data_changed. Refreshes our local cache
# entry for town_id from GameState so we stay in sync with external writes
# (e.g. from EventManager applying event outcomes that modify town loyalty or
# ownership directly without going through TownManager).
# TODO: After refreshing the cache entry, check whether any loyalty thresholds
# or ownership triggers should fire as a result of the external change.
# For example, an event outcome might drop loyalty below 20 (Hostile) and
# TownManager should react to that even though it didn't make the change itself.
func _on_town_data_changed(town_id):
	# Pull the fresh state from GameState and update our local mirror.
	_towns[town_id] = GameState.get_town(town_id)
