# ==============================================================================
# tantegel_floor2.gd
# Part of: godot4-dragon-warrior-clone
# Description: Root script for Tantegel Castle Floor 2 (upper hall). This floor
#              connects the throne room above to Floor 1 below via staircases on
#              the north and south walls. A sage and three guards occupy the hall.
#              Encounters are disabled — the castle is always safe.
# Attached to: Node2D (TantegelFloor2) in scenes/world/tantegel_floor2.tscn
# ==============================================================================

extends Node2D

# ------------------------------------------------------------------------------
# Node References
# ------------------------------------------------------------------------------

# Direct reference to the Player CharacterBody2D. Collision layers are set
# explicitly in _ready() so the intent is documented in code rather than
# buried in Inspector properties.
@onready var player = $Player

# The EncounterManager child node. Rate is already 0.0 in the .tscn export,
# but we enforce it here as a safety net so no battle can ever fire inside
# the castle regardless of what value a designer might accidentally set.
@onready var encounter_manager = $EncounterManager

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Resume playtime tracking — the player now has control. Every world scene
	# is responsible for this call so GameState.playtime correctly reflects the
	# total time the player has spent in the game world.
	GameState.resume_playtime()

	# Enable physics collision so the player stops at the wall shapes defined
	# in the .tscn. Layer 1 matches the physics layer used by all static walls;
	# mask 1 means the player detects and is stopped by layer-1 bodies.
	player.collision_layer = 1
	player.collision_mask = 1

	# Belt-and-suspenders: force encounter rate to zero regardless of .tscn value.
	# No random battles should fire anywhere inside Tantegel Castle.
	encounter_manager.base_encounter_rate = 0.0

	# Fire any JSON-defined events that should trigger on entry to this floor.
	# This covers quest updates or story beats keyed to "tantegel_floor2" scene id.
	EventManager.check_events_for_scene("tantegel_floor2")
