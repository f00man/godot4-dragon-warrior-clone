# ==============================================================================
# save_screen.gd
# Part of: godot4-dragon-warrior-clone
# Description: Save slot selection screen. Displays all 3 save slots with
#              party info, playtime, and location. Supports loading and deleting
#              slots. Keyboard/gamepad navigable via _process + Input polling.
# Attached to: Control (SaveScreen)
# ==============================================================================

extends Control

# ------------------------------------------------------------------------------
# Node references — resolved once in _ready, never accessed via string path.
# Each slot row has an InfoLabel (display), BtnLoad, and BtnDelete.
# ------------------------------------------------------------------------------

@onready var slot_labels  = [$SlotList/Slot0/InfoLabel, $SlotList/Slot1/InfoLabel, $SlotList/Slot2/InfoLabel]
@onready var load_buttons = [$SlotList/Slot0/BtnLoad,   $SlotList/Slot1/BtnLoad,   $SlotList/Slot2/BtnLoad]
@onready var delete_buttons = [$SlotList/Slot0/BtnDelete, $SlotList/Slot1/BtnDelete, $SlotList/Slot2/BtnDelete]
@onready var btn_back = $BtnBack

# ------------------------------------------------------------------------------
# State
# ------------------------------------------------------------------------------

# Index into _nav_buttons pointing at the currently highlighted button.
# Starts at 0 so the first enabled button is selected on open.
var _focused_index = 0

# Flat ordered list of navigable buttons built in _ready() after slot data is
# loaded. Only enabled buttons and btn_back are included. Navigation skips
# disabled entries automatically via _move_focus().
var _nav_buttons = []


func _ready():
	# While this screen is open the player is not actively playing, so we stop
	# the playtime clock. The overworld is responsible for resuming it when the
	# player regains control after loading.
	GameState.pause_playtime()

	# Populate all three slot rows with data from SaveManager before building
	# the navigation list — slot enabled/disabled state must be known first.
	_refresh_slots()

	# Build the flat navigation list from all load/delete buttons that are
	# currently enabled, then append the Back button at the end so it is always
	# reachable regardless of slot state.
	_build_nav_buttons()

	# Wire button signals here in code so the connections are visible in this
	# file rather than hidden in the .tscn.
	for i in range(3):
		# Capture i by value using a lambda with a default argument. Without the
		# default argument trick, all three closures would close over the same i
		# and all fire with i == 3.
		load_buttons[i].pressed.connect(func(slot = i): _on_load_pressed(slot))
		delete_buttons[i].pressed.connect(func(slot = i): _on_delete_pressed(slot))
	btn_back.pressed.connect(_on_back_pressed)

	# Defer the first grab_focus() call so Godot's layout pass has completed.
	# Calling grab_focus() synchronously in _ready() can silently fail on the
	# first frame before the scene is fully sized.
	_nav_buttons[0].grab_focus.call_deferred()


func _process(_delta):
	# Poll Input directly every frame. Godot's Viewport GUI system consumes
	# ui_up/ui_down during the input phase when a Control has keyboard focus,
	# so _input and _unhandled_input never receive those events. Reading from
	# the Input singleton in _process bypasses that consumption entirely and
	# gives us consistent one-trigger-per-keydown behaviour via
	# is_action_just_pressed().
	if Input.is_action_just_pressed("ui_down"):
		_move_focus(1)
	elif Input.is_action_just_pressed("ui_up"):
		_move_focus(-1)
	elif Input.is_action_just_pressed("ui_accept"):
		# Confirm the currently focused button. The disabled guard is a safety
		# net — _focused_index should never point at a disabled button because
		# _build_nav_buttons() excludes them, but defensive code costs nothing.
		if not _nav_buttons[_focused_index].disabled:
			_nav_buttons[_focused_index].emit_signal("pressed")


# Moves the highlighted button by `direction` steps (+1 = down, -1 = up),
# wrapping around the ends of the list and skipping any disabled buttons.
# This matches the navigation pattern used in main_menu.gd.
func _move_focus(direction):
	var count = _nav_buttons.size()
	# Iterate through candidates in the requested direction. Multiplying count
	# by count guarantees the modulo arithmetic stays positive even when
	# _focused_index is 0 and direction is -1.
	for i in range(1, count + 1):
		var candidate = (_focused_index + direction * i + count * count) % count
		if not _nav_buttons[candidate].disabled:
			_focused_index = candidate
			break
	# Update the visual focus highlight to the newly selected button.
	_nav_buttons[_focused_index].grab_focus()


# Populates slot_labels and sets the enabled state of load/delete buttons for
# all three slots by reading lightweight summaries from SaveManager.
func _refresh_slots():
	for i in range(3):
		var summary = SaveManager.get_slot_summary(i)

		if summary.get("exists", false):
			# Format the pieces of info we want to display.
			var playtime_str = _format_playtime(summary.get("playtime", 0.0))

			# Join party member names into a comma-separated string, or show a
			# placeholder if the party array is empty.
			var names = summary.get("party_names", [])
			var party_str = ", ".join(names) if names.size() > 0 else "No party"

			# Convert the Unix timestamp to a readable date/time string.
			var ts = summary.get("timestamp", 0)
			var date_str = Time.get_datetime_string_from_unix_time(ts) if ts > 0 else "Unknown date"

			# Build a multi-line display string with all relevant slot info.
			slot_labels[i].text = (
				"Slot %d  |  %s\nParty: %s\nSaved: %s" % [i + 1, playtime_str, party_str, date_str]
			)

			# Enable the action buttons for this slot since data exists.
			load_buttons[i].disabled = false
			delete_buttons[i].disabled = false
		else:
			# No save data in this slot — show a placeholder and grey out buttons.
			slot_labels[i].text = "— Empty —"
			load_buttons[i].disabled = true
			delete_buttons[i].disabled = true


# Rebuilds _nav_buttons from the current enabled/disabled button states.
# Called once in _ready() and again after a delete to reflect the new state.
func _build_nav_buttons():
	_nav_buttons = []

	# Add load and delete buttons for each slot, but only when they are enabled.
	# Disabled buttons are skipped so navigation never lands on an empty-slot
	# action the player can't actually perform.
	for i in range(3):
		if not load_buttons[i].disabled:
			_nav_buttons.append(load_buttons[i])
		if not delete_buttons[i].disabled:
			_nav_buttons.append(delete_buttons[i])

	# Always include Back at the end regardless of slot state so the player
	# can leave this screen even if all slots are empty.
	_nav_buttons.append(btn_back)


# Converts a raw seconds value to a human-readable "H:MM:SS" string.
# Example: 3661 seconds → "1:01:01"
func _format_playtime(seconds):
	var total_secs = int(seconds)

	# Integer-divide by 3600 to get whole hours.
	var hours = total_secs / 3600

	# The remainder after removing full hours gives us the sub-hour seconds.
	# Divide that by 60 for whole minutes.
	var minutes = (total_secs % 3600) / 60

	# Whatever is left after removing full minutes is the displayed seconds.
	var secs = total_secs % 60

	# Zero-pad minutes and seconds to two digits so "1:01:01" not "1:1:1".
	return "%d:%02d:%02d" % [hours, minutes, secs]


# Called when the player presses Load on a slot. Restores the full GameState
# from disk and then transitions to wherever the player last saved.
func _on_load_pressed(slot):
	# load_game() populates all GameState fields, including current_scene which
	# tells us the exact scene the player was in when they saved.
	SaveManager.load_game(slot)

	# Load restores GameState including current_scene, so we transition to
	# wherever the player last saved. SceneManager handles the fade.
	SceneManager.transition_to(GameState.current_scene)


# Called when the player presses Delete on a slot. Removes the save file and
# refreshes the display so the slot immediately shows as empty.
func _on_delete_pressed(slot):
	# Remove the file from disk.
	SaveManager.delete_slot(slot)

	# Repopulate the labels and re-enable/disable buttons to reflect the deletion.
	_refresh_slots()

	# The navigation list must be rebuilt because the load/delete buttons for
	# the deleted slot are now disabled and should not be reachable.
	_build_nav_buttons()

	# Reset focus to the start of the rebuilt list so the cursor is never left
	# pointing at a button that no longer exists in _nav_buttons.
	_focused_index = 0
	_nav_buttons[0].grab_focus()


# Called when the player presses the Back button. Returns to the previous
# screen (main menu) using SceneManager's history-aware back transition.
func _on_back_pressed():
	SceneManager.transition_back()
