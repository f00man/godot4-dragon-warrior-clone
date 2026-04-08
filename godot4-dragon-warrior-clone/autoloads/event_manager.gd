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

# Emitted when an event or NPC wants to display dialogue through the active
# DialogueBox. Any DialogueBox in the current scene connects to this in _ready().
# speaker   — String name shown in the speaker label (pass "" to hide it).
# pages     — Array of Strings, one entry per dialogue screen.
# choices   — Array of Strings shown as buttons after the last page (may be empty).
# world_pos — Vector2 global position of the speaking entity in world coordinates.
#             Pass null for events with no spatial anchor (box defaults to bottom).
signal dialogue_requested(speaker, pages, choices, world_pos)

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

# Holds the event dict that is currently waiting for a player choice.
# Set by trigger_event() before emitting dialogue_requested. Cleared after
# submit_choice() processes the selection. Only one event can be pending at
# a time — check_events_for_scene() enforces this by firing at most one
# event per scene load.
var _pending_event = null

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
# Public API
# ------------------------------------------------------------------------------

# Scans all loaded events and triggers the first one whose conditions are met
# for the given scene_id. Called by SceneManager (or the scene itself) after a
# scene finishes loading.
#
# Only one event is triggered per call — the first match wins and the loop
# breaks immediately. This prevents multiple events from stacking on top of
# each other when several conditions happen to be satisfied at once. If a
# queue-based approach is needed later (fire all pending events in sequence),
# replace the break with an event queue and a dequeue-on-completion pattern.
#
# Callers: SceneManager after a transition (SC2), or scene _ready() hooks.
func check_events_for_scene(scene_id):
	for event in _events.values():
		# Skip events that have already been completed. is_event_completed()
		# reads the "event_<id>_done" world flag set by apply_outcome().
		if is_event_completed(event["id"]):
			continue

		# Build the condition dict from the event's "trigger" key, then inject
		# the current scene_id so evaluate_condition() can do a scene check.
		# Events without a "trigger" key get an empty dict, which fires
		# unconditionally — useful for tutorial prompts and story beats.
		var condition = event.get("trigger", {})

		# Merge scene_id into a copy of the condition so we don't permanently
		# mutate the loaded event data. evaluate_condition() uses "scene_id" as
		# the key for the substring scene path check.
		var condition_with_scene = condition.duplicate()
		condition_with_scene["scene_id"] = scene_id

		if evaluate_condition(condition_with_scene):
			# Conditions met — present this event to the player, then stop.
			# Firing at most one event per scene load keeps the UX manageable.
			trigger_event(event)
			break

# Presents an event to the player by emitting dialogue_requested and storing
# the event as _pending_event so submit_choice() can apply the outcome later.
#
# The active scene is responsible for wiring DialogueBox.choice_made to
# EventManager.submit_choice. EventManager is an autoload and cannot hold a
# direct reference to a scene-level node, so the connection is the scene's job.
#
# `event` is the full event dictionary as loaded from disk (one entry from _events).
func trigger_event(event):
	# Announce that an event is starting so the dialogue UI can open/prepare.
	emit_signal("event_started", event["id"])

	# Build the list of choice labels to display as buttons in the dialogue UI.
	# Each choice dict has at minimum a "text" field. We extract just the text
	# here — the full choice dict (including outcomes) stays in _pending_event
	# for submit_choice() to read when the player picks an option.
	var choice_texts = []
	for choice in event.get("choices", []):
		choice_texts.append(choice.get("text", "???"))

	# Use the event's "title" as the speaker label if one is provided.
	# Fall back to the event id so the dialogue box always has something to show.
	var speaker = event.get("title", event["id"])

	# Wrap the description into a single-page array. The dialogue system expects
	# an array of strings so it can handle multi-page conversations uniformly.
	# An event without a "description" key gets a generic placeholder.
	var pages = [event.get("description", "...")]

	# Store the event so submit_choice() can look up the chosen outcome.
	# This must be set BEFORE emitting dialogue_requested in case the DialogueBox
	# immediately calls back (unlikely but possible on same-frame connections).
	_pending_event = event

	# Ask the active DialogueBox to display this event's text and choice buttons.
	# Events fired from JSON have no spatial anchor, so world_pos is null — the
	# DialogueBox will fall back to its default bottom placement.
	emit_signal("dialogue_requested", speaker, pages, choice_texts, null)

# Called by the active scene when the player selects a choice from the dialogue UI.
# `choice_index` is the zero-based index into the event's "choices" array.
#
# Scene responsibility: connect DialogueBox.choice_made to this function.
# Example (in the scene's _ready):
#   $DialogueBox.choice_made.connect(EventManager.submit_choice)
func submit_choice(choice_index):
	# Guard against submit_choice being called when no event is pending.
	# This could happen if a stale connection fires after an event is complete.
	if _pending_event == null:
		push_warning("EventManager.submit_choice: called with no pending event — ignoring.")
		return

	var choices = _pending_event.get("choices", [])

	# Guard against an out-of-range index. choice_index should always be valid
	# if the dialogue UI was built from the same choices array, but defensive
	# checks here prevent a silent bad state if the UI and data get out of sync.
	if choice_index < 0 or choice_index >= choices.size():
		push_warning("EventManager.submit_choice: choice_index %d out of range (have %d choices)" % [choice_index, choices.size()])
		return

	var event_id = _pending_event["id"]
	var chosen_outcomes = choices[choice_index].get("outcomes", {})

	# Apply every outcome from the selected choice, passing the event_id so
	# apply_outcome() can construct the completion flag key ("event_<id>_done").
	apply_outcome(chosen_outcomes, event_id)

	# Clear the pending event now that the choice has been fully processed.
	# This prevents submit_choice() from firing again if the signal fires twice.
	_pending_event = null

# Returns true if the event has already been resolved and should not fire again.
#
# Convention: an event with id "bandit_camp_choice" is considered complete when
# GameState.world_flags["event_bandit_camp_choice_done"] == true. This pattern
# means every event implicitly owns one flag in the form "event_<id>_done",
# which apply_outcome() sets automatically when the "set_completion_flag" key
# is present in the chosen outcome (or always, via the unconditional emit at
# the end of apply_outcome).
#
# Checking this flag rather than a separate completed-events list keeps the
# completion state part of the normal world_flags save data, so SaveManager
# doesn't need special handling for it.
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
#   "scene_id"      — substring of the scene path; only passes in matching scenes
#
# Returns true only if ALL present conditions are satisfied.
# An empty condition dictionary means the event is unconditional and always fires.
func evaluate_condition(condition):
	# An empty trigger dict means no conditions are required — always fire.
	# This lets event authors omit the "trigger" key entirely for unconditional events.
	if condition.is_empty():
		return true

	# --- flag_required check ---
	# The named flag must both exist in world_flags AND hold a truthy value.
	# A flag set to false, 0, or "" is treated the same as absent — the event
	# should not fire until the flag is genuinely "on".
	# GameState.has_flag() already combines the existence + truthiness check,
	# but we also call get_flag() explicitly so the truthiness test is visible
	# here and does not rely on the internal behaviour of has_flag().
	if condition.has("flag_required"):
		# First confirm the flag exists and is truthy via the GameState helper
		if not GameState.has_flag(condition["flag_required"]):
			return false
		# Double-check the raw value in case has_flag() ever diverges from
		# our intent — reject false, 0, and empty string as "not set"
		var flag_val = GameState.get_flag(condition["flag_required"])
		if flag_val == false or flag_val == 0 or flag_val == "":
			return false

	# --- flag_not check ---
	# The named flag must be absent OR hold a falsy value.
	# This is the standard "event not yet resolved" guard — e.g. "flag_not":
	# "event_bandit_camp_choice_done" means the event fires only before the
	# player has completed it.
	if condition.has("flag_not"):
		if GameState.has_flag(condition["flag_not"]):
			# Flag exists; check whether it is actually truthy before blocking.
			# A flag stored as false or 0 should not suppress the event.
			var blocking_val = GameState.get_flag(condition["flag_not"])
			if blocking_val != false and blocking_val != 0 and blocking_val != "":
				return false

	# --- scene_id check ---
	# current_scene holds the full resource path, e.g.
	# "res://scenes/world/overworld.tscn". A substring match lets event
	# authors write a short id like "overworld" instead of the full path,
	# making event JSON portable if the file is ever moved within the project.
	if condition.has("scene_id"):
		if not GameState.current_scene.contains(condition["scene_id"]):
			return false

	# All present conditions passed — this event is eligible to fire
	return true

# Shows dialogue through whichever DialogueBox is active in the current scene.
# Caller passes a speaker name, a single text string (wrapped here into a
# one-page array), and an optional choices array.  EventManager emits the
# dialogue_requested signal; the DialogueBox in the scene listens and displays it.
#
# NPC scripts and other scene objects call this to trigger dialogue without
# needing a direct reference to the DialogueBox node. This keeps scene objects
# decoupled from the UI hierarchy — they only need the EventManager autoload,
# which is always in scope.
#
# speaker   — Name shown in the header label (pass "" for narrator-style lines).
# text      — The dialogue text. Passed as a single string; wrapped into [text]
#              so DialogueBox treats it as a one-page sequence.
# choices   — Optional Array of choice strings shown as buttons after the text.
# world_pos — Optional Vector2 global position of the speaking entity in world
#              coordinates. The DialogueBox uses this to place the panel near
#              the speaker. Pass null (default) to use the bottom-bar fallback.
func request_dialogue(speaker, text, choices = [], world_pos = null):
	emit_signal("dialogue_requested", speaker, [text], choices, world_pos)

# Applies the outcome dictionary from a player's event choice to GameState.
# Called by submit_choice() with the outcomes dict from the selected choice
# and the event_id so the completion flag can be keyed correctly.
#
# Handles these outcome keys (all optional — missing keys are silently skipped):
#
#   "set_flag"            String — the flag key to set to true.
#                                  Marks a world change caused by this choice.
#                                  Example: "resolved_bandit_camp"
#
#   "set_flag_2"          String — a second flag key to set to true in the same
#                                  outcome. Allows two independent flags to be set
#                                  without needing a nested array. Typically used
#                                  when a choice has two consequences (e.g. the
#                                  camp is resolved AND bandits become allies).
#                                  Example: "bandits_allied"
#
#   "town_loyalty_delta"  Dict   — maps town_id (String) to a signed integer delta.
#                                  Positive values increase loyalty; negative decrease.
#                                  Example: { "riverkeep": 15 }
#
#   "add_item"            Dict   — shaped { "item_id": String, "quantity": int }.
#                                  Adds the item to the player's inventory.
#
#   "add_party_member"    String — the member_id whose .tres resource to load from
#                                  res://resources/party_members/<id>.tres, then add.
#
#   "remove_party_member" String — the member_name string to look up in the current
#                                  party. Searches party for a matching member_name
#                                  field and passes the resource to GameState.
#
#   "set_completion_flag" bool   — when true, marks this event as done by setting
#                                  "event_<event_id>_done" = true in world_flags.
#                                  This causes is_event_completed() to return true
#                                  for this event from now on.
#
# After processing all keys, emits event_completed(event_id) so the dialogue UI
# can close and any listening systems can react to the event being resolved.
func apply_outcome(outcome, event_id):
	# --- set_flag ---
	# Set the named world flag to true. This is the primary way events record
	# that something happened in the world (e.g. a camp was attacked, a quest started).
	if outcome.has("set_flag"):
		# Flag meaning: records the primary consequence of this event choice.
		GameState.set_flag(outcome["set_flag"], true)

	# --- set_flag_2 ---
	# A second optional flag. Used when one choice causes two distinct world changes.
	# For example, choosing to negotiate both "resolved_bandit_camp" (shared with
	# all choices) and "bandits_allied" (unique to the negotiation path).
	if outcome.has("set_flag_2"):
		# Flag meaning: records a secondary or choice-specific world consequence.
		GameState.set_flag(outcome["set_flag_2"], true)

	# --- town_loyalty_delta ---
	# Adjust the loyalty of one or more towns. The value is a dict mapping each
	# affected town_id to the signed integer change. GameState.modify_town_loyalty()
	# clamps the result to 0–100 automatically.
	if outcome.has("town_loyalty_delta"):
		for town_id in outcome["town_loyalty_delta"]:
			var delta = outcome["town_loyalty_delta"][town_id]
			# Adjust loyalty for this town. Positive delta rewards player-friendly
			# choices; negative delta reflects player actions that harm the town.
			GameState.modify_town_loyalty(town_id, delta)

	# --- add_item ---
	# Give the player an item. The value must be a dict with "item_id" and
	# "quantity" fields. Missing sub-fields are guarded below.
	if outcome.has("add_item"):
		var item_data = outcome["add_item"]
		if item_data.has("item_id") and item_data.has("quantity"):
			GameState.add_item(item_data["item_id"], item_data["quantity"])
		else:
			push_warning("EventManager.apply_outcome: 'add_item' outcome is missing 'item_id' or 'quantity' in event '%s'" % event_id)

	# --- add_party_member ---
	# Load a PartyMemberData .tres resource by id and add it to the party.
	# The resource must exist at res://resources/party_members/<id>.tres.
	if outcome.has("add_party_member"):
		var member_id = outcome["add_party_member"]
		var resource_path = "res://resources/party_members/%s.tres" % member_id
		var member_resource = load(resource_path)
		if member_resource == null:
			push_warning("EventManager.apply_outcome: could not load party member resource at '%s'" % resource_path)
		else:
			# Add the loaded resource to the party via GameState so party_changed fires.
			GameState.add_party_member(member_resource)

	# --- remove_party_member ---
	# Find a party member by their member_name string and remove them.
	# GameState.remove_party_member() takes a resource reference, not a name string,
	# so we scan the party array to find the matching resource first.
	if outcome.has("remove_party_member"):
		var target_name = outcome["remove_party_member"]
		var found_member = null
		for member in GameState.get_party():
			# member_name is the display name field on PartyMemberData (see R1).
			if member.member_name == target_name:
				found_member = member
				break
		if found_member == null:
			push_warning("EventManager.apply_outcome: could not find party member named '%s' to remove (event '%s')" % [target_name, event_id])
		else:
			# Remove by resource reference — GameState uses party.find() internally.
			GameState.remove_party_member(found_member)

	# --- set_completion_flag ---
	# Mark this specific event as permanently done. Future calls to
	# is_event_completed() will return true and check_events_for_scene()
	# will skip it. The flag key follows the convention "event_<id>_done"
	# so it lives in world_flags alongside all other state and is saved
	# automatically by SaveManager without any special handling.
	if outcome.get("set_completion_flag", false):
		# Flag meaning: this event has been resolved; do not present it again.
		GameState.set_flag("event_%s_done" % event_id, true)

	# Signal that all outcomes have been applied and the event is fully resolved.
	# The active dialogue UI connects to this to know when it can close itself.
	emit_signal("event_completed", event_id)
