# ==============================================================================
# main_menu.gd
# Part of: godot4-dragon-warrior-clone
# Description: Main menu screen. Handles New Game, Continue, and Quit.
#              Checks all three save slots on load to determine whether
#              Continue should be available. Pauses playtime while active.
#              Navigation is driven manually via _process + Input.is_action_just_pressed
#              so keyboard and gamepad work regardless of Godot's GUI event-routing.
# Attached to: Control (MainMenu)
# ==============================================================================

extends Control

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------

# Emitted when the player confirms New Game. Declared here for documentation
# purposes — at this stage the handler also calls GameState and SceneManager
# directly (see NOTE in _on_new_game_pressed). If a coordinator autoload is
# added later, the signal can be wired to it instead.
signal new_game_requested

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------

# Path to the overworld scene — destination after starting a new game.
const OVERWORLD_SCENE = "res://scenes/world/overworld.tscn"

# Path to the save/load selection screen — shown when the player picks Continue.
const SAVE_SCREEN_SCENE = "res://scenes/ui/save_screen.tscn"

# ------------------------------------------------------------------------------
# Node references — resolved once at _ready, not on every access.
# ------------------------------------------------------------------------------

@onready var btn_new_game = $VBoxContainer/BtnNewGame
@onready var btn_continue = $VBoxContainer/BtnContinue
@onready var btn_quit     = $VBoxContainer/BtnQuit

# ------------------------------------------------------------------------------
# State
# ------------------------------------------------------------------------------

# Ordered list of the three menu buttons built in _ready(). Driving navigation
# through this array lets us skip disabled entries cleanly without relying on
# Godot's focus-neighbor resolution, which can silently fail on first frame.
var _menu_buttons = []

# Index into _menu_buttons for the currently highlighted button.
# 0 = New Game, 1 = Continue, 2 = Quit.
var _focused_index = 0


func _ready():
	# Player is at the menu, not playing — don't count this time against their
	# playtime. SceneManager.transition_to() will not resume it; the overworld
	# scene is responsible for calling resume_playtime() when the player gains
	# control.
	GameState.pause_playtime()

	# Build the ordered button list used by _process navigation.
	# Order matters — index 0 is the default selection shown on menu open.
	_menu_buttons = [btn_new_game, btn_continue, btn_quit]

	# Check all save slots to decide whether the Continue button should be
	# active. Must happen before we set focus so the disabled state is already
	# correct when the first grab_focus() call fires.
	_check_save_slots()

	# Connect button press signals here in code, not in the editor, so the
	# wiring is explicit and visible when reading this file.
	btn_new_game.pressed.connect(_on_new_game_pressed)
	btn_continue.pressed.connect(_on_continue_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)

	# Highlight New Game immediately. call_deferred() lets Godot finish its
	# initial layout pass before the focus request fires — calling grab_focus()
	# synchronously in _ready() can be silently dropped on the first frame.
	_focused_index = 0
	btn_new_game.grab_focus.call_deferred()


func _process(_delta):
	# Poll the Input singleton directly every frame instead of relying on the
	# event-routing pipeline. This bypasses the problem entirely: when a Button
	# has focus, Godot's Viewport GUI system consumes ui_up/ui_down during the
	# input phase and marks them handled before _input (or _unhandled_input)
	# ever fires on this node. _process runs unconditionally each frame and
	# reads from Input state, which is set before any event routing occurs.
	# is_action_just_pressed() gives us the same "one trigger per keydown"
	# behaviour that event.is_action_pressed() provided.
	if Input.is_action_just_pressed("ui_down"):
		_move_focus(1)
	elif Input.is_action_just_pressed("ui_up"):
		_move_focus(-1)
	elif Input.is_action_just_pressed("ui_accept"):
		# Confirm the currently focused button. Handled here rather than relying
		# on the Button's native _gui_input so it goes through the same pipeline
		# as navigation and isn't vulnerable to Viewport event consumption.
		# Disabled buttons are skipped — _focused_index should never point at one,
		# but the guard is here as a safety net.
		if not _menu_buttons[_focused_index].disabled:
			_menu_buttons[_focused_index].emit_signal("pressed")


# Moves the highlighted button by `direction` steps (+1 down, -1 up), wrapping
# around the list and skipping any disabled buttons automatically.
func _move_focus(direction):
	var count = _menu_buttons.size()
	# Try each subsequent index in the given direction until we find one that
	# isn't disabled. In the worst case (all but one button disabled) this still
	# terminates because we will eventually land back on the enabled button.
	for i in range(1, count + 1):
		var candidate = (_focused_index + direction * i + count * count) % count
		if not _menu_buttons[candidate].disabled:
			_focused_index = candidate
			break
	# Give keyboard focus to the newly selected button so ui_accept fires on it
	# and the visual highlight (focus style) tracks the selection correctly.
	_menu_buttons[_focused_index].grab_focus()


func _check_save_slots():
	# Loop over all three save slots and check whether any have valid save data.
	# We only need to find one populated slot to enable Continue.
	var any_save_exists = false

	for i in range(3):
		# get_slot_summary returns a dict — use .get() with a false default so
		# this works safely even if the key is missing for some reason.
		if SaveManager.get_slot_summary(i).get("exists", false):
			any_save_exists = true
			break  # No need to keep checking once we find one.

	if any_save_exists:
		# At least one save slot has data — enable the Continue button.
		btn_continue.disabled = false
	else:
		# Gray out Continue when there are no saves so the player isn't confused
		# by a button that does nothing.
		btn_continue.disabled = true


func _on_new_game_pressed():
	# Reset all game state to defaults and jump straight to the overworld.
	# NOTE: This bypasses the emit-signal pattern intentionally — there is no
	# game manager autoload to route through at this stage. The new_game_requested
	# signal is declared above for future use if a coordinator is added. This
	# deviation is documented in the task summary.
	GameState.reset_to_defaults()
	SceneManager.transition_to(OVERWORLD_SCENE)


func _on_continue_pressed():
	# Navigate to the save select screen. The button is disabled when no saves
	# exist, so this function only runs if at least one slot is populated.
	SceneManager.transition_to(SAVE_SCREEN_SCENE)


func _on_quit_pressed():
	# Exit the application. On desktop this closes the window; on Switch this
	# is handled by the OS via the platform abstraction layer.
	get_tree().quit()
