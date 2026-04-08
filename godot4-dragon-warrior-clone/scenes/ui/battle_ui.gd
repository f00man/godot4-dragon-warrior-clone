# ==============================================================================
# battle_ui.gd
# Part of: godot4-dragon-warrior-clone
# Description: Full battle UI. Displays the enemy name, party HP/MP bars,
#              floating damage numbers, an action menu (Attack/Magic/Item/Run),
#              an item sub-panel, and a scrolling battle log label. Reads display
#              data from GameState.party (never writes). Calls back to a stored
#              BattleManager reference when the player confirms an action.
# Attached to: BattleUI (Control)
# ==============================================================================

extends Control

# ------------------------------------------------------------------------------
# Signals — emitted by this UI so external listeners can react if needed.
# BattleScene itself does not currently need these, but they are defined here
# per UI-agent convention so the system is extensible without touching this file.
# ------------------------------------------------------------------------------

# Emitted after the player picks Attack, Magic, Item, or Run. The action_type
# string mirrors the BattleManager method that will be called.
signal action_selected(action_type)

# Emitted after the player selects an item from the item sub-panel.
signal item_selected(item_id)

# ------------------------------------------------------------------------------
# Node references — all resolved at runtime via @onready.
# Matches the node paths in battle_ui.tscn exactly.
# ------------------------------------------------------------------------------

# --- Enemy area ---
@onready var enemy_name_label     = $EnemyArea/EnemyNameLabel
@onready var damage_label         = $EnemyArea/DamageLabel

# --- Party panel ---
# PartyRows is a VBoxContainer; each child is a Control row created dynamically.
@onready var party_rows_container = $BottomPanel/PartyRows

# --- Action menu ---
@onready var action_menu          = $BottomPanel/ActionMenu
@onready var action_label         = $BottomPanel/ActionMenu/ActionLabel
@onready var btn_attack           = $BottomPanel/ActionMenu/ButtonGrid/BtnAttack
@onready var btn_magic            = $BottomPanel/ActionMenu/ButtonGrid/BtnMagic
@onready var btn_item             = $BottomPanel/ActionMenu/ButtonGrid/BtnItem
@onready var btn_run              = $BottomPanel/ActionMenu/ButtonGrid/BtnRun

# --- Item sub-panel ---
@onready var item_panel           = $BottomPanel/ItemPanel
@onready var item_list_container  = $BottomPanel/ItemPanel/ItemList

# --- Battle log ---
@onready var battle_log_label     = $BattleLogLabel

# ------------------------------------------------------------------------------
# Private state
# ------------------------------------------------------------------------------

# Reference to BattleManager set by setup(). Stored so action buttons can call
# the correct methods without knowing about the scene tree from here.
var _battle_manager = null

# Maps member_name (String) → Control row node, so we can update HP/MP quickly
# when damage or heal signals arrive without scanning the container every time.
var _party_row_map = {}

# Grid position of the currently focused action button.
# The 2x2 layout is: row 0 = [Attack, Magic], row 1 = [Item, Run].
# Tracked as row/col so directional movement is axis-aligned with no wrapping.
var _action_row = 0
var _action_col = 0

# Convenience flat index derived from _action_row/_action_col (row * 2 + col).
# Order: 0=Attack, 1=Magic, 2=Item, 3=Run.
var _action_focus_index = 0

# Flat list of action buttons in grid order, used by navigation logic.
var _action_buttons = []

# Tracks which item row in the item sub-panel is focused.
var _item_focus_index = 0

# Flat list of item buttons built dynamically when the item panel opens.
var _item_buttons = []

# The original Y position of DamageLabel as defined in the .tscn (offset_top = 180).
# Stored in _ready() so _show_damage_number() can reset to it before each animation
# instead of reading the already-drifted current position, which would drift the label
# further up the screen with every successive hit until it disappears off-screen.
var _damage_label_origin_y = 0.0

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Record the label's starting Y before any tweens run. We reset to this value
	# at the start of each hit so successive damage numbers always pop from the same
	# screen position rather than drifting further up on each attack.
	_damage_label_origin_y = damage_label.position.y

	# Hide floating damage number immediately — it appears only on demand.
	damage_label.visible = false

	# Hide the action menu and item sub-panel until BattleManager asks for input.
	action_menu.visible = false
	item_panel.visible = false

	# Disable Magic for now — no spell system yet. A disabled button still shows
	# in the layout but cannot be focused or activated, communicating to the player
	# that the option will be available later.
	btn_magic.disabled = true

	# Build the ordered button list so navigation code can index into it cleanly.
	_action_buttons = [btn_attack, btn_magic, btn_item, btn_run]

	# Party rows are built in _on_battle_started() rather than here because
	# _ready() fires on BattleUI before BattleScene._ready() runs. At this point
	# GameState.party is still empty — start_battle() hasn't loaded the fallback
	# hero yet. Building rows in _on_battle_started() guarantees the party is set.

	# Start with a blank log message — the log updates as signals arrive.
	battle_log_label.text = ""

# ------------------------------------------------------------------------------
# Public API — called by battle_scene.gd
# ------------------------------------------------------------------------------

# Wires all BattleManager signals to this UI's handler functions.
# Must be called from battle_scene.gd BEFORE start_battle() so that the
# battle_started signal is already connected when start_battle() emits it.
# BattleUI never holds a direct scene-tree dependency on BattleManager.
#
# battle_manager_node — the BattleManager Node child of BattleScene.
func setup(battle_manager_node):
	_battle_manager = battle_manager_node

	# Connect every signal from BattleManager to the matching handler below.
	# Connecting here (rather than in the .tscn) keeps all wiring in one place
	# and avoids editor-connection drift as signal signatures evolve.
	_battle_manager.battle_started.connect(_on_battle_started)
	_battle_manager.action_needed.connect(_on_action_needed)
	_battle_manager.damage_dealt.connect(_on_damage_dealt)
	_battle_manager.member_healed.connect(_on_member_healed)
	_battle_manager.enemy_defeated.connect(_on_enemy_defeated)
	_battle_manager.party_member_defeated.connect(_on_party_member_defeated)
	_battle_manager.battle_won.connect(_on_battle_won)
	_battle_manager.battle_lost.connect(_on_battle_lost)
	_battle_manager.run_succeeded.connect(_on_run_succeeded)
	_battle_manager.run_failed.connect(_on_run_failed)
	_battle_manager.battle_log.connect(_on_battle_log)

# Reads GameState.party and refreshes every HP/MP bar and label in the party panel.
# Called at battle start and after any heal or damage event so the display stays
# in sync with the live PartyMemberData resources.
func refresh_party_display():
	for member in GameState.party:
		var name_key = member.member_name
		if not _party_row_map.has(name_key):
			# Member joined mid-battle or wasn't present at _ready() — skip safely.
			continue

		var row = _party_row_map[name_key]

		# Update HP bar maximum and current value.
		var hp_bar = row.get_node("HPBar")
		hp_bar.max_value = member.max_hp
		hp_bar.value     = member.current_hp

		# Update the "current / max" HP label next to the bar.
		var hp_label = row.get_node("HPLabel")
		hp_label.text = "%d / %d" % [member.current_hp, member.max_hp]

		# Update MP bar and label the same way.
		var mp_bar = row.get_node("MPBar")
		mp_bar.max_value = member.max_mp
		mp_bar.value     = member.current_mp

		var mp_label = row.get_node("MPLabel")
		mp_label.text = "%d / %d" % [member.current_mp, member.max_mp]

# ------------------------------------------------------------------------------
# BattleManager signal handlers
# ------------------------------------------------------------------------------

# Fires once when the battle begins. Populate the enemy name label, hide the
# action menu (it will re-appear when action_needed fires for the first member),
# and refresh the party display with the current HP/MP values.
func _on_battle_started(enemy_names):
	# Show the first enemy's name. Multiple enemy display is a future TODO.
	if enemy_names.size() > 0:
		enemy_name_label.text = enemy_names[0]
	else:
		enemy_name_label.text = "???"

	# Make sure the action menu is hidden until a player turn begins.
	action_menu.visible = false
	item_panel.visible  = false

	# Build party rows now — GameState.party is guaranteed to be populated at
	# this point because start_battle() runs before emitting this signal.
	# (BattleUI._ready() fired earlier when the party was still empty.)
	_build_party_rows()

	# Populate all HP/MP values from the current party state.
	refresh_party_display()

# Fires when a party member needs a player decision. Show the action menu with
# the member's name so the player knows who they are acting for.
func _on_action_needed(member_name):
	# Close the item panel if it was open from a previous turn.
	item_panel.visible = false

	# Update the prompt label and reveal the menu.
	action_label.text  = "Choose action for %s:" % member_name
	action_menu.visible = true

	# Always reset focus to Attack when a new turn starts so the cursor position
	# from the last turn doesn't confuse the player.
	_action_focus_index = 0
	_update_action_focus()

# Fires when any hit lands. Shows a floating damage number over the enemy area
# for enemy hits; flashes the affected party row red for party hits.
func _on_damage_dealt(target_name, amount, is_enemy_target):
	if is_enemy_target:
		# Show the damage number floating over the enemy sprite area, then fade it.
		_show_damage_number(amount)
	else:
		# Flash the party row red so the player registers which member was hurt.
		_flash_party_row_red(target_name)

	# Refresh HP/MP bars regardless of who was hit, so values stay accurate.
	refresh_party_display()

# Fires when a party member's HP is restored by an item or spell.
func _on_member_healed(member_name, _amount):
	# A heal always means HP/MP values changed — refresh the entire panel.
	# The member_name parameter is available if we later want to highlight
	# just the affected row, but a full refresh is safe and simple for now.
	refresh_party_display()

# Fires when an enemy at enemy_index is reduced to 0 HP.
func _on_enemy_defeated(_enemy_index):
	# For now there is only one enemy shown. Mark it as defeated in the name label.
	# When multi-enemy display is added, use enemy_index to target the correct label.
	enemy_name_label.text = "(Defeated)"

# Fires when a party member's HP reaches 0. Grey out their row to show they
# can no longer act or be targeted.
func _on_party_member_defeated(member_name):
	if _party_row_map.has(member_name):
		var row = _party_row_map[member_name]
		# Tint the entire row grey using the modulate property — no game state change.
		row.modulate = Color(0.5, 0.5, 0.5, 1.0)

# Fires when all enemies are defeated. Hide the action menu and show victory text.
func _on_battle_won(exp_gained, gold_gained):
	action_menu.visible = false
	item_panel.visible  = false
	# Write the reward summary to the battle log so the player can see it clearly.
	battle_log_label.text = "Victory! +%d EXP, +%d Gold" % [exp_gained, gold_gained]

# Fires when the entire party is wiped out.
func _on_battle_lost():
	action_menu.visible = false
	item_panel.visible  = false
	battle_log_label.text = "Defeat..."

# Fires when a run attempt succeeds. The BattleManager also emits battle_log
# with "Got away safely!" but we update the log here too as a safety net in case
# signal order ever changes.
func _on_run_succeeded():
	action_menu.visible = false
	item_panel.visible  = false
	battle_log_label.text = "Got away safely!"

# Fires when a run attempt fails. Show the message from BattleManager in the log.
func _on_run_failed(message):
	battle_log_label.text = message

# Fires for every narrative event — hits, misses, turn announcements, etc.
# Update the battle log label with the latest message so the player has context.
func _on_battle_log(message):
	battle_log_label.text = message

# ------------------------------------------------------------------------------
# Private: Party display helpers
# ------------------------------------------------------------------------------

# Creates one Control row per party member and registers it in _party_row_map.
# Each row contains: a name Label, HP ProgressBar, HP Label, MP ProgressBar,
# MP Label — all positioned as children of the row Control.
func _build_party_rows():
	# Clear any rows from a previous call (e.g. if _ready fires again after reload).
	for child in party_rows_container.get_children():
		child.queue_free()
	_party_row_map.clear()

	for member in GameState.party:
		var row = _create_party_row(member)
		party_rows_container.add_child(row)
		# Map by name so _on_damage_dealt and _on_member_healed can look up fast.
		_party_row_map[member.member_name] = row

# Constructs and returns a single party member row Control node.
# The layout is: [Name] [HP bar ----] [HP num] [MP bar ----] [MP num]
# Uses an HBoxContainer so items stretch naturally at runtime.
func _create_party_row(member):
	# Outer HBox spans the full row width.
	var row = HBoxContainer.new()
	row.name = "Row_" + member.member_name

	# Member name label — fixed width so bars align across different name lengths.
	var name_lbl = Label.new()
	name_lbl.name = "MemberName"
	name_lbl.text = member.member_name
	name_lbl.custom_minimum_size = Vector2(160, 0)
	name_lbl.add_theme_font_size_override("font_size", 22)
	row.add_child(name_lbl)

	# "HP" static label.
	var hp_static = Label.new()
	hp_static.text = "HP"
	hp_static.custom_minimum_size = Vector2(36, 0)
	hp_static.add_theme_font_size_override("font_size", 20)
	row.add_child(hp_static)

	# HP progress bar.
	var hp_bar = ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.max_value = member.max_hp
	hp_bar.value     = member.current_hp
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(200, 24)
	# SIZE_EXPAND_FILL lets the bar take remaining space but respects the label columns.
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hp_bar)

	# Numeric HP readout: "current / max".
	var hp_lbl = Label.new()
	hp_lbl.name = "HPLabel"
	hp_lbl.text = "%d / %d" % [member.current_hp, member.max_hp]
	hp_lbl.custom_minimum_size = Vector2(120, 0)
	hp_lbl.add_theme_font_size_override("font_size", 20)
	row.add_child(hp_lbl)

	# Spacer between HP and MP columns.
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	row.add_child(spacer)

	# "MP" static label.
	var mp_static = Label.new()
	mp_static.text = "MP"
	mp_static.custom_minimum_size = Vector2(36, 0)
	mp_static.add_theme_font_size_override("font_size", 20)
	row.add_child(mp_static)

	# MP progress bar.
	var mp_bar = ProgressBar.new()
	mp_bar.name = "MPBar"
	mp_bar.max_value = member.max_mp
	mp_bar.value     = member.current_mp
	mp_bar.show_percentage = false
	mp_bar.custom_minimum_size = Vector2(160, 24)
	mp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mp_bar)

	# Numeric MP readout.
	var mp_lbl = Label.new()
	mp_lbl.name = "MPLabel"
	mp_lbl.text = "%d / %d" % [member.current_mp, member.max_mp]
	mp_lbl.custom_minimum_size = Vector2(120, 0)
	mp_lbl.add_theme_font_size_override("font_size", 20)
	row.add_child(mp_lbl)

	return row

# Briefly tints the named party row red (Color(1, 0.3, 0.3)) then fades it back
# to white using a Tween. Called when an enemy attack lands on that member.
func _flash_party_row_red(member_name):
	if not _party_row_map.has(member_name):
		return

	var row = _party_row_map[member_name]

	# Create a one-shot Tween attached to this node so it is automatically freed
	# when the node leaves the tree. TransitionType.EASE_IN gives a sharp flash.
	var tween = create_tween()
	# Jump to red immediately.
	tween.tween_property(row, "modulate", Color(1.0, 0.3, 0.3, 1.0), 0.0)
	# Fade back to normal white over 0.4 seconds.
	tween.tween_property(row, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4)

# Displays the damage number at a fixed position over the enemy area, then
# animates it floating upward and fading out using a Tween.
func _show_damage_number(amount):
	damage_label.text    = str(amount)
	damage_label.visible = true
	# Reset modulate so the label is fully opaque at the start of each new hit.
	damage_label.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# BUG FIX: Reset position.y to the origin recorded in _ready() before starting
	# the tween. Without this, each call reads the already-drifted position.y and
	# animates 24 px above THAT, so the label moves further and further up the
	# screen with every hit until it drifts out of the visible area entirely.
	damage_label.position.y = _damage_label_origin_y

	# Create a fresh Tween to avoid conflicts if damage fires in rapid succession.
	var tween = create_tween()
	# Drift the label upward by 24 pixels over 0.6 seconds.
	tween.tween_property(damage_label, "position:y", _damage_label_origin_y - 24.0, 0.6)
	# Simultaneously fade alpha to 0.
	tween.parallel().tween_property(damage_label, "modulate:a", 0.0, 0.6)
	# Hide the label when the animation completes.
	tween.tween_callback(func(): damage_label.visible = false)

# ------------------------------------------------------------------------------
# Private: Action menu navigation helpers
# ------------------------------------------------------------------------------

# Moves the action cursor by (row_delta, col_delta) within the 2x2 grid.
# Clamps at the edges — no wrapping. If the destination button is disabled,
# the move is cancelled and the cursor stays where it is.
func _action_move(row_delta, col_delta):
	var new_row = clamp(_action_row + row_delta, 0, 1)
	var new_col = clamp(_action_col + col_delta, 0, 1)
	var new_index = new_row * 2 + new_col

	# Don't land on a disabled button — stay put instead.
	if _action_buttons[new_index].disabled:
		return

	_action_row = new_row
	_action_col = new_col
	_action_focus_index = new_index
	_action_buttons[_action_focus_index].grab_focus()

# Resets the grid cursor to row 0, col 0 (Attack) at the start of each turn,
# skipping to the next enabled button if Attack were ever disabled.
func _update_action_focus():
	# Find the first enabled button scanning left-to-right, top-to-bottom.
	for i in range(_action_buttons.size()):
		if not _action_buttons[i].disabled:
			_action_focus_index = i
			_action_row = i / 2
			_action_col = i % 2
			break
	_action_buttons[_action_focus_index].grab_focus()

# ------------------------------------------------------------------------------
# Private: Item sub-panel helpers
# ------------------------------------------------------------------------------

# Builds the item sub-panel from GameState.inventory and reveals it.
# Called when the player selects "Item" from the action menu.
func _open_item_panel():
	# Remove any buttons from a previous open so we always reflect the current
	# inventory without stale entries.
	for child in item_list_container.get_children():
		child.queue_free()
	_item_buttons.clear()

	var inventory = GameState.inventory
	if inventory.is_empty():
		# Show a disabled placeholder so the panel is not confusingly blank.
		var empty_lbl = Label.new()
		empty_lbl.text = "(No items)"
		item_list_container.add_child(empty_lbl)
	else:
		for entry in inventory:
			var btn = Button.new()
			btn.text = "%s  x%d" % [entry["item_id"], entry["quantity"]]
			# Bind the item_id so the handler knows what was selected.
			btn.pressed.connect(_on_item_button_pressed.bind(entry["item_id"]))
			btn.focus_mode = Control.FOCUS_ALL
			item_list_container.add_child(btn)
			_item_buttons.append(btn)

	item_panel.visible = true
	_item_focus_index  = 0

	# Focus the first item button immediately for gamepad navigation.
	if _item_buttons.size() > 0:
		_item_buttons[0].grab_focus()

# Called when the player presses an item button. Closes the sub-panel, emits the
# item_selected signal, and calls the BattleManager to apply the item effect.
func _on_item_button_pressed(item_id):
	item_panel.visible = false
	action_menu.visible = false
	emit_signal("item_selected", item_id)

	# TODO: Add target-selection so the player can choose which party member to
	# heal. For now we always target index 0 (the first/lead party member).
	if _battle_manager != null:
		_battle_manager.player_use_item(item_id, 0)

# ------------------------------------------------------------------------------
# Private: Action button pressed handlers
# ------------------------------------------------------------------------------

# Called when the Attack button is pressed (mouse, keyboard, or gamepad).
func _on_btn_attack_pressed():
	action_menu.visible = false
	emit_signal("action_selected", "attack")

	# TODO: Add enemy-selection UI when multiple enemies are supported.
	# For now we always target enemy index 0, the only enemy on screen.
	if _battle_manager != null:
		_battle_manager.player_attack(0)

# Called when the Item button is pressed.
func _on_btn_item_pressed():
	# Don't hide the action menu yet — the item panel layers on top.
	# The menu hides when the player confirms an item or cancels back.
	_open_item_panel()
	emit_signal("action_selected", "item")

# Called when the Run button is pressed.
func _on_btn_run_pressed():
	action_menu.visible = false
	emit_signal("action_selected", "run")

	if _battle_manager != null:
		_battle_manager.player_run()

# ------------------------------------------------------------------------------
# Input — keyboard / gamepad navigation
# ------------------------------------------------------------------------------

# Polls input every frame for action-menu and item-panel navigation.
# ui_cancel in the item panel is intentionally NOT handled here — it is handled
# in _unhandled_input() instead so the event is consumed and the battle-scene
# escape hatch (_unhandled_input in battle_scene.gd) never also fires, which
# would incorrectly exit the battle when the player just wanted to close the
# item panel.
func _process(_delta):
	# Only process input while the action menu OR item panel is open and visible.
	if not visible:
		return

	if action_menu.visible and not item_panel.visible:
		# 2D grid navigation — no wrapping, all four directions.
		# ui_accept is intentionally NOT handled here; the focused Button fires
		# its own pressed signal natively, and intercepting it here too would
		# call player_attack() twice on the same frame.
		if Input.is_action_just_pressed("ui_down"):
			_action_move(1, 0)
		elif Input.is_action_just_pressed("ui_up"):
			_action_move(-1, 0)
		elif Input.is_action_just_pressed("ui_right"):
			_action_move(0, 1)
		elif Input.is_action_just_pressed("ui_left"):
			_action_move(0, -1)

	elif item_panel.visible and _item_buttons.size() > 0:
		# Navigation only — same reason as above; item button pressed is handled
		# natively by Godot when the button has focus.
		if Input.is_action_just_pressed("ui_down"):
			_item_focus_index = (_item_focus_index + 1) % _item_buttons.size()
			_item_buttons[_item_focus_index].grab_focus()
		elif Input.is_action_just_pressed("ui_up"):
			_item_focus_index = (_item_focus_index - 1 + _item_buttons.size()) % _item_buttons.size()
			_item_buttons[_item_focus_index].grab_focus()


# Handles ui_cancel for the item sub-panel. Using _unhandled_input (rather than
# polling via Input.is_action_just_pressed in _process) allows us to call
# get_viewport().set_input_as_handled(), which marks the event consumed so that
# battle_scene.gd's _unhandled_input never also receives it. Without this, pressing
# Cancel to close the item panel would simultaneously exit the entire battle.
func _unhandled_input(event):
	# BUG FIX: item-panel cancel must consume the event so battle_scene.gd's
	# _unhandled_input (which calls return_to_overworld on ui_cancel) never fires
	# while the item panel is open.
	if item_panel.visible and event.is_action_pressed("ui_cancel"):
		item_panel.visible = false
		_update_action_focus()
		# Mark the event handled so no other node's _unhandled_input receives it.
		get_viewport().set_input_as_handled()
