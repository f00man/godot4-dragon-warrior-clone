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

# ---------------------------------------------------------------------------
# Exports — designer-tweakable in the Inspector
# ---------------------------------------------------------------------------

# Default encounter rate: 1-in-16 chance per step (1/16 = 0.0625).
# Override per zone via set_zone_encounter_rate().
# Designer-tweakable in the Inspector.
@export var base_encounter_rate = 0.0625

# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

# Active encounter rate for the current zone. Starts equal to base_encounter_rate;
# updated by set_zone_encounter_rate() when the player enters a new zone.
var _current_encounter_rate = 0.0625

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

	# Hand off to SceneManager for the fade transition. Battle scene takes over
	# from here; return_to_overworld() in battle_scene.gd calls
	# SceneManager.transition_back().
	SceneManager.transition_to(BATTLE_SCENE_PATH)


# Overrides the encounter rate for the current zone. Call this when the player
# enters a new zone tile or area. Pass 0.0 to disable encounters entirely
# (e.g. in safe zones near towns). Rate should be between 0.0 (never) and
# 1.0 (every step).
func set_zone_encounter_rate(rate):
	_current_encounter_rate = rate
