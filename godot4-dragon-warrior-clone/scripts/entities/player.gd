# ==============================================================================
# player.gd
# Part of: godot4-dragon-warrior-clone
# Description: Controls the player character on the overworld. Handles
#              grid-based tile movement, input reading, and step counting.
#              Communicates position changes to GameState via signal.
# Attached to: CharacterBody2D (Player) in scenes/world/overworld.tscn
# ==============================================================================

extends CharacterBody2D

# ---------------------------------------------------------------------------
# Signals — declared first per project coding standards.
# ---------------------------------------------------------------------------

# Emitted after every successful tile move. The overworld scene listens to
# this and updates GameState so the player's position is always persisted.
signal player_moved(new_tile_pos)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# The pixel width/height of one map tile. All grid math multiplies by this.
const TILE_SIZE = 32

# ---------------------------------------------------------------------------
# State variables
# ---------------------------------------------------------------------------

# The player's current position expressed in tile coordinates (not pixels).
# Initialized from GameState in _ready() so a loaded save restores correctly.
var tile_position = Vector2.ZERO

# Running total of tiles moved this session. Printed to console for now.
# Will be read by the EncounterManager once that system is wired up.
var step_count = 0


func _ready():
	# Restore position from GameState so loading a save drops the player at
	# their last known location rather than the scene's default origin.
	tile_position = GameState.player_position

	# Snap the node's pixel position to the tile grid by multiplying tile
	# coordinates by the tile size. This ensures the sprite sits exactly on
	# the correct tile from the first frame.
	position = tile_position * TILE_SIZE


func _unhandled_input(event):
	# Use _unhandled_input (not _input) so that open menus, dialogue boxes,
	# or other UI layers can consume directional input first. The overworld
	# only moves the player when nothing else has claimed the event.

	if Input.is_action_just_pressed("move_up"):
		# is_action_just_pressed fires once per keypress — exactly what we
		# want for grid movement. Holding the key does NOT repeat movement;
		# each step requires a fresh press.
		_try_move(Vector2.UP)
	elif Input.is_action_just_pressed("move_down"):
		_try_move(Vector2.DOWN)
	elif Input.is_action_just_pressed("move_left"):
		_try_move(Vector2.LEFT)
	elif Input.is_action_just_pressed("move_right"):
		_try_move(Vector2.RIGHT)


func _try_move(direction):
	# Calculate where the player would land if this move is allowed.
	var new_tile = tile_position + direction

	# TODO: Before updating position, check the TileMapLayer for collision
	# data once a tileset with physics layers is assigned. Query the tile at
	# new_tile and early-return here if it is flagged as impassable.
	# Example (not yet active):
	#   if _tile_is_impassable(new_tile):
	#       return

	# Move is valid — commit the new tile coordinate.
	tile_position = new_tile

	# Snap the sprite to the new tile's pixel position on the same frame.
	position = tile_position * TILE_SIZE

	# Track how many tiles the player has walked. The encounter system will
	# compare this against a zone-specific threshold to roll for battles.
	step_count += 1
	print("Step %d — tile position: %s" % [step_count, tile_position])

	# Notify the overworld (and anything else listening) that the player has
	# moved. Keeps GameState in sync without this script needing to know
	# anything about GameState directly — loose coupling via signals.
	player_moved.emit(tile_position)
