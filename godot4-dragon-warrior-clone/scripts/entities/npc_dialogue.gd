# ==============================================================================
# npc_dialogue.gd
# Part of: godot4-dragon-warrior-clone
# Description: Generic NPC that shows multi-page dialogue when the player presses
#              Accept while in range. One script drives every non-scripted NPC in
#              the castle (guards, chancellor, sage, etc.) — designer sets the
#              speaker name and dialogue text in the Inspector via @export vars.
# Attached to: CharacterBody2D (NPC) in castle/town scenes
# ==============================================================================

extends CharacterBody2D

# ------------------------------------------------------------------------------
# Exports — set these in the Inspector for each NPC instance.
# No stats or names are hardcoded here; all content lives in the scene file.
# ------------------------------------------------------------------------------

# The name displayed in the dialogue box speaker label when this NPC speaks.
# Default matches a generic guard; override per-instance in the Inspector.
@export var speaker_name = "Guard"

# Each entry in this array is one page of dialogue text.
# The DialogueBox advances through pages as the player presses Accept.
# An empty array will show nothing (the NPC silently ignores interaction).
@export var dialogue_pages: Array = ["..."]

# ------------------------------------------------------------------------------
# State
# ------------------------------------------------------------------------------

# True while the player's CharacterBody2D is inside the InteractionZone Area2D.
# Checked in _process() so input is only polled when proximity is relevant.
var _player_in_range = false

# ------------------------------------------------------------------------------
# Node References
# ------------------------------------------------------------------------------

# The Area2D child node that detects when the player enters and leaves talking
# range. Named InteractionZone by convention so scenes are consistent.
@onready var interaction_zone = $InteractionZone

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Connect the proximity signals in code (not the editor) per project standards.
	# body_entered fires when any physics body overlaps the InteractionZone;
	# body_exited fires when it leaves. Both filter on the "player" group.
	interaction_zone.body_entered.connect(_on_body_entered)
	interaction_zone.body_exited.connect(_on_body_exited)

# ------------------------------------------------------------------------------
# Input — polled every frame, gated on player proximity
# ------------------------------------------------------------------------------

func _process(_delta):
	# Only listen for the Accept input when the player is standing close enough
	# to this NPC. is_action_just_pressed fires once per keypress — the player
	# must release and press again to get a second dialogue trigger.
	if _player_in_range and Input.is_action_just_pressed("ui_accept"):
		_speak()

# ------------------------------------------------------------------------------
# Private: Dialogue trigger
# ------------------------------------------------------------------------------

# Sends this NPC's multi-page dialogue through EventManager's dialogue_requested
# signal so the active DialogueBox can display it. Using the signal instead of a
# direct DialogueBox node reference keeps this script decoupled from the scene
# hierarchy — the script works correctly in any scene that has a DialogueBox
# connected to EventManager.dialogue_requested.
#
# EventManager.dialogue_requested signature:
#   (speaker: String, pages: Array, choices: Array, world_pos: Vector2)
# We pass an empty choices array because generic NPCs do not present player
# choices — they simply speak their lines. Pass global_position as the world
# anchor so the DialogueBox can position itself near the NPC rather than
# defaulting to the bottom bar.
func _speak():
	# Guard: skip the signal emit if there is nothing to say. This prevents the
	# DialogueBox from opening to an empty panel if an NPC instance was placed
	# in the scene without dialogue_pages being configured.
	if dialogue_pages.is_empty():
		return

	# Emit dialogue_requested directly on EventManager. EventManager.request_dialogue()
	# only wraps a single string into a one-page array, so we bypass it and emit
	# the signal ourselves to pass the full multi-page array unchanged.
	EventManager.emit_signal("dialogue_requested", speaker_name, dialogue_pages, [], global_position)

# ------------------------------------------------------------------------------
# Body detection callbacks
# ------------------------------------------------------------------------------

# Mark the player as in range when their CharacterBody2D enters the zone.
# is_in_group("player") ensures enemy bodies, NPCs, or other physics objects
# that might overlap the zone do not accidentally set the flag.
func _on_body_entered(body):
	if body.is_in_group("player"):
		_player_in_range = true

# Clear the proximity flag when the player moves out of the zone.
# This stops _process() from checking for input until the player returns.
func _on_body_exited(body):
	if body.is_in_group("player"):
		_player_in_range = false
