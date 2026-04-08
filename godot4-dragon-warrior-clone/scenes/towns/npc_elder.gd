# ==============================================================================
# npc_elder.gd
# Part of: godot4-dragon-warrior-clone
# Description: Script for the Village Elder NPC in the sample town scene.
#              Detects when the player is in the InteractionZone and, on
#              ui_accept, triggers a multi-choice dialogue via EventManager.
# Attached to: CharacterBody2D (NPC_Elder) in scenes/towns/town_sample.tscn
# ==============================================================================

extends CharacterBody2D

# ------------------------------------------------------------------------------
# State
# ------------------------------------------------------------------------------

# True while the player's body is overlapping this NPC's InteractionZone.
# Checked each frame in _process so we only listen for input when it is relevant.
var _player_in_range = false

# ------------------------------------------------------------------------------
# Node References
# ------------------------------------------------------------------------------

# The Area2D child that detects the player entering and leaving talking range.
@onready var interaction_zone = $InteractionZone

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Connect the Area2D body signals so _player_in_range tracks correctly.
	# Using signal connections in _ready() (not the editor) per project standards.
	interaction_zone.body_entered.connect(_on_body_entered)
	interaction_zone.body_exited.connect(_on_body_exited)

# ------------------------------------------------------------------------------
# Input — checked every frame, but only acts when the player is nearby
# ------------------------------------------------------------------------------

func _process(_delta):
	# Only respond to ui_accept when the player is standing in the interaction zone.
	# is_action_just_pressed fires once per keypress, preventing repeated triggers
	# on the same held frame — exactly what grid-based dialogue needs.
	if _player_in_range and Input.is_action_just_pressed("ui_accept"):
		_speak()

# ------------------------------------------------------------------------------
# Private: Dialogue trigger
# ------------------------------------------------------------------------------

# Sends the elder's opening line through EventManager so the active DialogueBox
# displays it without this script needing a direct reference to any UI node.
# EventManager.request_dialogue wraps the text string into a single-page array
# internally, so we pass one string here (not an Array).
func _speak():
	EventManager.request_dialogue(
		"Village Elder",
		"Welcome, brave adventurer. Our village has been threatened by dark forces. Will you help us?",
		["Of course!", "Maybe later."]
	)

# ------------------------------------------------------------------------------
# Body detection callbacks
# ------------------------------------------------------------------------------

# Mark the player as in range when their CharacterBody2D enters the zone.
# Checking is_in_group("player") avoids reacting to enemy or object bodies
# that may also overlap this area later in development.
# NOTE: player.gd must call add_to_group("player") in _ready() for this to work.
#       That call was added to scripts/entities/player.gd as part of this commit.
func _on_body_entered(body):
	if body.is_in_group("player"):
		_player_in_range = true

# Clear the flag when the player walks away so we stop checking for input.
func _on_body_exited(body):
	if body.is_in_group("player"):
		_player_in_range = false
