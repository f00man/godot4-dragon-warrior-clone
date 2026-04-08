# ==============================================================================
# hud.gd
# Part of: godot4-dragon-warrior-clone
# Description: Overworld HUD that displays the lead party member's name, HP,
#              MP, and the player's current gold. Reads from GameState only —
#              never writes to it. Updates via signal connections and per-frame
#              polling to catch HP/MP mutations that bypass signals.
# Attached to: HUD (Control root node of hud.tscn)
# ==============================================================================

extends Control

# ------------------------------------------------------------------------------
# Node references — populated automatically by @onready on scene load.
# All four display labels live inside Panel > VBoxContainer.
# ------------------------------------------------------------------------------

@onready var label_name = $Panel/VBoxContainer/LabelName
@onready var label_hp   = $Panel/VBoxContainer/LabelHP
@onready var label_mp   = $Panel/VBoxContainer/LabelMP
@onready var label_gold = $Panel/VBoxContainer/LabelGold

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Connect to GameState signals so the HUD refreshes whenever gold or the
	# party roster changes (member added, removed, or reordered).
	GameState.gold_changed.connect(_on_gold_changed)
	GameState.party_changed.connect(_on_party_changed)

	# Populate immediately so there are no blank labels on the first frame.
	_refresh()

func _process(_delta):
	# HP and MP values are mutated directly on PartyMemberData during battle
	# without emitting a signal. Poll every frame so the HUD stays accurate.
	# This is intentionally lightweight — just four label assignments.
	_refresh()

# ------------------------------------------------------------------------------
# Signal handlers
# ------------------------------------------------------------------------------

# Called when GameState emits gold_changed. The new_amount parameter is
# ignored here because _refresh() reads gold directly — this keeps the
# refresh logic in a single place.
func _on_gold_changed(_new_amount):
	_refresh()

# Called when GameState emits party_changed (member added, removed, reordered).
func _on_party_changed():
	_refresh()

# ------------------------------------------------------------------------------
# Display helpers
# ------------------------------------------------------------------------------

# Reads all four data points from GameState and writes them to the labels.
# Safe to call at any time, including before the party is populated.
func _refresh():
	var party = GameState.party

	if party.is_empty():
		# Party is empty — show placeholder dashes so the HUD never crashes
		# and the player sees something meaningful rather than blank labels.
		label_name.text = "---"
		label_hp.text   = "HP    --- / ---"
		label_mp.text   = "MP    --- / ---"
	else:
		# Read from the lead party member (index 0 is always the party leader).
		var leader = party[0]
		label_name.text = leader.member_name
		label_hp.text   = "HP    %d / %d" % [leader.current_hp, leader.max_hp]
		label_mp.text   = "MP    %d / %d" % [leader.current_mp, leader.max_mp]

	# Gold is independent of the party — always display it.
	label_gold.text = "Gold  %d G" % GameState.gold
