# ==============================================================================
# encounter_manager.gd
# Part of: godot4-dragon-warrior-clone
# Description: Rolls for random encounters on each player step. Added as a
#              child node to the overworld scene — NOT an autoload. Each zone
#              can override the encounter rate via set_zone_encounter_rate().
# Attached to: Node (EncounterManager) as child of Overworld
# ==============================================================================

extends Node

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Path to the battle scene. SceneManager transitions here when an encounter fires.
const BATTLE_SCENE_PATH = "res://scenes/battle/battle_scene.tscn"

# Maps a substring of the current scene path to a list of enemy .tres resource
# paths that can appear in that zone.
#
# Rules:
#   - Keys are plain substrings — the first key whose substring is found inside
#     GameState.current_scene wins, so list more-specific keys before general
#     ones (e.g. "overworld_desert" before "overworld").
#   - Towns carry encounter_rate = 0.0 so they never reach this table in normal
#     play, but they are included as a safety net in case a non-zero rate is
#     ever configured accidentally.
#   - An empty list means "no valid enemies for this zone" — _pick_enemy_for_scene()
#     falls back to the slime rather than crashing.
const ENCOUNTER_TABLES = {
	"overworld": [
		"res://resources/enemies/slime.tres",
		"res://resources/enemies/drakee.tres",
	],
	"town": [],
}

# ---------------------------------------------------------------------------
# Exports — designer-tweakable in the Inspector
# ---------------------------------------------------------------------------

# Default encounter rate: 1-in-50 chance per step (1/50 = 0.02).
# Dragon Warrior NES was roughly 1-in-32 to 1-in-64 depending on zone.
# Override per zone via set_zone_encounter_rate().
# Designer-tweakable in the Inspector.
@export var base_encounter_rate = 0.02

# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

# Active encounter rate for the current zone. Starts equal to base_encounter_rate;
# updated by set_zone_encounter_rate() when the player enters a new zone.
var _current_encounter_rate = 0.02

# Stores the scene path to return to after battle ends. Set immediately before
# transitioning to the battle scene so SceneManager.transition_back() lands
# in the right place.
var _return_scene_path = ""


func _ready():
	# Seed the active rate from the exported base on scene load. Zones that need
	# a different rate call set_zone_encounter_rate() after the scene is ready.
	_current_encounter_rate = base_encounter_rate


# Called by the overworld each time the player moves one tile. Receives the
# player's new tile position so this function could later filter by zone,
# but for now it only uses the configured rate for a flat probability roll.
#
# tile_position is received from the player_moved signal but not used in the
# roll itself — it's available here for future use (e.g. zone-specific rates
# based on tile type or coordinates).
func on_player_stepped(tile_position):
	# randf() returns a float in [0.0, 1.0). Comparing against
	# _current_encounter_rate gives exactly that probability of triggering per step.
	if randf() < _current_encounter_rate:
		_trigger_encounter()


# Fires when the encounter roll succeeds. Stores the return path and hands
# off to SceneManager for the fade transition into the battle scene.
func _trigger_encounter():
	print("EncounterManager: encounter triggered!")

	# Save the current scene path before transitioning so battle knows where to
	# send the player afterward. GameState.current_scene is kept current by
	# SceneManager.
	_return_scene_path = GameState.current_scene

	# Pick the enemy for this zone and queue it for the battle scene to consume.
	# _pick_enemy_for_scene() handles all the zone-lookup and fallback logic so
	# this function stays focused on the transition, not the selection.
	GameState.pending_battle_enemies = [_pick_enemy_for_scene()]

	# Hand off to SceneManager for the fade transition. Battle scene takes over
	# from here; return_to_overworld() in battle_scene.gd calls
	# SceneManager.transition_back().
	SceneManager.transition_to(BATTLE_SCENE_PATH)


# Looks up the current scene path in ENCOUNTER_TABLES, picks a random enemy
# resource path from the matching list, and returns the loaded Resource.
#
# Selection logic:
#   1. Iterate ENCOUNTER_TABLES keys. The first key whose substring is found
#      inside GameState.current_scene wins.
#   2. If the matching list is empty (e.g. "town"), fall through to the fallback.
#   3. If no key matches at all, fall through to the fallback.
#   Fallback: always the slime — guarantees the function never returns null.
func _pick_enemy_for_scene():
	# Fallback path used when no table entry matches or a matched table is empty.
	# The slime is the gentlest enemy in the game, so it is the safest default.
	var fallback_path = "res://resources/enemies/slime.tres"

	# Walk the table in key-insertion order. The first substring match wins, so
	# more-specific keys (listed first in ENCOUNTER_TABLES) take priority.
	for zone_key in ENCOUNTER_TABLES:
		if GameState.current_scene.contains(zone_key):
			var enemy_paths = ENCOUNTER_TABLES[zone_key]

			# An empty list means this zone deliberately has no encounters.
			# Fall through to the fallback rather than calling pick_random_index
			# on an empty array (which would crash).
			if enemy_paths.is_empty():
				break

			# Pick a random index from the valid paths. randi() % n is fine for
			# a small table — no need for a weighted picker at this stage.
			var chosen_path = enemy_paths[randi() % enemy_paths.size()]
			return load(chosen_path)

	# No matching zone key, or the matched zone's table was empty — load the
	# fallback slime so the battle scene always receives a valid enemy resource.
	return load(fallback_path)


# Overrides the encounter rate for the current zone. Call this when the player
# enters a new zone tile or area. Pass 0.0 to disable encounters entirely
# (e.g. in safe zones near towns). Rate should be between 0.0 (never) and
# 1.0 (every step).
func set_zone_encounter_rate(rate):
	_current_encounter_rate = rate
