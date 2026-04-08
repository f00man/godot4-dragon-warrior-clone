# ==============================================================================
# overworld.gd
# Part of: godot4-dragon-warrior-clone
# Description: Root script for the overworld scene. Wires up player signals,
#              keeps GameState in sync with player position, and handles the
#              town-entrance trigger zone. The TileMapLayer is configured via
#              the Godot editor — no tileset generation happens in code.
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

# The Area2D zone at the south edge of the map. When the player walks into it
# they are transported to the sample town scene.
@onready var town_entrance = $TownEntrance


func _ready():
	# Resume playtime when the overworld is ready — the player now has control.
	# Playtime was paused by the main menu (or any other pre-game screen) and
	# resumes here rather than in SceneManager so each scene is responsible for
	# its own playtime contract.
	GameState.resume_playtime()

	# Assign physics collision layers so the CharacterBody2D player stops when
	# it walks into wall tiles painted in the editor.
	# Layer 1 matches the TileSet's physics layer so move_and_collide stops at
	# walls. Using layer 1 (not 2) also means Area2D interaction zones — which
	# default to collision_mask = 1 — can detect the player without extra setup.
	player.collision_layer = 1
	player.collision_mask = 1

	# Wire the town entrance trigger so walking south into the corridor fires
	# a scene transition to the sample town.
	town_entrance.body_entered.connect(_on_town_entrance_body_entered)

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
	EventManager.check_events_for_scene("overworld")


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

# Called every time the player successfully moves to a new tile.
# Updates GameState so the save system always has the correct position.
# This is the single write-point for player_position — the Player node itself
# never touches GameState directly (loose coupling via signals).
func _on_player_moved(new_tile_pos):
	GameState.set_location(GameState.current_scene, new_tile_pos)


# Called when any physics body enters the TownEntrance Area2D.
# We check for the "player" group to avoid reacting to stray physics bodies
# (e.g. if other CharacterBody2D NPCs are ever added to the scene).
func _on_town_entrance_body_entered(body):
	# Only fire for the player, not stray physics bodies.
	if body.is_in_group("player"):
		SceneManager.transition_to("res://scenes/towns/town_sample.tscn")
