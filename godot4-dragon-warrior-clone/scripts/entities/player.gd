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

	var dest = tile_position + direction

	# --- Tile-type blocking (overworld terrain) ---
	# Check whether the destination tile is passable before attempting any
	# physics move. This handles ocean and mountain blocking without needing
	# physics collision shapes on the TileSet, which avoids version-dependent
	# TileData physics polygon APIs.
	if _is_tile_blocked(dest):
		return

	# --- Physics-body blocking (castle walls, NPC colliders, etc.) ---
	# move_and_collide handles StaticBody2D walls placed in castle/town scenes.
	# On the overworld the TileMapLayer has no physics layer, so this only fires
	# when the player bumps into a scene-placed physics object.
	var motion = direction * TILE_SIZE
	var collision = move_and_collide(motion)
	if collision != null:
		# A StaticBody2D blocked the move. Snap back to the exact grid position
		# to prevent any sub-pixel drift from the partial move_and_collide slide.
		position = tile_position * TILE_SIZE
		return

	# Move was clear — commit the new tile coordinate and pixel position.
	tile_position = dest
	position = tile_position * TILE_SIZE

	step_count += 1
	print("Step %d — tile: %s" % [step_count, tile_position])

	# Notify listeners (overworld.gd updates GameState; EncounterManager rolls
	# for a random battle). Loose coupling — player.gd emits, others react.
	player_moved.emit(tile_position)


# Returns true if the tile at tile_pos should block the player.
# Looks for a TileMapLayer sibling node; if none exists (e.g. in castle scenes
# that use StaticBody2D walls instead) this always returns false so physics
# blocking takes over.
func _is_tile_blocked(tile_pos):
	var tilemap = get_node_or_null("../TileMapLayer")
	if tilemap == null or tilemap.tile_set == null:
		return false

	var ipos = Vector2i(int(tile_pos.x), int(tile_pos.y))
	var atlas = tilemap.get_cell_atlas_coords(ipos)

	# Vector2i(-1,-1) means no tile at that cell — off the edge of the map.
	# Treat as blocked so the player cannot walk into empty space.
	if atlas == Vector2i(-1, -1):
		return true

	# The tile type is encoded in the atlas X coordinate (column index),
	# matching the 10-column placeholder tileset built in overworld.gd.
	# OCEAN = column 0, MOUNTAIN = column 3.
	var tile_type = atlas.x
	return tile_type == 0 or tile_type == 3
