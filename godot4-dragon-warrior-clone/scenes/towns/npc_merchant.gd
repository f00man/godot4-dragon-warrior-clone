# ==============================================================================
# npc_merchant.gd
# Part of: godot4-dragon-warrior-clone
# Description: Simple herb merchant NPC for the sample town. Sells one Herb
#              for 10 gold when the player interacts. No choice UI — the
#              transaction is immediate and a single line of dialogue confirms
#              it. This is a proof-of-concept; a full shop UI should replace
#              this when the shop system is built.
# Attached to: CharacterBody2D (NPC_Merchant) in scenes/towns/town_sample.tscn
#
# TODO: Replace the immediate-sale pattern with a proper shop UI scene that
#       presents a browseable inventory, quantity selection, and a buy/sell
#       toggle. The shop UI should read the town's shop_inventory list from
#       TownManager.get_town() so the available items are data-driven.
# ==============================================================================

extends CharacterBody2D

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------

# Price of a single herb in gold. Defined as a constant so it is easy to
# find and change without hunting through logic branches.
const HERB_COST = 10

# ------------------------------------------------------------------------------
# State
# ------------------------------------------------------------------------------

# True while the player's CharacterBody2D is inside the InteractionZone.
# Checked each frame in _process to gate input listening.
var _player_in_range = false

# ------------------------------------------------------------------------------
# Node References
# ------------------------------------------------------------------------------

# The Area2D child that detects the player entering talking range.
@onready var interaction_zone = $InteractionZone

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Connect the body signals so _player_in_range tracks player proximity.
	# Connected in _ready() (not the editor) per project standards.
	interaction_zone.body_entered.connect(_on_body_entered)
	interaction_zone.body_exited.connect(_on_body_exited)

# ------------------------------------------------------------------------------
# Input — checked every frame, gates on player proximity
# ------------------------------------------------------------------------------

func _process(_delta):
	# Only respond when the player is adjacent to the merchant.
	# is_action_just_pressed prevents the transaction from firing on every frame
	# while the button is held — the player gets exactly one interaction per press.
	if _player_in_range and Input.is_action_just_pressed("ui_accept"):
		_attempt_sale()

# ------------------------------------------------------------------------------
# Private: Sale logic
# ------------------------------------------------------------------------------

# Tries to sell one herb to the player for HERB_COST gold.
# Checks whether the player can afford it first; shows appropriate dialogue
# either way. The actual gold deduction and item grant only happen on success.
func _attempt_sale():
	if GameState.gold >= HERB_COST:
		# The player has enough gold — complete the transaction immediately.
		# modify_gold with a negative amount deducts gold; emits gold_changed
		# so the HUD refreshes without this script touching the HUD directly.
		GameState.modify_gold(-HERB_COST)

		# Add one herb to the player's inventory. add_item() handles stacking,
		# so if the player already carries herbs the count just increments.
		GameState.add_item("herb", 1)

		# Confirm the sale through EventManager so the active DialogueBox
		# displays the line without this script needing a direct UI reference.
		# Pass global_position so the DialogueBox can place itself near the merchant.
		EventManager.request_dialogue(
			"Merchant",
			"Sold you an herb for %dG!" % HERB_COST,
			[],
			global_position
		)
	else:
		# Not enough gold — tell the player without completing any transaction.
		EventManager.request_dialogue(
			"Merchant",
			"You need %dG for an herb." % HERB_COST,
			[],
			global_position
		)

# ------------------------------------------------------------------------------
# Body detection callbacks
# ------------------------------------------------------------------------------

# Set the proximity flag when the player enters talking range.
# is_in_group check prevents other physics bodies from being treated as the player.
func _on_body_entered(body):
	if body.is_in_group("player"):
		_player_in_range = true

# Clear the flag when the player walks away.
func _on_body_exited(body):
	if body.is_in_group("player"):
		_player_in_range = false
