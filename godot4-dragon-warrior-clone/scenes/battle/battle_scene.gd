# ==============================================================================
# battle_scene.gd
# Part of: godot4-dragon-warrior-clone
# Description: Skeleton battle scene script. Sets GameState.in_battle on entry
#              and exit. Full battle logic (turn order, actions, enemy AI) will
#              be implemented in scripts/systems/battle_manager.gd later.
# Attached to: Node2D (BattleScene) in scenes/battle/battle_scene.tscn
# ==============================================================================

extends Node2D


func _ready():
	print("BattleScene: battle scene loaded")

	# Mark battle active immediately on load. SaveManager checks this flag and
	# will refuse to save while it is true — mid-battle state is not safely
	# restorable.
	GameState.in_battle = true


func _unhandled_input(event):
	# Temporary escape hatch for testing the transition back to the overworld.
	# Remove or replace when the real battle end condition is implemented.
	if event.is_action_pressed("ui_cancel"):
		return_to_overworld()


# Ends the battle and returns the player to the overworld. Called by the real
# victory/defeat resolution once battle_manager.gd is implemented; for now
# it is reachable via the ui_cancel escape hatch above.
func return_to_overworld():
	# Clear the battle flag before transitioning so SaveManager is unblocked
	# as soon as the overworld loads.
	GameState.in_battle = false

	# SceneManager tracks the previous scene and handles the fade transition
	# back. EncounterManager stored the return path in _return_scene_path before
	# we got here, but transition_back() uses SceneManager's own internal history
	# so no extra coordination is needed.
	SceneManager.transition_back()
