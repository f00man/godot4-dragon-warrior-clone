# ==============================================================================
# event_manager.gd
# Part of: godot4-dragon-warrior-clone
# Description: Loads and manages dynamic events defined in data/events/ JSON
#              files. Checks trigger conditions against GameState.world_flags
#              and applies outcomes (setting flags, adjusting town loyalty, etc.)
# Attached to: Autoload (EventManager)
# ==============================================================================

extends Node

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------

# Emitted when an event is about to be presented to the player.
# Listeners (e.g. the dialogue UI) can use this to prepare the display.
signal event_started(event_id)

# Emitted after the player makes a choice and all outcomes have been applied.
# Listeners can use this to dismiss the dialogue UI or trigger a scene change.
signal event_completed(event_id)

# ------------------------------------------------------------------------------
# Private Data
# ------------------------------------------------------------------------------

# Dictionary that holds all loaded event definitions, keyed by event id.
# Structure mirrors the JSON schema defined in data/events/*.json:
#   {
#     "id":          String           — unique event identifier
#     "trigger":     Dictionary       — conditions required to fire this event
#     "description": String           — narrative text shown to the player
#     "choices":     Array            — list of choice dictionaries the player picks from
#   }
# Populated in _ready() from disk. Never modified at runtime.
var _events = {}

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Load all event JSON files from the events data directory into _events.
	# This runs once at startup so every other system can immediately ask
	# "is event X triggerable?" without doing any disk I/O.
	_load_all_events()

# ------------------------------------------------------------------------------
# Private: Event Loading
# ------------------------------------------------------------------------------

# Scans res://data/events/ for .json files, parses each one, and stores the
# resulting dictionary in _events keyed by the event's "id" field.
# Prints a warning and returns early if the directory doesn't exist — this
# is expected during early development when no events have been authored yet.
func _load_all_events():
	var dir_path = "res://data/events/"

	# Verify the directory exists before trying to open it.
	# DirAccess.open() returns null if the path is missing or inaccessible.
	var dir = DirAccess.open(dir_path)
	if dir == null:
		push_warning("EventManager: data/events/ directory not found — no events loaded. Create the directory and add .json files to define events.")
		return

	# Begin iterating over the contents of the directory.
	# include_navigational = false skips the "." and ".." entries.
	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		# Only process files that end in .json — ignore subdirectories and
		# any other file types that might end up in this folder.
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			_load_event_file(dir_path + file_name)

		# Advance to the next entry in the directory listing
		file_name = dir.get_next()

	# Always close the directory iterator when done to release the handle
	dir.list_dir_end()

	print("EventManager: loaded %d event(s) from data/events/" % _events.size())

# Opens a single JSON file at `file_path`, parses it, and registers the event
# in _events. Skips the file with a warning if parsing fails or if the "id"
# field is missing — a bad file should not crash the whole game.
func _load_event_file(file_path):
	# Open the file for reading. FileAccess.open() returns null on failure.
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("EventManager: could not open event file: %s" % file_path)
		return

	# Read the entire file contents as a string and close the handle immediately
	var raw_text = file.get_as_text()
	file.close()

	# Parse the JSON string into a GDScript Dictionary
	var data = JSON.parse_string(raw_text)
	if data == null:
		push_warning("EventManager: failed to parse JSON in file: %s" % file_path)
		return

	# Every event file must have an "id" field — without it we have no key to
	# store it under, and no way for other systems to reference it.
	if not data.has("id"):
		push_warning("EventManager: event file is missing required 'id' field: %s" % file_path)
		return

	# Store the parsed event dictionary, keyed by its id string.
	# If two files share an id, the later one silently wins — file authors
	# must ensure ids are unique across all files in data/events/.
	_events[data["id"]] = data

# ------------------------------------------------------------------------------
# Public API — Stubbed Functions
# ------------------------------------------------------------------------------

# Scans all loaded events and triggers any whose conditions are met for the
# given scene_id. Called by SceneManager (or the scene itself) after a scene
# finishes loading.
#
# When fully implemented this will:
#   1. Iterate over every entry in _events.
#   2. For each event, call evaluate_condition(event["trigger"]) with the
#      scene_id injected into the condition dict.
#   3. Also check is_event_completed(event["id"]) to skip already-done events.
#   4. Call trigger_event(event["id"]) for every event whose conditions pass.
#
# Callers: SceneManager after a transition, or scene _ready() hooks.
#
# TODO: implement the iteration and condition-check loop
func check_events_for_scene(scene_id):
	# Stub — no behaviour yet. Will iterate _events and call trigger_event()
	# for any event whose trigger.scene_id matches and whose conditions pass.
	pass

# Presents the named event to the player.
#
# When fully implemented this will:
#   1. Look up event_id in _events; warn and return if not found.
#   2. Emit event_started(event_id) so the dialogue UI can open.
#   3. Display the event's "description" text via the dialogue system.
#   4. Present the event's "choices" array as a list of selectable options.
#      Choices that have a "requires_flag" field are hidden if the player
#      doesn't have that flag set in GameState.world_flags.
#   5. Await the player's selection (yield/await on a dialogue signal).
#   6. Call apply_outcome(chosen_choice["outcomes"]) with the selected choice.
#   7. Emit event_completed(event_id) so the UI can close.
#
# TODO: implement dialogue UI integration and choice presentation
func trigger_event(event_id):
	# Stub — no behaviour yet. Will drive the dialogue box and present choices.
	pass

# Returns true if the event has already been resolved and should not fire again.
#
# Convention: an event with id "bandit_camp_choice" is considered complete when
# GameState.world_flags["event_bandit_camp_choice_done"] == true. This pattern
# means every event implicitly owns one flag in the form "event_<id>_done",
# which apply_outcome() sets automatically when any choice is made.
#
# Checking this flag rather than a separate completed-events list keeps the
# completion state part of the normal world_flags save data, so SaveManager
# doesn't need special handling for it.
#
# TODO: no additional implementation needed — the logic is correct as written
#       once apply_outcome() reliably sets the completion flag.
func is_event_completed(event_id):
	# Build the completion flag key from the event id, then ask GameState.
	# Returns false for any event that hasn't been resolved or doesn't exist.
	var completion_flag = "event_%s_done" % event_id
	return GameState.has_flag(completion_flag)

# Evaluates a trigger condition dictionary against the current GameState.
#
# Expected keys in `condition` (all optional — absent keys are ignored):
#   "flag_required" — a world_flag key that must exist and be truthy
#   "flag_not"      — a world_flag key that must be absent or falsy
#   "scene_id"      — if present, the condition only passes in this scene
#
# Returns true only if ALL present conditions are satisfied.
#
# Currently returns true unconditionally so that events are never silently
# suppressed during early development and testing. The real evaluation logic
# will be added once the event data schema is finalised.
#
# TODO: implement flag_required, flag_not, and scene_id checks against
#       GameState.has_flag() and the scene_id parameter passed from
#       check_events_for_scene()
func evaluate_condition(condition):
	# Stub — returns true so no event is silently filtered out during testing.
	# Replace this with real condition evaluation before shipping.
	return true

# Applies the outcome dictionary from a player's event choice to GameState.
#
# Handles these outcome keys (all optional — missing keys are silently skipped):
#   "set_flag"             String  — calls GameState.set_flag(value, true)
#   "set_flag_2"           String  — same as set_flag; allows two flags in one outcome
#   "set_completion_flag"  bool    — when true, sets the event's own completion flag
#                                    ("event_<event_id>_done") so is_event_completed()
#                                    returns true from now on. The event_id must be
#                                    passed in alongside the outcome (see TODO below).
#   "town_loyalty_delta"   Dict    — maps town_id → int delta; calls
#                                    GameState.modify_town_loyalty(town_id, delta)
#                                    for each entry
#   "add_item"             Dict    — shaped { "item_id": String, "quantity": int };
#                                    calls GameState.add_item()
#   "add_party_member"     String  — member_id; calls GameState.add_party_member()
#   "remove_party_member"  String  — member_id; calls GameState.remove_party_member()
#
# Note: "set_completion_flag" requires the event_id context to construct the
# flag key ("event_<id>_done"). trigger_event() will need to pass this along
# when it calls apply_outcome(). A simple approach is to merge the event_id
# into the outcome dict before calling this function.
#
# TODO: implement each outcome key handler using the GameState accessors above
# TODO: have trigger_event() inject the event_id into the outcome dict so the
#       completion flag can be set correctly
func apply_outcome(outcome):
	# Stub — no behaviour yet. Will dispatch to GameState accessors based on
	# which keys are present in the outcome dictionary.
	pass
