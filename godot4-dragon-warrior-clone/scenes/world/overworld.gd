# ==============================================================================
# overworld.gd
# Part of: godot4-dragon-warrior-clone
# Description: Root script for the overworld scene. Wires up player signals,
#              keeps GameState in sync with player position, detects when the
#              player steps onto a town, castle, or cave tile, and fires the
#              appropriate scene transition. Random encounter checks are
#              delegated to EncounterManager on every step.
# Attached to: Node2D (Overworld) in scenes/world/overworld.tscn
# ==============================================================================

extends Node2D

# ------------------------------------------------------------------------------
# Tile type indices — must match generate_overworld.gd and the tileset atlas.
# Declared here so _check_tile_entrance() can compare against them without
# importing a separate file.
# ------------------------------------------------------------------------------
const OCEAN    = 0
const PLAINS   = 1
const FOREST   = 2
const MOUNTAIN = 3
const SWAMP    = 4
const DESERT   = 5
const BRIDGE   = 6
const TOWN     = 7
const CAVE     = 8
const CASTLE   = 9

# ------------------------------------------------------------------------------
# Landmark entrance map
# Maps "x,y" tile coordinate strings to their destination scene path.
# When the player steps onto any tile listed here the scene transition fires
# immediately. Placeholder entries (empty string) are silently ignored so
# caves without scenes don't crash the game.
#
# Extend this dictionary whenever a new town/cave/dungeon scene is created.
# ------------------------------------------------------------------------------
const ENTRANCES = {
	# Castles
	"45,43":  "res://scenes/world/tantegel_throne_room.tscn",  # Tantegel Castle

	# Towns — all placeholder to town_sample until individual scenes exist
	"44,47":  "res://scenes/towns/town_sample.tscn",   # Brecconary
	"17,27":  "res://scenes/towns/town_sample.tscn",   # Garinham     (placeholder)
	"58,17":  "res://scenes/towns/town_sample.tscn",   # Kol          (placeholder)
	"92,55":  "res://scenes/towns/town_sample.tscn",   # Rimuldar     (placeholder)
	"30,89":  "res://scenes/towns/town_sample.tscn",   # Cantlin      (placeholder)
	"51,81":  "res://scenes/towns/town_sample.tscn",   # Hauksness    (placeholder)

	# Caves — empty strings until dungeon scenes are built
	"26,24":  "",  # Grave of Garin
	"62,22":  "",  # Mountain Cave
	"64,46":  "",  # Swamp Cave
	"26,90":  "",  # Erdrick's Cave
	"52,78":  "",  # Hauksness cave
	"87,18":  "",  # Cave of Domdora

	# Charlock Castle — endgame; placeholder for now
	"58,105": "",
}

# ------------------------------------------------------------------------------
# Node references — resolved once at _ready, not on every access.
# ------------------------------------------------------------------------------

# Direct reference to the Player CharacterBody2D child node.
@onready var player = $Player

# EncounterManager receives every player step to roll for random encounters.
@onready var encounter_manager = $EncounterManager

# TileMapLayer node — queried per step to check tile type under the player.
@onready var tilemap = $TileMapLayer


# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Resume playtime — the player is now in control of the overworld.
	# Playtime was paused by any pre-game screen (main menu, save screen, etc.)
	# and is resumed here rather than in SceneManager so each scene owns its
	# own playtime contract.
	GameState.resume_playtime()

	# Collision layer 1 = world physics, matching the TileMapLayer's physics
	# layer so the player stops at ocean and mountain tiles.
	player.collision_layer = 1
	player.collision_mask  = 1

	# Route every step to both GameState (position tracking) and the encounter
	# system (random battle rolls). Signals keep the subsystems decoupled —
	# player.gd only knows it moved; the listeners decide what that means.
	player.player_moved.connect(_on_player_moved)
	player.player_moved.connect(encounter_manager.on_player_stepped)

	# Check for world-flag-triggered events when the player enters the overworld
	# (e.g. story cutscenes, quest completion notifications, etc.).
	EventManager.check_events_for_scene("overworld")


# ------------------------------------------------------------------------------
# Signal handlers
# ------------------------------------------------------------------------------

# Called every time the player moves to a new tile.
# 1. Syncs position to GameState so save/load always has the current location.
# 2. Checks whether the new tile is a town, cave, or castle entrance and fires
#    the appropriate scene transition.
func _on_player_moved(new_tile_pos):
	GameState.set_location(GameState.current_scene, new_tile_pos)
	_check_tile_entrance(new_tile_pos)


# Looks up the new tile position in ENTRANCES. If a destination is registered
# and non-empty, triggers an immediate scene transition.
func _check_tile_entrance(tile_pos):
	var key = "%d,%d" % [int(tile_pos.x), int(tile_pos.y)]
	if not ENTRANCES.has(key):
		return

	var dest = ENTRANCES[key]

	# Empty string = entrance exists in the data but scene not yet built.
	# Log a warning so the designer knows the tile is registering correctly,
	# but don't crash.
	if dest == "":
		push_warning("overworld: stepped on entrance at %s but no scene assigned" % key)
		return

	SceneManager.transition_to(dest)
