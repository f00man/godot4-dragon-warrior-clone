# ==============================================================================
# staircase.gd
# Part of: godot4-dragon-warrior-clone
# Description: Auto-trigger staircase. When the player steps onto this Area2D,
#              the spawn position in the destination scene is written to
#              GameState.player_position and SceneManager performs the transition.
#              Mirrors Dragon Warrior's "step on stairs = immediately descend"
#              behaviour — no button press required.
# Attached to: Area2D (Staircase) in castle/dungeon scenes
# ==============================================================================

extends Area2D

# ------------------------------------------------------------------------------
# Exports — set these in the Inspector per staircase instance.
# ------------------------------------------------------------------------------

# Full res:// path to the destination scene.
# Example: "res://scenes/towns/tantegel_castle_lower.tscn"
# Left empty by default so a misconfigured staircase does nothing harmful
# rather than transitioning to an invalid path.
@export var target_scene = ""

# Tile coordinates (column, row) where the player should appear in the
# destination scene. player.gd reads GameState.player_position in _ready()
# and multiplies by TILE_SIZE (32) to convert to pixel position.
# Default (7, 8) is a reasonable centre-of-room starting tile; override per instance.
@export var spawn_tile = Vector2(7, 8)

# ------------------------------------------------------------------------------
# State
# ------------------------------------------------------------------------------

# Guard flag that prevents the transition from firing twice if the physics
# engine emits body_entered on back-to-back frames before the scene swap occurs.
# Set to true the moment transition begins; never reset (the node is freed when
# the scene unloads, so there is no need to reset it).
var _transitioning = false

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Connect body_entered in code per project standards (not the editor).
	# Area2D emits this signal when a physics body (including CharacterBody2D)
	# begins overlapping the staircase collision shape.
	body_entered.connect(_on_body_entered)

# ------------------------------------------------------------------------------
# Collision callback — the transition entry point
# ------------------------------------------------------------------------------

# Fires when any physics body steps onto the staircase.
# Only acts when the body belongs to the "player" group.
func _on_body_entered(body):
	# Ignore bodies that are not the player (enemies, NPCs, physics objects, etc.).
	if not body.is_in_group("player"):
		return

	# Block double-fire: if a transition is already in progress from a previous
	# frame, discard this callback. Without this guard, the SceneManager would
	# receive two transition_to() calls in quick succession and the second call
	# would be silently dropped by SceneManager's own _is_transitioning guard —
	# but a warning would be printed. This flag avoids even that noise.
	if _transitioning:
		return

	# Validate that a destination scene was actually configured in the Inspector.
	# An empty target_scene would hand SceneManager an invalid path, which would
	# fail with an error and leave the screen black. Warn and bail out instead.
	if target_scene == "":
		push_warning("Staircase: target_scene is empty — assign a res:// path in the Inspector.")
		return

	# Commit the transition: from this point on, treat the staircase as used.
	_transitioning = true

	# Write the spawn tile to GameState before the scene swap so that when
	# player.gd's _ready() runs in the destination scene it reads the correct
	# starting position. GameState persists across scene changes (autoload),
	# so the value survives the transition cleanly.
	GameState.player_position = spawn_tile

	# Hand off to SceneManager for the actual fade-out / scene-load / fade-in.
	# SceneManager.transition_to() is non-blocking — it runs asynchronously via
	# coroutines, so this callback returns immediately after the call.
	SceneManager.transition_to(target_scene)
