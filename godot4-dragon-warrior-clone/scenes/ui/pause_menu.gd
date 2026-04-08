# ==============================================================================
# pause_menu.gd
# Part of: godot4-dragon-warrior-clone
# Description: Pause menu overlay. Displays party status, inventory with
#              consumable Use buttons, and Save / Close actions. Manages its
#              own visibility — toggles on menu_open and closes on ui_cancel.
#              Pauses the scene tree while visible so the world freezes.
# Attached to: PauseMenu (Control — root of pause_menu.tscn)
# ==============================================================================

extends Control

# ------------------------------------------------------------------------------
# Signals — emitted when the player makes choices so managers can react.
# This script never calls SaveManager directly for save logic outside of the
# sanctioned save_game() call; all other game-affecting choices go through
# signals so the appropriate manager can act.
# ------------------------------------------------------------------------------

# Fired when the player requests a save on a specific slot (0-indexed).
# SaveManager in the overworld (or whichever scene is active) should connect
# this and call SaveManager.save_game(slot_index).
# NOTE: This script calls SaveManager.save_game() directly because SaveManager
# is a stateless utility autoload — it does not affect GameState directly, only
# reads and writes disk. This is the one sanctioned direct call from UI.
signal save_requested(slot_index)

# ------------------------------------------------------------------------------
# Node references — all populated via @onready to avoid null-reference errors.
# The tree structure is defined in pause_menu.tscn and must match these paths.
# ------------------------------------------------------------------------------

# The dark semi-transparent overlay that dims the game behind the menu
@onready var overlay = $Overlay

# The centered white panel that contains all menu content
@onready var panel = $Overlay/Panel

# --- Party status labels (top section) ---
@onready var label_name = $Overlay/Panel/VBox/TopSection/LabelName
@onready var label_hp   = $Overlay/Panel/VBox/TopSection/LabelHP
@onready var label_mp   = $Overlay/Panel/VBox/TopSection/LabelMP
@onready var label_xp   = $Overlay/Panel/VBox/TopSection/LabelXP
@onready var label_gold = $Overlay/Panel/VBox/TopSection/LabelGold

# --- Inventory section (middle) ---
# The VBoxContainer whose children are rebuilt on every _refresh() call
@onready var inventory_list = $Overlay/Panel/VBox/MiddleSection/InventoryScroll/InventoryList

# --- Bottom section containers ---
# The normal bottom section with Save and Close buttons
@onready var bottom_normal  = $Overlay/Panel/VBox/BottomSection/BottomNormal
# The slot-selection section shown after pressing Save
@onready var bottom_slots   = $Overlay/Panel/VBox/BottomSection/BottomSlots

# --- Normal bottom widgets ---
@onready var btn_save            = $Overlay/Panel/VBox/BottomSection/BottomNormal/ButtonRow/BtnSave
@onready var label_no_scroll     = $Overlay/Panel/VBox/BottomSection/BottomNormal/LabelNoScroll
@onready var btn_close           = $Overlay/Panel/VBox/BottomSection/BottomNormal/ButtonRow/BtnClose

# --- Slot-selection widgets ---
@onready var btn_slot_0          = $Overlay/Panel/VBox/BottomSection/BottomSlots/SlotRow/BtnSlot0
@onready var btn_slot_1          = $Overlay/Panel/VBox/BottomSection/BottomSlots/SlotRow/BtnSlot1
@onready var btn_slot_2          = $Overlay/Panel/VBox/BottomSection/BottomSlots/SlotRow/BtnSlot2
@onready var label_saved_confirm = $Overlay/Panel/VBox/BottomSection/BottomSlots/LabelSavedConfirm

# Timer used to auto-dismiss the "Game Saved!" confirmation message after 1.5 s
@onready var save_confirm_timer  = $SaveConfirmTimer

# ------------------------------------------------------------------------------
# _ready
# ------------------------------------------------------------------------------

func _ready():
	# Start hidden — we show ourselves when the player presses menu_open
	hide()

	# Connect button signals in code rather than in the editor so all wiring
	# lives in one place and the .tscn stays clean
	btn_save.pressed.connect(_on_save_pressed)
	btn_close.pressed.connect(_on_close_pressed)
	btn_slot_0.pressed.connect(_on_slot_pressed.bind(0))
	btn_slot_1.pressed.connect(_on_slot_pressed.bind(1))
	btn_slot_2.pressed.connect(_on_slot_pressed.bind(2))

	# When the confirmation timer fires, restore the normal bottom section
	save_confirm_timer.timeout.connect(_on_save_confirm_timer_timeout)

	# Start with the normal bottom section visible, slots hidden
	bottom_normal.show()
	bottom_slots.hide()
	label_saved_confirm.hide()

# ------------------------------------------------------------------------------
# _process
# ------------------------------------------------------------------------------

# Polls for the menu_open and ui_cancel input actions every frame.
# process_mode is set to PROCESS_MODE_ALWAYS on the root node so this
# continues to run while get_tree().paused = true.
func _process(_delta):
	# Toggle open: menu_open while hidden → show and refresh
	if Input.is_action_just_pressed("menu_open"):
		if not visible:
			_open_menu()
		else:
			# Second press of menu_open closes the menu
			_close_menu()
		return

	# ui_cancel also closes the menu when it is open
	if Input.is_action_just_pressed("ui_cancel") and visible:
		_close_menu()

# ------------------------------------------------------------------------------
# _open_menu
# ------------------------------------------------------------------------------

# Shows the pause menu, refreshes all displayed data, and pauses the scene tree
# so the world (player movement, encounter ticks, etc.) freezes while open.
func _open_menu():
	_refresh()
	show()
	get_tree().paused = true

	# Pause playtime accumulation — the player shouldn't be charged play-hours
	# for time spent reading their stats in the menu.
	GameState.pause_playtime()

	# Return focus to the Save button so keyboard/gamepad navigation works
	# immediately after the menu opens without requiring a mouse click.
	btn_save.grab_focus()

# ------------------------------------------------------------------------------
# _close_menu
# ------------------------------------------------------------------------------

# Hides the pause menu and resumes normal game flow.
# Resets the slot section back to the normal bottom view in case the player
# opened Save but then dismissed with ui_cancel before selecting a slot.
func _close_menu():
	hide()
	get_tree().paused = false

	# Resume playtime now that the player is back in control
	GameState.resume_playtime()

	# Reset bottom section to normal so next open starts clean
	bottom_normal.show()
	bottom_slots.hide()
	label_saved_confirm.hide()
	save_confirm_timer.stop()

# ------------------------------------------------------------------------------
# _refresh
# ------------------------------------------------------------------------------

# Reads live data from GameState and updates every label and list in the menu.
# Called every time the menu opens. Also safe to call mid-session if needed.
func _refresh():
	# Guard against an empty party — nothing to display and accessing [0]
	# would crash the game.
	if GameState.party.is_empty():
		return

	var hero = GameState.party[0]

	# --- Party status labels ---
	# Format: "Erdrick   Lv 3" — padded for visual alignment
	label_name.text = "%s   Lv %d" % [hero.member_name, hero.level]

	# HP current / max
	label_hp.text   = "HP    %d / %d" % [hero.current_hp, hero.max_hp]

	# MP current / max
	label_mp.text   = "MP    %d / %d" % [hero.current_mp, hero.max_mp]

	# XP total (no max — XP accumulates indefinitely)
	label_xp.text   = "XP    %d" % hero.experience

	# Gold with G suffix, reading from GameState (never from the hero resource)
	label_gold.text = "Gold  %d G" % GameState.gold

	# --- Inventory list ---
	_rebuild_inventory_list()

	# --- Save button state ---
	# Save is only allowed when the player possesses a Royal Scroll (save_permit)
	_refresh_save_button()

# ------------------------------------------------------------------------------
# _rebuild_inventory_list
# ------------------------------------------------------------------------------

# Clears and repopulates the inventory VBoxContainer.
# Each consumable item gets a name label + "Use" button row.
# Key items (effect_type == "save_permit") show "(Key Item)" instead of a
# Use button because they are passive and not consumed on use.
func _rebuild_inventory_list():
	# Remove all existing children so we start from a clean slate on each refresh
	for child in inventory_list.get_children():
		child.queue_free()

	# If the inventory is completely empty, show a placeholder label
	if GameState.inventory.is_empty():
		var empty_label = Label.new()
		empty_label.text = "— Empty —"
		empty_label.add_theme_font_size_override("font_size", 20)
		inventory_list.add_child(empty_label)
		return

	# Build one row per inventory entry
	for entry in GameState.inventory:
		var item_id  = entry["item_id"]
		var quantity = entry["quantity"]

		# Load the ItemData resource for this item so we can read its display
		# name and effect type. If the resource doesn't exist, fall back gracefully.
		var item_path = "res://resources/items/%s.tres" % item_id
		var item_data = null
		if ResourceLoader.exists(item_path):
			item_data = load(item_path)

		# Determine display name — use ItemData.item_name if available, else item_id
		var display_name = item_id
		if item_data != null:
			display_name = item_data.item_name

		# Build the row container
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)

		# Item name + quantity label (left-aligned, expands to fill available width)
		var name_label = Label.new()
		name_label.text = "%s  x%d" % [display_name, quantity]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 20)
		row.add_child(name_label)

		# Decide what to put on the right side of the row
		if item_data != null and item_data.effect_type == "save_permit":
			# Key items are passive — never consumed, never "used" from this menu
			var key_label = Label.new()
			key_label.text = "(Key Item)"
			key_label.add_theme_font_size_override("font_size", 20)
			row.add_child(key_label)
		else:
			# Consumable item — show a Use button
			var use_btn = Button.new()
			use_btn.text = "Use"
			use_btn.focus_mode = Control.FOCUS_ALL   # gamepad navigable
			use_btn.add_theme_font_size_override("font_size", 20)
			# Bind item_id so the callback knows which item was pressed
			use_btn.pressed.connect(_on_use_item_pressed.bind(item_id, item_data))
			row.add_child(use_btn)

		inventory_list.add_child(row)

# ------------------------------------------------------------------------------
# _refresh_save_button
# ------------------------------------------------------------------------------

# Enables the Save button only when the player has a save_permit item (Royal Scroll).
# When disabled, shows a small explanatory label.
func _refresh_save_button():
	var has_scroll = _player_has_save_permit()
	btn_save.disabled = not has_scroll
	# Show the "Requires Royal Scroll" hint only when Save is disabled
	label_no_scroll.visible = not has_scroll

# ------------------------------------------------------------------------------
# _player_has_save_permit
# ------------------------------------------------------------------------------

# Returns true if any item in GameState.inventory has effect_type == "save_permit".
# This is the Royal Scroll check — saving is gated behind possessing this key item.
func _player_has_save_permit():
	for entry in GameState.inventory:
		var item_path = "res://resources/items/%s.tres" % entry["item_id"]
		if ResourceLoader.exists(item_path):
			var item_data = load(item_path)
			if item_data != null and item_data.effect_type == "save_permit":
				return true
	return false

# ------------------------------------------------------------------------------
# _on_use_item_pressed
# ------------------------------------------------------------------------------

# Called when the player presses "Use" on an inventory item.
# Applies the item's effect to the party leader (party[0]) and removes one copy.
# TODO: route through an ItemManager once one exists — direct GameState writes
#       from UI are acceptable here only because no ItemManager exists yet.
func _on_use_item_pressed(item_id, item_data):
	# Guard against an empty party (shouldn't happen here, but be safe)
	if GameState.party.is_empty():
		return

	# Null item_data means the resource file is missing — skip silently
	if item_data == null:
		push_warning("pause_menu: could not load ItemData for '%s'" % item_id)
		return

	var hero = GameState.party[0]

	# Apply the effect based on effect_type
	if item_data.effect_type == "heal_hp":
		# Restore HP to the party leader, clamped to their maximum
		hero.current_hp = min(hero.current_hp + item_data.effect_value, hero.max_hp)

	elif item_data.effect_type == "heal_mp":
		# Restore MP to the party leader, clamped to their maximum
		hero.current_mp = min(hero.current_mp + item_data.effect_value, hero.max_mp)

	elif item_data.effect_type == "revive":
		# Revive the party leader with the specified HP amount
		# Only useful if the hero is knocked out; safe to apply regardless
		hero.current_hp = min(item_data.effect_value, hero.max_hp)

	# Consume one copy of the item from the inventory.
	# GameState.remove_item() handles quantity decrement and entry removal.
	GameState.remove_item(item_id, 1)

	# Refresh the UI to show the updated HP/MP and depleted inventory entry
	_refresh()

# ------------------------------------------------------------------------------
# _on_save_pressed
# ------------------------------------------------------------------------------

# Swaps the bottom section from the normal view to the slot-selection view.
# The actual save happens in _on_slot_pressed when the player picks a slot.
func _on_save_pressed():
	# Switch to slot-selection mode
	bottom_normal.hide()
	bottom_slots.show()
	label_saved_confirm.hide()

	# Give focus to Slot 1 so the player can navigate immediately with a gamepad
	btn_slot_0.grab_focus()

# ------------------------------------------------------------------------------
# _on_slot_pressed
# ------------------------------------------------------------------------------

# Called when the player selects a save slot (0, 1, or 2).
# Delegates the actual disk write to SaveManager, then shows a brief
# confirmation message before restoring the normal bottom section.
func _on_slot_pressed(slot_index):
	# Delegate the save to SaveManager — UI never writes to disk directly
	var success = SaveManager.save_game(slot_index)

	if success:
		# Show the confirmation label and start the auto-dismiss timer
		label_saved_confirm.text = "Game Saved!"
		label_saved_confirm.show()
		save_confirm_timer.start()
	else:
		# Save failed (e.g. mid-battle guard triggered) — show an error message
		# and let the timer dismiss it so the player can try again
		label_saved_confirm.text = "Save Failed!"
		label_saved_confirm.show()
		save_confirm_timer.start()

# ------------------------------------------------------------------------------
# _on_save_confirm_timer_timeout
# ------------------------------------------------------------------------------

# Fires 1.5 seconds after a save attempt. Hides the confirmation message and
# restores the normal bottom section so the menu is back in its resting state.
func _on_save_confirm_timer_timeout():
	label_saved_confirm.hide()
	bottom_slots.hide()
	bottom_normal.show()

	# Return focus to the Save button for clean keyboard/gamepad navigation
	btn_save.grab_focus()

# ------------------------------------------------------------------------------
# _on_close_pressed
# ------------------------------------------------------------------------------

# Closes the pause menu when the "Close" button is pressed.
func _on_close_pressed():
	_close_menu()
