# ==============================================================================
# save_screen.gd
# Part of: godot4-dragon-warrior-clone
# Description: Stub save/load selection screen. Will be replaced with a full
#              3-slot save screen implementation. For now just shows a
#              placeholder label and returns to the main menu on ui_cancel.
# Attached to: Node2D (SaveScreen)
# ==============================================================================

extends Node2D


func _ready():
	# Nothing to initialize in the stub.
	pass


func _unhandled_input(event):
	# Listen for the cancel action so the player can return to the main menu
	# without any save slot logic needing to exist yet.
	if event.is_action_pressed("ui_cancel"):
		# Return to the main menu. Uses transition_back() so SceneManager
		# handles the fade and history correctly.
		SceneManager.transition_back()
