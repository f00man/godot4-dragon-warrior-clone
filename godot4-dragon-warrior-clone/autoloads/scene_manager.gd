# ==============================================================================
# scene_manager.gd
# Part of: godot4-dragon-warrior-clone
# Description: Handles all scene transitions with a fade-to-black effect.
#              Owns a CanvasLayer + ColorRect overlay that always renders on
#              top of game content so the fade works regardless of which scene
#              is active. Tracks previous_scene_path to support transition_back().
# Attached to: Autoload (SceneManager)
# ==============================================================================

extends Node

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------

# Emitted the moment a transition begins (overlay starts fading to black).
# Useful for disabling player input during the transition.
signal transition_started(target_scene_path)

# Emitted after the new scene has loaded and the overlay has fully faded out.
# Useful for re-enabling player input or triggering intro sequences.
signal transition_finished(new_scene_path)

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------

# Duration in seconds for each half of the fade (fade-out and fade-in separately).
# Total visible blackout time is roughly FADE_DURATION * 2.
const FADE_DURATION = 0.4

# CanvasLayer render order. 100 keeps the overlay above all in-game content
# (typical game layers use values well below 100) without conflicting with
# OS-level overlays or Godot's own debug panels.
const OVERLAY_CANVAS_LAYER = 100

# ------------------------------------------------------------------------------
# Private state
# ------------------------------------------------------------------------------

# The CanvasLayer node that parents the overlay, created in _ready().
# Lives on SceneManager itself so it persists across all scene changes.
var _canvas_layer = null

# The full-screen black ColorRect used as the fade overlay.
var _overlay = null

# Path of the scene that was active before the most recent transition.
# Populated at the start of transition_to() so transition_back() knows
# where to return. Empty string if no transition has occurred yet.
var _previous_scene_path = ""

# Path of the scene currently loaded. Kept in sync with GameState.current_scene
# so SceneManager is the authoritative source during a transition.
var _current_scene_path = ""

# Guard flag — prevents a second transition from starting while one is already
# running. Without this, rapid calls could stack tweens and corrupt state.
var _is_transitioning = false

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Build the persistent fade overlay. Adding it to SceneManager (an autoload)
	# means it survives every change_scene_to_file() call without being
	# re-created or freed.
	_build_overlay()

	# Seed _current_scene_path from GameState so get_current_scene() is
	# accurate even before the first explicit transition.
	_current_scene_path = GameState.current_scene

# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

# Fades the screen to black, replaces the active scene with `scene_path`,
# then fades back in. Safe to await:
#
#   await SceneManager.transition_to("res://scenes/towns/riverkeep.tscn")
#
# Callers that don't need to wait for completion can call it without await.
# Does nothing if a transition is already in progress (logs a warning).
func transition_to(scene_path):
	# Block re-entrant calls — only one transition may run at a time
	if _is_transitioning:
		push_warning("SceneManager.transition_to: transition already in progress, ignoring call to '%s'" % scene_path)
		return

	_is_transitioning = true

	# Remember where we came from so transition_back() can return here
	_previous_scene_path = _current_scene_path

	emit_signal("transition_started", scene_path)

	# --- Phase 1: Fade to black ---
	await _fade_to_black()

	# --- Phase 2: Swap the scene ---
	# change_scene_to_file queues the swap; it takes effect at the start of
	# the next process frame, so we must await a frame before fading back in.
	var err = get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("SceneManager.transition_to: change_scene_to_file failed (error %d) for path '%s'" % [err, scene_path])
		# Even on failure, fade back in so the player isn't stuck on black
		await _fade_from_black()
		_is_transitioning = false
		return

	# Wait one frame so Godot can finish loading and initializing the new scene
	await get_tree().process_frame

	# Update internal path tracking now that the scene has actually changed
	_current_scene_path = scene_path
	GameState.set_current_scene(scene_path)

	# --- Phase 3: Fade back in ---
	await _fade_from_black()

	_is_transitioning = false
	emit_signal("transition_finished", scene_path)

# Returns to the scene that was active before the most recent transition_to()
# call. Does nothing if there is no previous scene (e.g. at game start).
# Safe to await, same as transition_to().
func transition_back():
	if _previous_scene_path == "":
		push_warning("SceneManager.transition_back: no previous scene to return to")
		return

	# transition_to() will overwrite _previous_scene_path with the current path,
	# so capture it before the call in case the caller wants to chain back further.
	var destination = _previous_scene_path
	await transition_to(destination)

# Returns the resource path of the scene that is currently loaded.
# Delegates to the internal tracking variable rather than GameState so
# callers get the correct value even mid-transition (GameState is only
# updated after the new scene has fully loaded).
func get_current_scene():
	return _current_scene_path

# Returns true while a fade/transition is in progress. Use this to guard
# player input or other systems that shouldn't run during a scene swap.
func is_transitioning():
	return _is_transitioning

# ------------------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------------------

# Creates the CanvasLayer and ColorRect overlay nodes and attaches them to
# this autoload. Called once in _ready(). The overlay starts fully transparent
# so it has no visible effect until a transition begins.
func _build_overlay():
	# The CanvasLayer ensures the overlay renders above all scene content.
	# Setting layer to OVERLAY_CANVAS_LAYER pushes it above typical game UI.
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = OVERLAY_CANVAS_LAYER
	_canvas_layer.name = "FadeCanvasLayer"
	add_child(_canvas_layer)

	# The ColorRect fills the entire viewport and acts as the black fade surface.
	_overlay = ColorRect.new()
	_overlay.name = "FadeOverlay"
	_overlay.color = Color.BLACK

	# PRESET_FULL_RECT anchors all four edges to the viewport edges so the
	# overlay covers the screen at any resolution without manual sizing.
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Start fully transparent — the overlay is invisible until we tween it.
	_overlay.modulate.a = 0.0

	# Mouse filter IGNORE prevents the invisible overlay from eating input
	# clicks during normal gameplay.
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_canvas_layer.add_child(_overlay)

# Tweens the overlay from transparent to fully opaque (fade to black).
# Returns when the tween is complete. Always awaited by transition_to().
func _fade_to_black():
	var tween = create_tween()
	# Ease in so the fade starts gently — less jarring than a linear cut
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(_overlay, "modulate:a", 1.0, FADE_DURATION)
	await tween.finished

# Tweens the overlay from fully opaque back to transparent (fade in).
# Returns when the tween is complete. Always awaited by transition_to().
func _fade_from_black():
	var tween = create_tween()
	# Ease out so the new scene reveals smoothly
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(_overlay, "modulate:a", 0.0, FADE_DURATION)
	await tween.finished
