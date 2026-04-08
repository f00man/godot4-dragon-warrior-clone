# ==============================================================================
# battle_scene.gd
# Part of: godot4-dragon-warrior-clone
# Description: Root controller for the battle scene. Owns the BattleManager
#              child node, wires its outcome signals, feeds it the queued enemies
#              from GameState, and handles the transition back to the overworld
#              on all battle-end paths (victory, defeat, escape).
# Attached to: Node2D (BattleScene) in scenes/battle/battle_scene.tscn
# ==============================================================================

extends Node2D

# BattleManager is a child Node of this scene. Using @onready keeps the
# reference tidy and avoids magic get_node() strings elsewhere in this file.
@onready var battle_manager = $BattleManager

# BattleUI lives inside UILayer (a CanvasLayer) so that anchor-based layout
# resolves against the full viewport, not the Node2D parent rect.
@onready var battle_ui = $UILayer/BattleUI


func _ready():
	print("BattleScene: battle scene loaded")

	# Mark battle active immediately on load. SaveManager checks this flag
	# before writing to disk — mid-battle state is not safely restorable.
	GameState.in_battle = true

	# Connect BattleManager outcome signals. We only need the three terminal
	# signals here; the UI-MENUS agent will wire the per-turn signals
	# (action_needed, damage_dealt, battle_log, etc.) in its own UI scripts.
	battle_manager.battle_won.connect(_on_battle_won)
	battle_manager.battle_lost.connect(_on_battle_lost)
	battle_manager.run_succeeded.connect(_on_run_succeeded)

	# Pull the enemy array staged by EncounterManager before the transition.
	# If none were queued (e.g. the scene was opened directly in the editor
	# for testing), fall back to a slime so the system always has something
	# to fight and we don't crash on an empty enemy list.
	var enemies = GameState.pending_battle_enemies
	if enemies.is_empty():
		push_warning("BattleScene: no pending_battle_enemies found — using slime fallback for testing")
		enemies = [load("res://resources/enemies/slime.tres")]

	# Clear the staging array now that we have consumed it. This prevents a
	# stale enemy list from bleeding into a subsequent battle if the player
	# somehow re-enters battle before EncounterManager sets new enemies.
	GameState.pending_battle_enemies = []

	# Wire BattleManager signals into BattleUI before calling start_battle().
	# setup() must run first so that the battle_started signal is already
	# connected when start_battle() emits it synchronously below. If setup()
	# ran after start_battle(), the initial battle_started emission would be
	# missed and the UI would never show the enemy name or refresh party HP.
	battle_ui.setup(battle_manager)

	# Hand control to BattleManager. From here all turn logic lives in that script.
	# battle_started fires here — BattleUI.setup() above ensures it is connected.
	battle_manager.start_battle(enemies)



# Called when BattleManager emits battle_won. The signal passes exp and gold
# totals but we don't need them here — BattleManager already wrote gold to
# GameState and the UI handles the victory display.
func _on_battle_won(_exp, _gold):
	# Small delay could be added here later for a victory fanfare before transitioning.
	return_to_overworld()


# Called when BattleManager emits battle_lost.
# TODO: Route to a game-over screen instead of returning to the overworld.
# For now we return to the overworld so the game doesn't hard-stop during development.
func _on_battle_lost():
	return_to_overworld()


# Called when BattleManager emits run_succeeded after a successful escape.
func _on_run_succeeded():
	return_to_overworld()


# Final common path for all battle-end conditions. Clears the battle flag and
# delegates the scene transition to SceneManager, which handles the fade and
# restores the previous scene (overworld or dungeon) via its internal history.
func return_to_overworld():
	# Clear the battle flag before transitioning so SaveManager is unblocked
	# as soon as the overworld scene is active.
	GameState.in_battle = false

	# SceneManager.transition_back() uses its own internal scene history to
	# return to wherever the player was before the encounter fired.
	SceneManager.transition_back()
