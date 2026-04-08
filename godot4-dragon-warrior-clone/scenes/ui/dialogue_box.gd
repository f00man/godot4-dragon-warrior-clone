# ==============================================================================
# dialogue_box.gd
# Part of: godot4-dragon-warrior-clone
# Description: Reusable dialogue panel. Displays speaker name and scrolling
#              typewriter text. Supports multiple pages and branching choices.
#              Instanced into any scene that needs dialogue (towns, events, etc.)
#              Connects to EventManager signals so events can drive it remotely.
# Attached to: Control (DialogueBox)
# ==============================================================================

extends Control

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------

# Emitted when the last page is dismissed and no choices remain.
# Listeners can use this to return control to the player, close menus, etc.
signal dialogue_closed()

# Emitted when the player selects one of the branching choices.
# choice_index is a zero-based index into the choices array passed to show_dialogue().
# EventManager listens to this to determine which outcomes to apply.
signal choice_made(choice_index)

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------

# Delay in seconds between each revealed character in typewriter mode.
# Lower numbers mean faster text.
const TYPEWRITER_SPEED = 0.04

# ---------------------------------------------------------------------------
# Panel sizing and positioning constants
# ---------------------------------------------------------------------------

# Width of the floating dialogue panel in screen pixels.
const PANEL_W = 640.0

# Height of the floating dialogue panel in screen pixels.
const PANEL_H = 200.0

# Gap between the speaking entity's sprite edge and the nearest panel edge.
const PANEL_GAP = 20.0

# Minimum distance the panel must keep from any screen edge.
const SCREEN_MARGIN = 16.0

# Half the screen-space height of a standard entity sprite.
# Tiles are 32px world; at Camera2D zoom=4 they render as 128px on screen.
# Half of that is 64px — used to find the top/bottom edge of the sprite.
const ENTITY_HALF_H = 64.0

# Half a tile in world space. Added to global_position (which is the node
# origin / top-left corner) to get the rough world-space center of the sprite.
const TILE_HALF = 16.0

# ------------------------------------------------------------------------------
# Node References
# ------------------------------------------------------------------------------

# The Panel that contains all dialogue UI. Its position and size are set at
# runtime by the positioning helpers below based on the speaking entity's
# screen location.
@onready var panel = $Panel

# The speaker name header — e.g. "Hero", "Narrator", "Village Elder".
# Hidden when the caller passes an empty string for the speaker.
@onready var speaker_label = $Panel/VBox/SpeakerLabel

# The main text area where dialogue content appears character by character.
@onready var text_label = $Panel/VBox/TextLabel

# Small "▼" label shown at the bottom-right when the player must press accept
# to advance to the next page or to close the box after the final page.
@onready var continue_indicator = $Panel/ContinueIndicator

# VBoxContainer that holds dynamically-created choice Buttons.
# Hidden by default; only shown when the final page has choices attached.
@onready var choices_container = $Panel/VBox/ChoicesContainer

# One-shot timer that fires each typewriter tick. Using a Timer node rather
# than accumulating delta in _process keeps the tick interval consistent and
# independent of frame rate variations.
@onready var typewriter_timer = $TypewriterTimer

# ------------------------------------------------------------------------------
# State
# ------------------------------------------------------------------------------

# The complete text string for the page currently being displayed.
# The typewriter effect reveals characters from this string one at a time.
var _full_text = ""

# How many characters of _full_text have been revealed so far on this page.
# When _displayed_chars == _full_text.length() the page is fully shown.
var _displayed_chars = 0

# True while the typewriter is still ticking and has not finished the current page.
# Used to distinguish "skip to end of page" from "advance to next page" on accept.
var _is_printing = false

# Queue of text strings waiting to be shown, one per dialogue screen.
# pop_front() is called each time a page is fully read and the player advances.
var _pages = []

# The current set of choice strings to present after the final page.
# An empty array means no choices — the box closes directly after the last page.
var _choices = []

# True when the current page is fully revealed and the box is waiting for the
# player to press accept. Guards against double-advancing on the same frame.
var _waiting_for_input = false

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Keep this node (and its children) processing even when the scene tree is
	# paused. show_dialogue() pauses the tree to freeze player movement and NPCs;
	# PROCESS_MODE_ALWAYS ensures our timer, _process, and input still run.
	# Same pattern used by PauseMenu.
	process_mode = PROCESS_MODE_ALWAYS

	# Start hidden — callers show us explicitly via show_dialogue().
	visible = false

	# The continue indicator only appears when the player needs to act.
	continue_indicator.visible = false

	# The choices panel is built dynamically; hide it until choices are ready.
	choices_container.visible = false

	# Route each timer timeout to the typewriter tick handler.
	typewriter_timer.timeout.connect(_on_typewriter_tick)

	# Connect to EventManager so events can trigger this dialogue box remotely
	# without a direct node reference. Any scene that instances DialogueBox will
	# automatically start receiving event dialogue requests as soon as _ready() fires.
	EventManager.dialogue_requested.connect(_on_event_dialogue_requested)

# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

# Main entry point. Call this to begin showing a dialogue sequence.
#
# speaker       — String. Name shown above the text. Pass "" to hide the speaker label.
# pages_array   — Array of Strings. Each string is one full screen of text.
# choices_array — Array of Strings (optional). Shown as buttons after the last page.
#                 Pass [] for plain dialogue with no branching.
# world_pos     — Vector2 (optional). The global_position of the speaking entity in
#                 world coordinates. The panel will appear above or below the entity
#                 based on its screen location, flipping sides to stay on-screen.
#                 Pass null (default) to use the fallback bottom-center position.
func show_dialogue(speaker, pages_array, choices_array = [], world_pos = null):
	# Store the full page queue and choices so _show_next_page() can consume them.
	_pages = pages_array.duplicate()  # Duplicate so we don't mutate the caller's array.
	_choices = choices_array.duplicate()

	# Show or hide the speaker header depending on whether a name was supplied.
	if speaker == "":
		speaker_label.visible = false
	else:
		speaker_label.visible = true
		speaker_label.text = speaker

	# Position the panel before making it visible so there is no single-frame
	# flash at the wrong location. World_pos drives smart placement; null falls
	# back to a bottom-center bar so event dialogue still looks clean.
	if world_pos != null:
		_position_panel_near(world_pos)
	else:
		_position_panel_default()

	# Freeze gameplay so the player and NPCs cannot move while dialogue is open.
	# The DialogueBox has PROCESS_MODE_ALWAYS so it keeps ticking despite the pause.
	get_tree().paused = true

	# Make the box visible after positioning so the first frame is correct.
	visible = true

	# Begin displaying the first page of dialogue.
	_show_next_page()

# Immediately hides the dialogue box and stops any in-progress typewriter animation.
# Use this for hard interrupts (e.g. battle starting, scene transition) where the
# normal advance-to-close flow isn't appropriate.
func hide_dialogue():
	# Unpause on forced close (e.g. battle starting mid-conversation) so the
	# game doesn't get stuck in a permanently paused state.
	get_tree().paused = false
	visible = false
	_is_printing = false
	typewriter_timer.stop()

# ------------------------------------------------------------------------------
# Private: Panel Positioning
# ------------------------------------------------------------------------------

# Positions the panel near a world-space entity so dialogue reads as coming
# from that character. Prefers placing above the entity; falls back to below
# when the entity is too close to the top of the screen.
func _position_panel_near(world_pos):
	# get_canvas_transform() returns the viewport's canvas transform, which
	# maps world coordinates to screen coordinates. It accounts for Camera2D
	# position and zoom, so world_pos fed through it gives the correct screen pixel.
	var canvas_tf = get_viewport().get_canvas_transform()

	# Shift the world position to the approximate visual center of the entity's
	# sprite tile (node origins are typically at the top-left corner of the tile).
	var sprite_center_world = world_pos + Vector2(TILE_HALF, TILE_HALF)
	var screen_center = canvas_tf * sprite_center_world

	var viewport_size = get_viewport_rect().size

	# --- Vertical placement ---
	# Attempt above: panel bottom sits PANEL_GAP pixels above the sprite top edge.
	# ENTITY_HALF_H is the sprite's half-height in screen pixels (32px * zoom=4 / 2).
	var y_above = screen_center.y - ENTITY_HALF_H - PANEL_GAP - PANEL_H

	var pos_y
	if y_above >= SCREEN_MARGIN:
		# There is room above — prefer it so the sprite stays fully visible.
		pos_y = y_above
	else:
		# Too close to the top edge — flip the panel below the entity instead.
		pos_y = screen_center.y + ENTITY_HALF_H + PANEL_GAP

	# Guard the bottom edge so the panel never slides off the bottom of the screen.
	pos_y = min(pos_y, viewport_size.y - PANEL_H - SCREEN_MARGIN)

	# --- Horizontal placement ---
	# Centre the panel on the entity's screen X, then clamp both edges in.
	var pos_x = screen_center.x - PANEL_W / 2.0
	pos_x = clamp(pos_x, SCREEN_MARGIN, viewport_size.x - PANEL_W - SCREEN_MARGIN)

	_apply_panel_rect(pos_x, pos_y)


# Fallback placement used when no world position is available (e.g. JSON-driven
# events). Centres the panel horizontally at the bottom of the screen — a
# classic JRPG dialogue bar layout.
func _position_panel_default():
	var viewport_size = get_viewport_rect().size
	var pos_x = (viewport_size.x - PANEL_W) / 2.0
	var pos_y = viewport_size.y - PANEL_H - SCREEN_MARGIN
	_apply_panel_rect(pos_x, pos_y)


# Writes position and size to the Panel node by clearing its anchors and
# directly assigning the four offset edges. Clearing anchors first is required
# because the .tscn sets anchors to the bottom of the parent — leaving them in
# place would fight the offset values we're writing here.
func _apply_panel_rect(x, y):
	# Remove all anchor offsets so the offsets below are interpreted as absolute
	# positions relative to the parent's top-left corner (0, 0 = screen origin
	# inside the CanvasLayer).
	panel.anchor_left   = 0.0
	panel.anchor_top    = 0.0
	panel.anchor_right  = 0.0
	panel.anchor_bottom = 0.0

	# Set the four edges of the panel. With anchors zeroed out, offset_left and
	# offset_top define the top-left corner; offset_right and offset_bottom define
	# the bottom-right corner (not the margin — the absolute screen coordinate).
	panel.offset_left   = x
	panel.offset_top    = y
	panel.offset_right  = x + PANEL_W
	panel.offset_bottom = y + PANEL_H


# ------------------------------------------------------------------------------
# Private: Page Flow
# ------------------------------------------------------------------------------

# Advances to the next page in the queue, or moves to choices/close when the
# queue is empty. Called by show_dialogue() for the first page, and by _process
# when the player presses accept on a fully-revealed page.
func _show_next_page():
	if _pages.is_empty():
		# No more pages left. If choices are waiting, show them now.
		# Otherwise close the box — the conversation is over.
		if not _choices.is_empty():
			_show_choices()
		else:
			# Unpause before hiding so the player regains control the same frame
			# the box disappears, with no visible gap.
			get_tree().paused = false
			emit_signal("dialogue_closed")
			visible = false
		return

	# Pop the next page off the front of the queue and start revealing it.
	_full_text = _pages.pop_front()
	text_label.text = ""
	_displayed_chars = 0
	_is_printing = true
	_waiting_for_input = false
	continue_indicator.visible = false

	# Kick off the first typewriter tick. Each tick adds one character, then
	# re-starts the timer for the next tick until the page is fully revealed.
	typewriter_timer.start(TYPEWRITER_SPEED)

# Called every TYPEWRITER_SPEED seconds. Reveals one additional character of the
# current page and re-starts the timer. When the last character is shown, switches
# the box to "waiting for input" mode and shows the continue indicator if appropriate.
func _on_typewriter_tick():
	if _displayed_chars < _full_text.length():
		# Reveal the next character by slicing from the left of the full string.
		_displayed_chars += 1
		text_label.text = _full_text.left(_displayed_chars)
		# Schedule the next tick to continue the animation.
		typewriter_timer.start(TYPEWRITER_SPEED)
	else:
		# All characters are now visible — the page is fully revealed.
		_is_printing = false
		_waiting_for_input = true

		# Show the ▼ indicator only if there are more pages to read, or if
		# we're about to close (no choices follow). If choices are coming next,
		# the indicator would be misleading since the player selects rather than
		# advances.
		continue_indicator.visible = _pages.size() > 0 or _choices.is_empty()

# ------------------------------------------------------------------------------
# Private: Choice Presentation
# ------------------------------------------------------------------------------

# Clears any previous choice buttons, builds new ones from _choices, and
# shows the choices_container. Focuses the first button so keyboard/gamepad
# navigation works immediately without requiring a mouse click.
func _show_choices():
	# Remove any buttons left over from a previous dialogue sequence.
	for child in choices_container.get_children():
		child.queue_free()

	# Create one Button per choice string, connecting each to the selection handler
	# with its index bound so we know which choice was made.
	for i in range(_choices.size()):
		var btn = Button.new()
		btn.text = _choices[i]
		# bind(i) captures the current value of i, not a reference to the loop var.
		btn.pressed.connect(_on_choice_selected.bind(i))
		choices_container.add_child(btn)

	choices_container.visible = true

	# Focus the first choice button so the player can navigate immediately
	# with keyboard or gamepad without needing to click with a mouse.
	if choices_container.get_child_count() > 0:
		choices_container.get_child(0).grab_focus()

# Called when a choice Button is pressed. Collapses the choice UI, emits the
# result signals, and hides the dialogue box.
func _on_choice_selected(index):
	# Hide the choices panel so it doesn't linger if the dialogue box is reused.
	choices_container.visible = false
	_choices = []

	# Unpause before hiding so the player regains control the same frame the
	# box disappears.
	get_tree().paused = false

	# Emit both signals: choice_made tells EventManager which branch to take,
	# dialogue_closed notifies any other listener that the conversation is over.
	emit_signal("choice_made", index)
	emit_signal("dialogue_closed")

	visible = false

# ------------------------------------------------------------------------------
# Input Handling
# ------------------------------------------------------------------------------

# Polls Input directly every frame to bypass Godot's Viewport GUI event routing.
# When a Button inside choices_container has focus, Godot's GUI system may consume
# ui_accept before _input or _unhandled_input see it — polling Input.is_action_just_pressed
# in _process avoids this. This matches the same pattern used in main_menu.gd.
func _process(_delta):
	# Do nothing if the box isn't visible — avoid stealing input from other systems.
	if not visible:
		return

	if Input.is_action_just_pressed("ui_accept"):
		if _is_printing:
			# Typewriter is mid-animation. Skip to the end of the current page
			# instantly so the player isn't forced to wait for slow text.
			_displayed_chars = _full_text.length()
			text_label.text = _full_text
			typewriter_timer.stop()
			_is_printing = false
			_waiting_for_input = true
			# Show the ▼ indicator so the player knows to press accept again to advance.
			continue_indicator.visible = true

		elif _waiting_for_input and not choices_container.visible:
			# Page is fully revealed and we're not showing choices yet.
			# Advance to the next page (or close/show choices if queue is empty).
			_waiting_for_input = false
			_show_next_page()

# ------------------------------------------------------------------------------
# EventManager Signal Handler
# ------------------------------------------------------------------------------

# Called by EventManager when an event wants to show dialogue through this box.
# Any DialogueBox instanced in the current scene receives this automatically
# because the connection is made in _ready() via the autoload signal.
#
# speaker  — String. Speaker name to display (or "" for narrator-style with no name).
# pages    — Array of Strings. Pre-split page list from the event JSON dialogue array.
# choices  — Array of Strings. Choice texts to present after the final page.
func _on_event_dialogue_requested(speaker, pages, choices, world_pos):
	# world_pos may be null (for JSON-driven events) or a Vector2 (for NPC/chest
	# interactions). show_dialogue handles both cases.
	show_dialogue(speaker, pages, choices, world_pos)
