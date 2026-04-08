# ==============================================================================
# chest.gd
# Part of: godot4-dragon-warrior-clone
# Description: One-time treasure chest that grants the player a single item.
#              Tracks whether it has been opened via a world flag so the state
#              survives save/load. Visually dims when opened so players can tell
#              at a glance which chests they have already looted.
# Attached to: Node2D (Chest) in scenes/towns/town_sample.tscn
# ==============================================================================

extends Node2D

# ------------------------------------------------------------------------------
# Exports — editable in the Inspector so the same script serves any chest
# ------------------------------------------------------------------------------

# The item_id string to grant when the chest is opened.
# Must match an entry in the item registry (resources/items/).
@export var item_id = "royal_scroll"

# The world flag key used to remember whether this chest has been opened.
# Each chest in the game should use a unique flag so they track independently.
@export var world_flag = "chest_town_royal_scroll"

# ------------------------------------------------------------------------------
# State
# ------------------------------------------------------------------------------

# True once the chest has been opened this session (or was already open on load).
# Used to prevent double-triggering when the player stands in range.
var _already_opened = false

# True while the player's body is overlapping the InteractionZone.
# Only checked in _process; keeps input polling efficient.
var _player_in_range = false

# ------------------------------------------------------------------------------
# Node References
# ------------------------------------------------------------------------------

# The Area2D child that detects the player stepping close to the chest.
@onready var interaction_zone = $InteractionZone

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Connect the proximity signals so _player_in_range stays accurate.
	# Done in _ready() (not the editor) per project coding standards.
	interaction_zone.body_entered.connect(_on_body_entered)
	interaction_zone.body_exited.connect(_on_body_exited)

	# If the world flag is already set, this chest was opened in a previous
	# session. Mark it as opened and dim it immediately so the state matches
	# what was saved — the player should never be able to loot the same chest twice.
	if GameState.get_flag(world_flag):
		_mark_opened()

# ------------------------------------------------------------------------------
# Input — checked every frame, gates on player proximity
# ------------------------------------------------------------------------------

func _process(_delta):
	# Only respond when the player is standing in the interaction zone AND the
	# chest has not already been opened. is_action_just_pressed fires once per
	# keypress so holding the button doesn't spam the dialogue system.
	if _player_in_range and not _already_opened and Input.is_action_just_pressed("ui_accept"):
		_open_chest()

# ------------------------------------------------------------------------------
# Private: Chest interaction logic
# ------------------------------------------------------------------------------

# Grants the item to the player, records the world flag, shows dialogue,
# and visually marks the chest as depleted.
func _open_chest():
	# Give the player the item via GameState — this is the authoritative place
	# where items enter the inventory. add_item() handles stacking automatically.
	GameState.add_item(item_id, 1)

	# Persist the opened state as a world flag so SaveManager picks it up and
	# the chest remains empty if the player saves and reloads.
	GameState.set_flag(world_flag, true)

	# Show discovery dialogue near the chest. global_position lets the DialogueBox
	# place itself above or below the chest rather than always at the bottom bar.
	EventManager.request_dialogue("Treasure Chest", "You found a Royal Scroll!", [], global_position)

	# Dim and lock the chest in the same frame so feedback is immediate.
	_mark_opened()

# Applies the "already opened" visual state and sets the local guard flag.
# Called both from _open_chest() (first open) and _ready() (loaded-save case).
func _mark_opened():
	# Reduce alpha to 0.4 to signal that this chest is depleted.
	# The chest node remains visible so players can confirm they checked it,
	# but the reduced opacity distinguishes it from an untouched chest.
	modulate.a = 0.4

	# Set the local flag so _process stops checking for input on this chest.
	_already_opened = true

# ------------------------------------------------------------------------------
# Body detection callbacks
# ------------------------------------------------------------------------------

# Set the proximity flag when the player enters the interaction zone.
# Checking is_in_group("player") prevents objects or NPCs from triggering the chest.
func _on_body_entered(body):
	if body.is_in_group("player"):
		_player_in_range = true

# Clear the proximity flag when the player moves away.
func _on_body_exited(body):
	if body.is_in_group("player"):
		_player_in_range = false
