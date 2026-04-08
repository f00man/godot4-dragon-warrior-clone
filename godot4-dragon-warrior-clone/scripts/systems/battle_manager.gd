# ==============================================================================
# battle_manager.gd
# Part of: godot4-dragon-warrior-clone
# Description: Drives the turn-based battle system. Manages party vs. enemy
#              turn order, damage calculation, victory/defeat conditions, and
#              XP/gold awards. Round-based: all party members act first (player
#              chooses each action), then all enemies auto-attack.
# Attached to: Node (BattleManager) as child of BattleScene
# ==============================================================================

extends Node

# ------------------------------------------------------------------------------
# Signals — declared first per project convention. The UI-MENUS agent connects
# to these in battle_scene.gd and the HUD scripts to drive all visual updates.
# BattleManager never touches the UI directly; it only emits signals.
# ------------------------------------------------------------------------------

# Fired once when start_battle() is called. enemy_names is an Array of Strings
# so the UI can label each enemy on screen without holding EnemyData references.
signal battle_started(enemy_names)

# Fired when a party member needs the player to choose an action (Attack / Magic
# / Item / Run). The UI listens for this and displays the action menu for member_name.
signal action_needed(member_name)

# Fired whenever a hit lands. is_enemy_target = true means an enemy was struck
# (show damage on the enemy sprite); false means a party member was struck
# (show damage in the party panel).
signal damage_dealt(target_name, amount, is_enemy_target)

# Fired when a party member gains HP from an item or spell.
signal member_healed(member_name, amount)

# Fired when an enemy's HP reaches zero. UI uses the index to remove or grey
# out that enemy's sprite. Index matches _enemies array position.
signal enemy_defeated(enemy_index)

# Fired when a party member's HP reaches zero.
signal party_member_defeated(member_name)

# Fired when the entire enemy group is wiped out. exp_gained and gold_gained
# are totals for the UI to display in a victory summary.
signal battle_won(exp_gained, gold_gained)

# Fired when the entire party is wiped out.
signal battle_lost()

# Fired when the run attempt succeeds.
signal run_succeeded()

# Fired when the run attempt fails. message is a localizable display string.
signal run_failed(message)

# General-purpose text feed for the battle message box (e.g. "Slime attacked
# Hero for 3 damage!"). The UI appends these to a scrolling log or status label.
signal battle_log(message)

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Connect to GameState's level_up_occurred signal so we can announce
	# level-ups in the battle log the moment they happen. We do this here in
	# _ready() (code-side connection) rather than in the editor so the wiring
	# is explicit and version-controlled alongside the rest of the logic.
	GameState.level_up_occurred.connect(_on_level_up)


# ------------------------------------------------------------------------------
# Private state — all runtime data lives here; EnemyData resources are never
# mutated. We copy HP into the _enemies dicts so the resource stays pristine.
# ------------------------------------------------------------------------------

# Array of PartyMemberData resources pulled from GameState.party at battle start.
# These ARE the canonical resource objects — reducing current_hp here changes
# the live party state, which is intentional (damage persists between battles).
var _party = []

# Array of dicts: { data: EnemyData, current_hp: int }
# data is the read-only EnemyData resource; current_hp is a runtime copy that
# we decrement as damage is dealt. Never write back to data.max_hp.
var _enemies = []

# Ordered list of party members who still need to act this round.
# Rebuilt at the start of each round, sorted by speed descending so faster
# members act first within the party phase.
var _party_turn_queue = []

# False until start_battle() runs; set back to false on victory, defeat, or
# escape. Guards all public action methods so nothing fires before battle begins
# or after it ends.
var _battle_active = false

# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

# Initialises all battle state and kicks off the first party turn.
# Call this from battle_scene.gd after the scene loads, passing the array of
# EnemyData resources staged in GameState.pending_battle_enemies.
func start_battle(enemy_data_array):
	_battle_active = true

	# Pull the live party from GameState. If for some reason the party is empty
	# (e.g. the battle scene was loaded directly for testing), fall back to the
	# hero resource so we always have at least one combatant and the system
	# doesn't crash.
	_party = GameState.party
	if _party.is_empty():
		push_warning("BattleManager.start_battle: GameState.party is empty — loading hero.tres as fallback")
		_party = [load("res://resources/party_members/hero.tres")]
		# Write the fallback back to GameState so the UI (and any other reader) can
		# see the party. Without this, BattleUI._build_party_rows() reads an empty
		# array and never creates HP/MP rows.
		GameState.party = _party

	# Build the enemy runtime list. We copy max_hp into current_hp so we can
	# track damage without mutating the shared EnemyData resource.
	_enemies = []
	for enemy_data in enemy_data_array:
		_enemies.append({ "data": enemy_data, "current_hp": enemy_data.max_hp })

	# Build the first round's party turn queue sorted by speed descending.
	# Faster members always act before slower ones within the party phase.
	_rebuild_party_turn_queue()

	# Tell the UI which enemies are present. We send names only — the UI is
	# responsible for loading and displaying the correct sprite from EnemyData.
	var enemy_names = _enemies.map(func(e): return e.data.enemy_name)
	emit_signal("battle_started", enemy_names)

	# Hand control to the first party member.
	_next_party_turn()


# Executes an Attack action for the currently acting party member against the
# enemy at enemy_index. Called by the UI when the player confirms an attack.
#
# Guard checks ensure nothing fires out-of-sequence (e.g. UI bug double-firing).
func player_attack(enemy_index):
	# Reject the action if the battle is not running or the index is out of range.
	if not _battle_active:
		push_warning("BattleManager.player_attack: called while battle is not active")
		return
	if enemy_index < 0 or enemy_index >= _enemies.size():
		push_warning("BattleManager.player_attack: enemy_index %d is out of range" % enemy_index)
		return

	# The acting party member is always the first entry still in the queue.
	var actor = _party_turn_queue[0]
	var enemy = _enemies[enemy_index]

	# Damage formula: ATK minus DEF plus a small random bonus (0–3).
	# Minimum 1 so a heavily armoured enemy still takes chip damage.
	# This mirrors the Dragon Warrior NES formula loosely — no fractions needed.
	var damage = max(1, actor.attack - enemy.data.defense + randi() % 4)

	# Apply damage to the runtime HP tracker (never to the resource's max_hp).
	enemy.current_hp = max(0, enemy.current_hp - damage)

	emit_signal("damage_dealt", enemy.data.enemy_name, damage, true)
	emit_signal("battle_log", "%s attacked %s for %d damage!" % [actor.member_name, enemy.data.enemy_name, damage])

	# If the enemy is dead, announce it and check if that was the last one.
	if enemy.current_hp <= 0:
		emit_signal("enemy_defeated", enemy_index)
		emit_signal("battle_log", "%s was defeated!" % enemy.data.enemy_name)

	# _check_victory returns true and ends the battle if all enemies are down.
	# Only advance the turn queue if the battle is still running.
	if not _check_victory():
		_advance_party_turn()


# Executes an Item action for the currently acting party member.
# item_id must match a filename in resources/items/ (e.g. "herb" → herb.tres).
# target_party_index is the index into _party of the member being targeted.
func player_use_item(item_id, target_party_index):
	if not _battle_active:
		push_warning("BattleManager.player_use_item: called while battle is not active")
		return

	# Attempt to load the ItemData resource. If the file doesn't exist yet,
	# warn and bail so the player can choose a different action.
	var item_resource_path = "res://resources/items/%s.tres" % item_id
	var item = load(item_resource_path)
	if item == null:
		push_warning("BattleManager.player_use_item: could not load item resource at %s" % item_resource_path)
		emit_signal("battle_log", "That item doesn't exist!")
		return

	# Verify the player actually has this item in their inventory.
	if GameState.get_item_quantity(item_id) <= 0:
		emit_signal("battle_log", "You don't have that item!")
		return

	# Validate the target index before using it.
	if target_party_index < 0 or target_party_index >= _party.size():
		push_warning("BattleManager.player_use_item: target_party_index %d is out of range" % target_party_index)
		return

	var target = _party[target_party_index]

	# Apply the item's effect based on its effect_type field.
	if item.effect_type == "heal_hp":
		# Restore HP but never exceed the member's maximum.
		var heal = item.effect_value
		target.current_hp = min(target.max_hp, target.current_hp + heal)
		emit_signal("member_healed", target.member_name, heal)

	elif item.effect_type == "heal_mp":
		# Restore MP but never exceed the member's maximum.
		var heal = item.effect_value
		target.current_mp = min(target.max_mp, target.current_mp + heal)
		# Reuse member_healed signal — UI can differentiate by context if needed.
		# A dedicated member_mp_restored signal can be added later if the UI needs it.
		emit_signal("member_healed", target.member_name, heal)

	else:
		# Unknown effect type — log it so a designer can catch the misconfiguration.
		push_warning("BattleManager.player_use_item: unknown effect_type '%s' on item '%s'" % [item.effect_type, item_id])

	# Consume one unit of the item from the inventory regardless of effect.
	GameState.remove_item(item_id, 1)

	emit_signal("battle_log", "Used %s on %s!" % [item.item_name, target.member_name])

	# Item use counts as the acting member's action for this round.
	_advance_party_turn()


# Executes a Run action for the currently acting party member.
# 50% flat chance to escape — no level scaling yet. If the attempt fails, the
# acting member's turn is consumed (they wasted it trying to flee).
func player_run():
	if not _battle_active:
		push_warning("BattleManager.player_run: called while battle is not active")
		return

	if randf() < 0.5:
		# Escape succeeded — the battle ends immediately, no rewards.
		emit_signal("run_succeeded")
		emit_signal("battle_log", "Got away safely!")
		_end_battle_escape()
	else:
		# Escape failed — the acting member's turn is still consumed.
		emit_signal("run_failed", "Couldn't escape!")
		emit_signal("battle_log", "Couldn't escape!")
		_advance_party_turn()

# ------------------------------------------------------------------------------
# Private — turn flow
# ------------------------------------------------------------------------------

# Rebuilds _party_turn_queue from alive party members, sorted by speed descending.
# Called at the start of each new round so that members who die mid-round are
# automatically excluded from the new queue next round.
func _rebuild_party_turn_queue():
	# Filter to alive members only (dead members skip their turn permanently
	# until revived — no revive mechanic exists yet, so they just sit out).
	_party_turn_queue = _party.filter(func(m): return m.is_alive())

	# Sort descending by speed so the fastest member goes first within the round.
	_party_turn_queue.sort_custom(func(a, b): return a.speed > b.speed)


# Advances to the next party member's turn, or moves to the enemy phase if all
# party members have acted this round. Skips dead members automatically.
func _next_party_turn():
	# If the queue is empty, all party members have acted — hand off to enemies.
	if _party_turn_queue.is_empty():
		_enemy_phase()
		return

	# Peek at the front of the queue. If the member died since the queue was built
	# (killed by a counter-attack or AoE that isn't in this build yet), skip them.
	while not _party_turn_queue.is_empty() and not _party_turn_queue[0].is_alive():
		_party_turn_queue.pop_front()

	# After pruning dead members, recheck whether anyone is left.
	if _party_turn_queue.is_empty():
		# Everyone in the queue is dead — check for total party defeat.
		_check_defeat()
		return

	# Signal the UI to show the action menu for this party member.
	emit_signal("action_needed", _party_turn_queue[0].member_name)


# Consumes the current party member's turn and moves to the next one.
# Called at the end of every player action (attack, item, failed run).
func _advance_party_turn():
	# Remove the member who just acted from the front of the queue.
	if not _party_turn_queue.is_empty():
		_party_turn_queue.pop_front()

	# Proceed to whoever is next (or enemy phase if queue is now empty).
	_next_party_turn()


# Runs all enemy attacks after the full party has acted. Each living enemy
# picks a random alive party member and strikes them. After all enemies act,
# checks for total party defeat. If the party survived, a new round begins.
func _enemy_phase():
	for i in range(_enemies.size()):
		var enemy = _enemies[i]

		# Only living enemies act.
		if enemy.current_hp <= 0:
			continue

		# Find all alive party members to choose from. If none are alive,
		# the defeat check below will catch it — stop attacking immediately.
		var alive_members = _party.filter(func(m): return m.is_alive())
		if alive_members.is_empty():
			break

		# Pick a random alive party member as this enemy's target.
		var target = alive_members[randi() % alive_members.size()]

		# Damage formula mirrors the player's: ATK - DEF + 0–3 random, min 1.
		var damage = max(1, enemy.data.attack - target.defense + randi() % 4)

		# Apply damage to the live PartyMemberData resource (persists after battle).
		target.current_hp = max(0, target.current_hp - damage)

		emit_signal("damage_dealt", target.member_name, damage, false)
		emit_signal("battle_log", "%s attacked %s for %d damage!" % [enemy.data.enemy_name, target.member_name, damage])

		if target.current_hp <= 0:
			emit_signal("party_member_defeated", target.member_name)

	# After every enemy has acted, check if the party was wiped out.
	_check_defeat()

	# If the battle is still running, start a fresh round.
	if _battle_active:
		_rebuild_party_turn_queue()
		_next_party_turn()

# ------------------------------------------------------------------------------
# Private — win/loss resolution
# ------------------------------------------------------------------------------

# Returns true and resolves the battle if all enemies have been defeated.
# Returns false if at least one enemy is still alive, so the caller knows
# whether to continue advancing the turn queue.
func _check_victory():
	# Check whether any enemy still has HP remaining.
	for enemy in _enemies:
		if enemy.current_hp > 0:
			return false

	# All enemies are dead — tally rewards.
	var total_exp = 0
	var total_gold = 0
	for enemy in _enemies:
		total_exp += enemy.data.experience_reward
		total_gold += enemy.data.gold_reward

	# Add gold directly to GameState. Gold is shared across the party.
	GameState.modify_gold(total_gold)

	# Award full EXP to every alive party member independently.
	# GameState.award_experience() handles the accumulation AND any resulting
	# level-ups (including multi-level jumps) so this call site stays clean.
	# Dead members do not receive XP — they sat the fight out.
	for member in _party:
		if member.is_alive():
			GameState.award_experience(member, total_exp)

	emit_signal("battle_won", total_exp, total_gold)
	emit_signal("battle_log", "Victory! Gained %d EXP and %d gold." % [total_exp, total_gold])

	_battle_active = false
	return true


# Checks whether the entire party has been wiped out and resolves defeat if so.
# Called after every enemy attack phase.
func _check_defeat():
	# If any party member is still alive, the battle continues.
	for member in _party:
		if member.is_alive():
			return

	# Every member is at 0 HP — the party has been defeated.
	emit_signal("battle_lost")
	emit_signal("battle_log", "Your party has been defeated...")

	_battle_active = false


# Terminates the battle cleanly when the player escapes. No rewards are given.
# BattleScene listens for run_succeeded and calls return_to_overworld().
func _end_battle_escape():
	# Deactivate battle state so no further actions can fire.
	_battle_active = false

# ------------------------------------------------------------------------------
# Private — level-up handler
# ------------------------------------------------------------------------------

# Receives GameState.level_up_occurred and pushes a congratulatory message into
# the battle log. This fires once per level per member during the XP award loop,
# so if a member gains two levels at once the player sees two separate messages —
# which makes each level feel like a distinct event rather than one vague notice.
# member_name is the display name String; new_level is the int level just reached.
func _on_level_up(member_name, new_level):
	emit_signal("battle_log", "Level Up! %s is now level %d!" % [member_name, new_level])
