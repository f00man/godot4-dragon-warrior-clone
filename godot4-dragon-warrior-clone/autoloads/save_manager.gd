# ==============================================================================
# save_manager.gd
# Part of: godot4-dragon-warrior-clone
# Description: Handles saving and loading game state to/from JSON files.
#              Supports 3 save slots with atomic writes, version tracking,
#              migration stubs, and safe defaults on load so missing fields
#              never crash the game.
# Attached to: Autoload (SaveManager)
# ==============================================================================

extends Node

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------

# Number of save slots available to the player (0, 1, 2)
const SLOT_COUNT = 3

# Base filename template. %d is replaced with the slot number (0–2).
const SAVE_FILE_TEMPLATE = "user://save_slot_%d.json"

# Temp file used for atomic writes. We write here first, then rename to the
# real path so a crash mid-write never corrupts an existing save.
const TEMP_FILE_PATH = "user://save_slot_temp.json"

# ------------------------------------------------------------------------------
# save_game
# ------------------------------------------------------------------------------

# Serializes the current GameState to a JSON file in the given slot.
# Returns true on success, false if the save was blocked (e.g. mid-battle)
# or if a file write error occurred.
#
# Safety rules enforced here:
#   1. Never save while in_battle — the transient battle state can't be restored cleanly.
#   2. Atomic write — write to a temp file, then rename, so a crash can't corrupt the slot.
func save_game(slot):
	# Validate slot range before touching the filesystem
	if slot < 0 or slot >= SLOT_COUNT:
		push_error("SaveManager.save_game: invalid slot %d (must be 0–%d)" % [slot, SLOT_COUNT - 1])
		return false

	# Block saving during battle — mid-combat state is not safe to serialize
	if GameState.in_battle:
		push_warning("SaveManager.save_game: save blocked — player is in battle")
		return false

	# Build the save dictionary from current GameState
	var data = _serialize_game_state(slot)

	# Convert to formatted JSON for human-readability (easier to debug)
	var json_string = JSON.stringify(data, "\t")

	# --- Atomic write: write to temp, then rename ---

	# Step 1: write the JSON to the temp file
	var temp_file = FileAccess.open(TEMP_FILE_PATH, FileAccess.WRITE)
	if temp_file == null:
		push_error("SaveManager.save_game: could not open temp file for writing (error %d)" % FileAccess.get_open_error())
		return false
	temp_file.store_string(json_string)
	temp_file.close()

	# Step 2: rename temp file to the real slot path, atomically replacing any previous save
	var target_path = SAVE_FILE_TEMPLATE % slot
	var rename_error = DirAccess.rename_absolute(TEMP_FILE_PATH, target_path)
	if rename_error != OK:
		push_error("SaveManager.save_game: rename failed with error %d (temp → %s)" % [rename_error, target_path])
		return false

	# Update GameState so it knows which slot it is associated with
	GameState.save_slot = slot

	print("SaveManager: game saved to slot %d" % slot)
	return true

# ------------------------------------------------------------------------------
# load_game
# ------------------------------------------------------------------------------

# Reads the JSON file for the given slot and restores GameState from it.
# Returns true on success, false if the file doesn't exist or can't be parsed.
#
# Safe defaults: any field missing from the save file is filled in with a
# sensible default rather than crashing. This means older save files always
# load cleanly after a schema change.
func load_game(slot):
	# Validate slot range
	if slot < 0 or slot >= SLOT_COUNT:
		push_error("SaveManager.load_game: invalid slot %d" % slot)
		return false

	var path = SAVE_FILE_TEMPLATE % slot

	# Check the file exists before attempting to open it
	if not FileAccess.file_exists(path):
		push_warning("SaveManager.load_game: no save file at %s" % path)
		return false

	# Open and read the raw JSON string
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveManager.load_game: could not open %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	var raw = file.get_as_text()
	file.close()

	# Parse JSON — if parsing fails the save is corrupted, return false
	var parsed = JSON.parse_string(raw)
	if parsed == null:
		push_error("SaveManager.load_game: JSON parse failed for slot %d — file may be corrupted" % slot)
		return false

	# Run migration if the save was written by an older version
	var save_version = parsed.get("version", "0.0.0")
	if save_version != GameState.GAME_VERSION:
		parsed = _migrate_save(parsed, save_version)

	# Restore GameState from the (possibly migrated) data dictionary
	_deserialize_into_game_state(parsed, slot)

	print("SaveManager: slot %d loaded (version %s → %s)" % [slot, save_version, GameState.GAME_VERSION])
	return true

# ------------------------------------------------------------------------------
# get_slot_summary
# ------------------------------------------------------------------------------

# Returns a lightweight summary dictionary for displaying on the save/load
# screen WITHOUT fully loading the save into GameState.
#
# Return shape:
#   {
#     "exists":        bool,
#     "party_names":   Array,   # display names of party members, or []
#     "playtime":      float,   # seconds
#     "location_name": String,  # human-readable scene label or "Unknown"
#     "timestamp":     int      # Unix timestamp of when the file was written
#   }
func get_slot_summary(slot):
	# Build the "empty slot" result we return when no save exists
	var empty = {
		"exists": false,
		"party_names": [],
		"playtime": 0.0,
		"location_name": "Empty",
		"timestamp": 0
	}

	if slot < 0 or slot >= SLOT_COUNT:
		return empty

	var path = SAVE_FILE_TEMPLATE % slot
	if not FileAccess.file_exists(path):
		return empty

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return empty
	var raw = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(raw)
	if parsed == null:
		# Corrupted file — treat as empty so the UI doesn't break
		return empty

	# Extract just the fields needed for the summary display
	var party_names = []
	if parsed.has("party") and typeof(parsed["party"]) == TYPE_ARRAY:
		for member in parsed["party"]:
			if typeof(member) == TYPE_DICTIONARY and member.has("member_name"):
				party_names.append(member["member_name"])

	# Convert the scene path to a friendly display name
	var location_name = _scene_path_to_label(parsed.get("current_scene", ""))

	return {
		"exists": true,
		"party_names": party_names,
		"playtime": parsed.get("playtime", 0.0),
		"location_name": location_name,
		"timestamp": parsed.get("timestamp", 0)
	}

# ------------------------------------------------------------------------------
# delete_slot
# ------------------------------------------------------------------------------

# Deletes the save file for the given slot. Does nothing if no file exists.
# Call this when the player chooses "Delete Save" on the save screen.
func delete_slot(slot):
	if slot < 0 or slot >= SLOT_COUNT:
		push_error("SaveManager.delete_slot: invalid slot %d" % slot)
		return

	var path = SAVE_FILE_TEMPLATE % slot
	if not FileAccess.file_exists(path):
		# Nothing to delete — not an error
		return

	var err = DirAccess.remove_absolute(path)
	if err != OK:
		push_error("SaveManager.delete_slot: failed to delete %s (error %d)" % [path, err])
	else:
		print("SaveManager: slot %d deleted" % slot)

# ------------------------------------------------------------------------------
# _migrate_save (stub)
# ------------------------------------------------------------------------------

# Called automatically by load_game() when the save file's version string
# doesn't match the current GAME_VERSION.
#
# How to extend: add `if from_version == "0.1.0":` blocks that transform
# the data dictionary to match the current schema, then fall through to the
# next version check. Always return the modified data at the end.
#
# Example future migration:
#   if from_version == "0.1.0":
#       # "stamina" was added in 0.2.0 — seed a default for old saves
#       for member in data.get("party", []):
#           if not member.has("stamina"):
#               member["stamina"] = 10
#       from_version = "0.2.0"
func _migrate_save(data, from_version):
	push_warning("SaveManager._migrate_save: save is version %s, current is %s — no migration rules defined yet" % [from_version, GameState.GAME_VERSION])
	# No transformations yet — return data unchanged.
	# Future migrations go here as the schema evolves.
	return data

# ------------------------------------------------------------------------------
# _serialize_game_state (private)
# ------------------------------------------------------------------------------

# Builds and returns the full save dictionary from the current GameState.
# Party members are serialized as plain dictionaries because Resource objects
# can't be written directly to JSON.
func _serialize_game_state(slot):
	# Serialize each party member to a plain dict
	var party_data = []
	for member in GameState.party:
		party_data.append(_serialize_party_member(member))

	# player_position is a Vector2 — JSON doesn't have a Vector2 type,
	# so we store it as a plain { x, y } dictionary.
	var pos = GameState.player_position

	return {
		"version":        GameState.GAME_VERSION,
		"timestamp":      int(Time.get_unix_time_from_system()),
		"save_slot":      slot,
		"playtime":       GameState.playtime,
		"gold":           GameState.gold,
		"party":          party_data,
		"inventory":      GameState.inventory.duplicate(true),
		"world_flags":    GameState.world_flags.duplicate(true),
		"player_position": { "x": pos.x, "y": pos.y },
		"current_scene":  GameState.current_scene,
		"towns":          GameState.towns.duplicate(true)
	}

# Converts a PartyMemberData resource to a serializable dictionary.
# Only stores the fields we need to restore — the resource path is stored
# so we can reload the base resource and then apply saved stats on top.
func _serialize_party_member(member):
	# If the member resource doesn't have expected properties, log and skip
	if member == null:
		return {}
	return {
		# Store the resource path so we can re-load base data from disk on load
		"resource_path": member.resource_path if member.resource_path != "" else "",
		# Core identity — direct property access; Object.get() in Godot 4 does not
		# accept a second default-value argument the way Python's dict.get() does.
		"member_name":   member.member_name,
		# Current HP (may differ from max due to damage taken)
		"current_hp":    member.current_hp,
		# Current MP (may differ from max due to spell use)
		"current_mp":    member.current_mp,
		# Experience points earned — determines level
		"experience":    member.experience,
		# Current level derived from experience, cached here for the summary screen
		"level":         member.level
	}

# ------------------------------------------------------------------------------
# _deserialize_into_game_state (private)
# ------------------------------------------------------------------------------

# Reads from the parsed save dictionary and writes all values into GameState.
# Every field uses .get(key, default) so a missing field never causes a crash.
func _deserialize_into_game_state(data, slot):
	# Record which slot this session is tied to
	GameState.save_slot      = slot
	GameState.game_version   = data.get("version", GameState.GAME_VERSION)
	GameState.playtime       = data.get("playtime", 0.0)
	GameState.gold           = data.get("gold", 0)
	GameState.world_flags    = data.get("world_flags", {})
	GameState.current_scene  = data.get("current_scene", "res://scenes/world/overworld.tscn")
	GameState.towns          = data.get("towns", {})
	GameState.inventory      = data.get("inventory", [])
	GameState.in_battle      = false  # Never restore into a battle state

	# Restore player_position from the { x, y } dict back to a Vector2
	var pos_dict = data.get("player_position", { "x": 0, "y": 0 })
	GameState.player_position = Vector2(
		pos_dict.get("x", 0),
		pos_dict.get("y", 0)
	)

	# Restore party — load the base .tres resource for each member then overlay
	# the mutable fields (current_hp, current_mp, experience, level) from the
	# save data. This ensures all read-only stats (max_hp, attack, etc.) are
	# sourced from the authoritative resource file rather than from JSON, which
	# means a balance change in the .tres automatically applies on next load.
	var party_data = data.get("party", [])
	GameState.party = []
	for member_dict in party_data:
		# Skip nulls or empty dicts that may result from corrupted saves
		if typeof(member_dict) != TYPE_DICTIONARY or member_dict.is_empty():
			continue

		var resource_path = member_dict.get("resource_path", "")
		var member = null

		# Prefer loading from the stored resource path so the member retains
		# all base stats defined in the .tres file
		if resource_path != "" and ResourceLoader.exists(resource_path):
			member = load(resource_path)

		# Fallback: if the path is missing or the file was moved, reconstruct
		# by member_name — scan the known party_members directory
		if member == null:
			var fallback_name = member_dict.get("member_name", "").to_lower()
			var fallback_path = "res://resources/party_members/%s.tres" % fallback_name
			if ResourceLoader.exists(fallback_path):
				member = load(fallback_path)

		if member == null:
			push_warning("SaveManager: could not restore party member from dict: %s" % str(member_dict))
			continue

		# Overlay the mutable fields saved at the time of the save.
		# These may differ from the .tres defaults due to damage, spending MP,
		# or gaining XP since the resource was last edited.
		member.current_hp  = member_dict.get("current_hp",  member.current_hp)
		member.current_mp  = member_dict.get("current_mp",  member.current_mp)
		member.experience  = member_dict.get("experience",  member.experience)
		member.level       = member_dict.get("level",       member.level)

		GameState.party.append(member)

	# Emit signals so any already-open UI refreshes with the restored data
	GameState.emit_signal("gold_changed", GameState.gold)
	GameState.emit_signal("party_changed")
	GameState.emit_signal("inventory_changed")

# ------------------------------------------------------------------------------
# _scene_path_to_label (private)
# ------------------------------------------------------------------------------

# Converts a scene resource path to a short human-readable display label
# for use on the save/load screen. Extend this dictionary as new scenes are added.
func _scene_path_to_label(scene_path):
	# Map of known scene paths to display-friendly names
	var labels = {
		"res://scenes/world/overworld.tscn": "Overworld",
		"res://scenes/battle/battle_scene.tscn": "In Battle"
	}
	if labels.has(scene_path):
		return labels[scene_path]
	# Fall back to the filename without extension if path is unrecognised
	if scene_path != "":
		return scene_path.get_file().get_basename().replace("_", " ").capitalize()
	return "Unknown"
