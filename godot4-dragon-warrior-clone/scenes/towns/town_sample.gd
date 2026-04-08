# ==============================================================================
# town_sample.gd
# Part of: godot4-dragon-warrior-clone
# Description: Root script for the sample town scene. Resumes playtime on entry,
#              wires the south exit trigger, and provides the hook point for
#              future town-specific event checks.
# Attached to: Node2D (TownSample) in scenes/towns/town_sample.tscn
# ==============================================================================

extends Node2D

# ------------------------------------------------------------------------------
# Node References
# ------------------------------------------------------------------------------

# Direct reference to the Player node in this scene.
# Used for signal connections such as the overworld exit trigger.
@onready var player = $Player

# Reference to the DialogueBox UI node instanced at the bottom of this scene.
# The DialogueBox connects itself to EventManager.dialogue_requested in its own
# _ready() (via _on_event_dialogue_requested). We do NOT connect it again here.
# Connecting it a second time — even to a different callable — would result in
# EventManager.dialogue_requested firing twice per event: once through the
# DialogueBox internal handler and once through any additional connection made
# here. The is_connected() guard in the old code did not protect against this
# because it tested for show_dialogue while DialogueBox had already connected
# _on_event_dialogue_requested — two distinct callables on the same signal.
# The DialogueBox is fully self-wiring; town scenes should never add a second
# connection to EventManager.dialogue_requested.
@onready var dialogue_box = $DialogueBox

# The Area2D placed at the south edge of the town. When the player walks over
# it, body_entered fires and we transition back to the overworld.
@onready var overworld_exit = $OverworldExit

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Resume playtime when the player enters the town. Playtime tracking is
	# managed by GameState; each scene is responsible for resuming it in _ready()
	# and pausing it (if needed) on exit or when menus open.
	GameState.resume_playtime()

	# Force the player to a fixed town spawn tile by setting the node directly.
	# We do NOT call GameState.set_location() here — that would overwrite the
	# overworld tile position stored in GameState. When the player exits the town
	# via transition_back(), player.gd._ready() reads GameState.player_position
	# to restore the overworld spawn, so that value must stay intact.
	# SceneManager.transition_to() already updates GameState.current_scene, so
	# there is nothing else to write here.
	var TOWN_SPAWN = Vector2(5, 5)
	player.tile_position = TOWN_SPAWN
	player.position = TOWN_SPAWN * 32

	# Wire the south exit so the player can leave the town and return to the
	# overworld. The handler checks that the body is the player before acting.
	overworld_exit.body_entered.connect(_on_overworld_exit_body_entered)

	# Check for any scene-entry events that should fire when the player arrives
	# in this town (e.g. a quest trigger, an elder greeting cutscene, etc.).
	# EventManager.check_events_for_scene() is a stub for now — see TODO E3
	# in CLAUDE.md. When implemented it will fire any events whose trigger
	# conditions include scene_id = "town_sample".
	EventManager.check_events_for_scene("town_sample")

# ------------------------------------------------------------------------------
# Exit Handling
# ------------------------------------------------------------------------------

# Return to the overworld when the player walks over the exit tile.
# We check is_in_group("player") so NPCs or other physics bodies that happen to
# overlap the exit zone do not accidentally trigger a scene transition.
func _on_overworld_exit_body_entered(body):
	if body.is_in_group("player"):
		SceneManager.transition_back()
