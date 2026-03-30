# ==============================================================================
# overworld.gd
# Part of: godot4-dragon-warrior-clone
# Description: Root script for the overworld scene. Wires up player signals,
#              keeps GameState in sync with player position, and will later
#              handle random encounter checks and scene-entry events.
# Attached to: Node2D (Overworld) in scenes/world/overworld.tscn
# ==============================================================================

extends Node2D

# ---------------------------------------------------------------------------
# Node references — resolved once at scene ready, not on every access.
# ---------------------------------------------------------------------------

# Direct reference to the Player CharacterBody2D child node.
@onready var player = $Player

# Reference to the EncounterManager child node. Connected to player_moved in
# _ready() so it receives every step.
@onready var encounter_manager = $EncounterManager


func _ready():
	# Resume playtime when the overworld is ready — the player now has control.
	# Playtime was paused by the main menu (or any other pre-game screen) and
	# resumes here rather than in SceneManager so each scene is responsible for
	# its own playtime contract.
	GameState.resume_playtime()

	# Connect player movement signal so GameState stays in sync without the
	# player script needing to know about GameState directly. Signals keep the
	# two scripts loosely coupled — player.gd only knows it moved; overworld.gd
	# decides what that means for the rest of the game.
	player.player_moved.connect(_on_player_moved)

	# Also route every step to EncounterManager so it can roll for random
	# encounters independently of GameState updates.
	player.player_moved.connect(encounter_manager.on_player_stepped)

	# Check for any events that should fire when the player enters the overworld
	# (e.g. a cutscene triggered by a world flag, a quest update, etc.).
	# This is a stub call — EventManager.check_events_for_scene() has no
	# real behaviour yet (see TODO E3 in CLAUDE.md).
	EventManager.check_events_for_scene("overworld")


func _on_player_moved(new_tile_pos):
	# Keep GameState in sync so SaveManager always captures the correct tile
	# position when the player saves. This is the single write-point for
	# player_position — the Player node itself never touches GameState directly.
	#
	# The future EncounterManager will read step_count from the Player node
	# directly (via a group lookup or a direct reference) rather than through
	# this signal, so encounter logic does not need to live here.
	GameState.set_location(GameState.current_scene, new_tile_pos)
