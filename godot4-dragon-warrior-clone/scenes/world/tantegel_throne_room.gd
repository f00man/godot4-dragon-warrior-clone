# ==============================================================================
# tantegel_throne_room.gd
# Part of: godot4-dragon-warrior-clone
# Description: Root script for the Tantegel Castle throne room — the opening
#              scene of the game. King Lorik delivers his intro speech on first
#              visit, then the player can speak to all NPCs in the room and
#              descend via the south staircase. Encounters are disabled (rate 0).
# Attached to: Node2D (TantegelThroneRoom) in scenes/world/tantegel_throne_room.tscn
# ==============================================================================

extends Node2D

# ------------------------------------------------------------------------------
# Dialogue Content — King Lorik's opening monologue
# ------------------------------------------------------------------------------

# The full 7-page intro speech delivered by King Lorik on the player's first
# visit. Each string is one screen of the DialogueBox. The pages follow the
# original Dragon Warrior NES script closely for authenticity.
# Stored as a constant so it cannot be accidentally modified at runtime and
# any other system that needs to reference this speech can use the same array.
const KING_LORIK_INTRO_PAGES = [
	"Descendant of Erdrick, I am King Lorik the 16th. Long have we awaited thy coming.",
	"Darkness hath fallen upon our land. The Dragonlord hath stolen the precious Ball of Light, and all of Alefgard now lies shrouded in shadow.",
	"Monsters roam the fields and roads unchecked. The people live in fear and despair.",
	"Worse still, our beloved Princess Gwaelin hath been abducted by the Dragonlord's servants. We have been unable to discover her whereabouts.",
	"Thou art the only hope for this kingdom. As a descendant of the great hero Erdrick, only thou hast the power to challenge the Dragonlord and recover the Ball of Light.",
	"Before thou departest, I urge thee to speak with mine chancellor and the royal guards. They shall provide counsel for the journey ahead.",
	"Go now, brave warrior. The fate of all Alefgard rests upon thy shoulders."
]

# ------------------------------------------------------------------------------
# Node References
# ------------------------------------------------------------------------------

# Direct reference to the Player CharacterBody2D. Collision layers are set
# here in _ready() rather than in the .tscn so the intent is documented in code.
@onready var player = $Player

# The EncounterManager child node. Its base_encounter_rate is set to 0.0 in
# the .tscn, but we assert that explicitly here in _ready() as a safety net —
# no random battles should ever trigger inside the throne room.
@onready var encounter_manager = $EncounterManager

# The reusable DialogueBox instance living inside the CanvasLayer. We hold a
# reference so we can connect dialogue_closed after the intro fires without
# risking connecting the EventManager.dialogue_requested signal a second time
# (DialogueBox already wires that itself in its own _ready()).
@onready var dialogue_box = $DialogueLayer/DialogueBox

# Reference to King Lorik's NPC node. Used to pass his global_position to the
# DialogueBox so it positions the panel near him rather than falling back to
# the default bottom bar.
@onready var king_lorik = $NPC_KingLorik

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Resume playtime — the player now has control. Each scene is responsible
	# for this call so GameState.playtime correctly reflects time in-world.
	GameState.resume_playtime()

	# Enable physics collision so the player stops at wall shapes painted in
	# the .tscn. Layer 1 matches the tileset physics layer; mask 1 means the
	# player detects layer-1 bodies (walls, other players, NPCs with layer=1).
	player.collision_layer = 1
	player.collision_mask = 1

	# Belt-and-suspenders: make absolutely sure encounters cannot fire inside
	# the throne room even if the .tscn export value is somehow changed.
	encounter_manager.base_encounter_rate = 0.0

	# Only play the intro on the very first visit. The world flag
	# "king_lorik_intro_done" is set inside _on_king_intro_closed() once the
	# player has read through all seven pages. Subsequent visits skip straight
	# to the scene-event check below.
	if not GameState.has_flag("king_lorik_intro_done"):
		# A short delay before speaking lets the scene fully finish loading
		# and the fade-in transition to settle, so the dialogue box does not
		# appear on the very first rendered frame. 0.3 seconds matches the
		# feel of the original NES title which had a brief pause before text.
		await get_tree().create_timer(0.3).timeout
		_trigger_king_intro()

	# Check for any non-intro events that should fire on entry. This covers
	# quest updates, story beats, etc. defined in data/events/ JSON files.
	# The call is safe even when the intro is playing — check_events_for_scene
	# only fires one event and the intro is not a JSON event, so there is no
	# overlap.
	EventManager.check_events_for_scene("tantegel_throne_room")

# ------------------------------------------------------------------------------
# Private: Intro Trigger
# ------------------------------------------------------------------------------

# Fires the opening King Lorik monologue through the shared dialogue system.
# We emit dialogue_requested directly on EventManager (the same approach used
# by npc_dialogue.gd) so the active DialogueBox receives it via its own
# _on_event_dialogue_requested() handler — no second connection needed.
# After emitting, we connect dialogue_closed to our completion handler so we
# know when the player has finished reading and can set the done flag.
func _trigger_king_intro():
	# Emit the signal using the EventManager autoload directly. This is the
	# project-standard way for scripts to request dialogue without holding a
	# reference to the DialogueBox node itself (keeping scene hierarchy decoupled).
	# Arguments match EventManager.dialogue_requested:
	#   speaker   — label shown in the dialogue panel header
	#   pages     — the full 7-page array defined above
	#   choices   — empty array (no branching choices in the intro speech)
	#   world_pos — king_lorik.global_position so the panel appears near his sprite
	EventManager.emit_signal("dialogue_requested", "King Lorik", KING_LORIK_INTRO_PAGES, [], king_lorik.global_position)

	# Connect dialogue_closed so we can mark the intro as complete once the
	# player has read through all pages. We check is_connected() first to be
	# safe against hot-reload or any future code path that might call this
	# function more than once in the same session.
	if not dialogue_box.dialogue_closed.is_connected(_on_king_intro_closed):
		dialogue_box.dialogue_closed.connect(_on_king_intro_closed)

# ------------------------------------------------------------------------------
# Signal Handlers
# ------------------------------------------------------------------------------

# Called by DialogueBox when the last page of the intro is dismissed.
# Sets the world flag so the intro never plays again, then removes the one-time
# connection we added in _trigger_king_intro(). The NPC_KingLorik node still
# has its own dialogue_pages for subsequent visits — this only governs the
# seven-page opening monologue.
func _on_king_intro_closed():
	# Record that the intro has been completed. GameState.set_flag() writes to
	# world_flags and emits world_flag_changed so SaveManager can persist it.
	GameState.set_flag("king_lorik_intro_done", true)

	# Remove our one-shot connection so future DialogueBox close events
	# (triggered by speaking to any other NPC in the room) do not re-fire
	# this handler. is_connected() guards against a double-disconnect if the
	# signal was already cleaned up by some other code path.
	if dialogue_box.dialogue_closed.is_connected(_on_king_intro_closed):
		dialogue_box.dialogue_closed.disconnect(_on_king_intro_closed)
