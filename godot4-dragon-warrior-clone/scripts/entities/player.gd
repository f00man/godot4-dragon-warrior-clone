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

# The direction the player is currently facing. Updated on every input press,
# including failed moves, so the player turns to face a wall when blocked.
# Defaults to DOWN matching Dragon Warrior's starting orientation.
var facing = Vector2.DOWN

# Running total of tiles moved this session. Printed to console for now.
# Will be read by the EncounterManager once that system is wired up.
var step_count = 0

# Small ColorRect child node created in _ready() that marks the facing edge.
var _direction_indicator = null


func _ready():
	# Register the player in the "player" group so NPC InteractionZones and the
	# TownEntrance Area2D can identify which body entered without needing a
	# direct node reference. Standard Godot pattern for body-type detection.
	add_to_group("player")

	# Restore position from GameState so loading a save drops the player at
	# their last known location rather than the scene's default origin.
	tile_position = GameState.player_position

	# Snap the node's pixel position to the tile grid by multiplying tile
	# coordinates by the tile size. This ensures the sprite sits exactly on
	# the correct tile from the first frame.
	position = tile_position * TILE_SIZE

	# Build the facing indicator and set its initial position. Creating it here
	# in code means every scene that uses player.gd gets it for free — no .tscn
	# edits required. It is added last so it renders on top of PlaceholderRect.
	_direction_indicator = ColorRect.new()
	_direction_indicator.size = Vector2(8, 8)
	_direction_indicator.color = Color(0.05, 0.05, 0.25)  # dark navy, contrasts cyan
	add_child(_direction_indicator)
	_update_direction_indicator()


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


# Repositions the direction indicator to the center of the facing edge.
# The player sprite occupies (0,0)→(32,32) relative to the node origin.
# The 8x8 indicator is centered on whichever edge matches `facing`.
func _update_direction_indicator():
	if _direction_indicator == null:
		return
	# Calculate the top-left position of the 8x8 dot so it sits centered
	# on the correct edge of the 32x32 tile.
	var center_offset = (TILE_SIZE - 8) / 2  # = 12  — centres the dot on an edge
	if facing == Vector2.UP:
		_direction_indicator.position = Vector2(center_offset, 0)
	elif facing == Vector2.DOWN:
		_direction_indicator.position = Vector2(center_offset, TILE_SIZE - 8)
	elif facing == Vector2.LEFT:
		_direction_indicator.position = Vector2(0, center_offset)
	elif facing == Vector2.RIGHT:
		_direction_indicator.position = Vector2(TILE_SIZE - 8, center_offset)


func _try_move(direction):
	# Update facing immediately so the player turns toward a wall even when
	# the move is blocked — matches Dragon Warrior's input feel.
	facing = direction
	_update_direction_indicator()

	# Convert the unit-direction vector into a full-tile pixel displacement.
	# move_and_collide expects a motion in pixel space, not tile space.
	var motion = direction * TILE_SIZE

	# Attempt the move through Godot's physics engine. move_and_collide returns
	# a KinematicCollision2D object if something blocked the motion, or null if
	# the player moved freely. This replaces the old direct position assignment
	# so wall tile collision shapes actually stop movement.
	var collision = move_and_collide(motion)

	if collision != null:
		# A physics body (the TileMapLayer wall shape) blocked the full motion.
		# Do NOT update tile_position or emit player_moved — from the game's
		# perspective the player did not change tiles.
		# move_and_collide may have slid the body slightly along a surface, but
		# for grid movement we want to stay exactly on the grid, so snap back.
		position = tile_position * TILE_SIZE
		return

	# Move was unobstructed — commit the new tile coordinate.
	# We derive tile_position from the actual post-move pixel position to stay
	# in sync with what move_and_collide wrote, then snap to the nearest grid
	# origin so any sub-pixel drift is eliminated.
	tile_position = tile_position + direction

	# Snap the pixel position to the exact tile grid coordinate. This guards
	# against any floating-point drift that move_and_collide might introduce.
	position = tile_position * TILE_SIZE

	# Track how many tiles the player has walked. The encounter system will
	# compare this against a zone-specific threshold to roll for battles.
	step_count += 1
	print("Step %d — tile position: %s" % [step_count, tile_position])

	# Notify the overworld (and anything else listening) that the player has
	# moved. Keeps GameState in sync without this script needing to know
	# anything about GameState directly — loose coupling via signals.
	player_moved.emit(tile_position)
