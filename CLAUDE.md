# CLAUDE.md — godot4-dragon-warrior-clone

This file tells Claude AI about the project so every coding session starts with
full context. Read this before writing any code.

---

## Project Overview

**Working Title:** godot4-dragon-warrior-clone
**Engine:** Godot 4.6.1 (standard build — GDScript only, no .NET/C#)
**Genre:** Top-down tile-based JRPG
**Inspiration:** Dragon Warrior (Dragon Quest I, NES, 1986 USA release)
**Target Platforms:** Steam (PC/Mac/Linux) and Nintendo Switch

### Core Features
- Top-down tile-based overworld and dungeon exploration
- First-person battle view (player sees enemies facing them, Dragon Warrior style)
- Turn-based combat system
- Party system (multiple party members — NOT in the original, this is an addition)
- Town ownership system (player/factions can own and manage towns)
- Dynamic event system (player choices affect world state and future events)
- Branching dialogue and NPC interactions
- Save/load system with multiple save slots

---

## Engine & Language

- **Language:** GDScript exclusively (no C#, no C++)
- **Godot Version:** 4.6.1
- **Rendering:** Use Godot's 2D renderer. Do not use 3D nodes unless explicitly asked.
- **Tilemaps:** Use `TileMapLayer` nodes (Godot 4.x style — NOT the deprecated `TileMap`)

---

## Coding Style

### General Rules
- **Comment everything.** Every function, every block of logic, every non-obvious
  variable should have a plain-English comment explaining what it does and why.
- Use comments to explain *intent*, not just *what* — bad: `# increment i`, good:
  `# Move to the next party member in the turn queue`
- Keep functions short and focused. If a function is doing more than one thing,
  split it.
- Use `snake_case` for variables and functions, `PascalCase` for class names and
  node names, `ALL_CAPS` for constants.
- Prefer explicit over implicit. If something could be ambiguous, make it clear.

### GDScript Specifics
- Do NOT use strict typing unless asked. Keep variable declarations readable:
  `var player_name = "Hero"` not `var player_name: String = "Hero"`
- Use `@export` for any value a designer might want to tweak in the Inspector
- Use `@onready` for node references: `@onready var sprite = $Sprite2D`
- Signals should be declared at the top of the file, before variables
- Connect signals in `_ready()` when possible, not in the editor

### File Header
Every `.gd` file should start with a comment block like this:
```
# ==============================================================================
# filename.gd
# Part of: godot4-dragon-warrior-clone
# Description: One or two sentences explaining what this script does.
# Attached to: [Node name or "Autoload"]
# ==============================================================================
```

---

## Project Architecture

### Autoloads (Global Singletons)
These are always in scope. Do not re-declare them as local variables.

| Autoload Name     | File                          | Purpose                                      |
|-------------------|-------------------------------|----------------------------------------------|
| `GameState`       | `autoloads/game_state.gd`     | Central truth: party, flags, world state     |
| `SaveManager`     | `autoloads/save_manager.gd`   | Save/load slots, serialization               |
| `SceneManager`    | `autoloads/scene_manager.gd`  | Scene transitions with fade effects          |
| `AudioManager`    | `autoloads/audio_manager.gd`  | BGM and SFX playback                         |
| `EventManager`    | `autoloads/event_manager.gd`  | Dynamic event system, choice/consequence     |
| `TownManager`     | `autoloads/town_manager.gd`   | Town ownership, loyalty, buildings           |

### Directory Structure
```
godot4-dragon-warrior-clone/
├── CLAUDE.md                  ← this file
├── project.godot
├── autoloads/                 ← global singletons (see table above)
├── scenes/
│   ├── world/                 ← overworld TileMapLayer scenes
│   ├── towns/                 ← individual town scenes
│   ├── dungeons/              ← dungeon scenes
│   ├── battle/                ← battle scene (first-person view)
│   ├── ui/                    ← HUD, menus, dialogue box, party screen
│   └── management/            ← town management UI screens
├── scripts/
│   ├── entities/              ← player, party members, enemies (data + logic)
│   ├── systems/               ← battle engine, encounter system, etc.
│   └── resources/             ← custom Resource definitions
├── resources/
│   ├── enemies/               ← EnemyData .tres files
│   ├── party_members/         ← PartyMemberData .tres files
│   ├── items/                 ← ItemData .tres files
│   ├── spells/                ← SpellData .tres files
│   └── towns/                 ← TownData .tres files
├── data/
│   └── events/                ← JSON files defining dynamic events
├── assets/
│   ├── sprites/
│   ├── tilesets/
│   ├── audio/
│   └── fonts/
└── addons/                    ← third-party plugins (e.g. Dialogic)
```

---

## Core Data Model

### GameState (autoload)
The single source of truth for all mutable game data. Everything that needs to
be saved lives here. Key properties:

```gdscript
# Party
var party: Array  # Array of PartyMemberData resources (max 4)
var gold: int
var playtime: float

# World flags — used by the event system to track player choices
# Example: world_flags["rescued_village_of_kale"] = true
var world_flags: Dictionary

# Town ownership
# Example: towns["riverkeep"] = { "owner": "player", "loyalty": 75, ... }
var towns: Dictionary
```

### Custom Resources
Use `class_name` Resources for all game data. Example pattern:

```gdscript
# resources/enemies/enemy_data.gd
class_name EnemyData extends Resource
@export var enemy_name: String
@export var max_hp: int
@export var attack: int
@export var defense: int
@export var sprite: Texture2D  # The front-facing battle sprite
```

---

## Battle System

- **View:** First-person. The player's party is off-screen (represented by a UI
  panel at the bottom). The enemy/enemies are displayed as large sprites facing
  the player, centered on screen — exactly like Dragon Warrior NES.
- **Turn order:** ATB-style queue OR simple player-then-enemy. Ask before
  implementing if not specified.
- **Actions per turn:** Attack, Magic/Spell, Item, Run
- **Party battles:** All active party members act before enemies (or interleaved
  by speed stat — confirm before implementing)
- **Enemy groups:** Unlike the original, support multiple enemies on screen at once
- Battle scene file: `scenes/battle/battle_scene.tscn`
- Battle manager script: `scripts/systems/battle_manager.gd`

---

## Town Ownership System

- Towns have an `owner` (player, a faction name, or "neutral")
- Towns have a `loyalty` value (0–100) that affects events, shop prices, and
  available quests
- Player can gain ownership through quests, purchase, or conquest
- Owned towns can have buildings constructed (inn, blacksmith, etc.)
- Town state is stored in `GameState.towns` and persisted via SaveManager
- Visual changes on the overworld (flag color, building sprites) should reflect
  ownership state

---

## Dynamic Event System

- Events are defined as JSON files in `data/events/`
- Each event has: trigger conditions (world_flags check), choices, and outcomes
  (which set new world_flags, modify town loyalty, add/remove party members, etc.)
- `EventManager` autoload polls for triggerable events on scene load and at
  defined trigger points
- Choices made by the player are recorded in `GameState.world_flags`
- Events can be one-time or repeatable (defined in the JSON)

Example event JSON structure:
```json
{
  "id": "bandit_camp_choice",
  "trigger": { "flag_required": "found_bandit_camp", "flag_not": "resolved_bandit_camp" },
  "description": "You discover a bandit camp near Riverkeep.",
  "choices": [
    {
      "text": "Attack the bandits",
      "outcomes": { "set_flag": "resolved_bandit_camp", "town_loyalty_delta": { "riverkeep": 15 } }
    },
    {
      "text": "Negotiate a truce",
      "outcomes": { "set_flag": "resolved_bandit_camp", "set_flag_2": "bandits_allied" }
    }
  ]
}
```

---

## What Claude Should Always Do

- **Read this file at the start of every session** before writing any code
- **Ask before inventing architecture** — if a system isn't described here, ask
  how it should work before implementing it
- **Never rename existing autoloads or change the directory structure** without
  being explicitly asked
- **Always write comments** — this is non-negotiable regardless of how simple the
  code seems
- **Prefer signals over direct node references** for cross-system communication
- **Check GameState first** — if you need data that might already live in
  GameState, use it from there rather than creating a parallel data store
- **One system at a time** — complete and comment a system fully before moving
  to the next

## What Claude Should Never Do

- Do not use C# or any language other than GDScript
- Do not use the deprecated `TileMap` node — always use `TileMapLayer`
- Do not use `get_node()` strings when `@onready` works
- Do not put game logic inside UI scripts — UI scripts only handle display and
  emit signals; logic lives in managers/autoloads
- Do not hardcode stats, names, or game data inline — all game data belongs in
  Resource files or JSON in the `data/` folder
- Do not create autoloads beyond the ones listed above without discussing it first

---

---

## Pending TODOs

Items flagged during implementation that need attention before shipping or when
the relevant system is built. Update this table as items are resolved or added.

### Resources / Data Schemas (blocking multiple systems)

| # | Item | Blocks |
|---|------|--------|
| R1 | Create `PartyMemberData` resource class (`scripts/resources/party_member_data.gd`) with fields: `member_name`, `max_hp`, `current_hp`, `max_mp`, `current_mp`, `experience`, `level`, `attack`, `defense`, `speed` | SaveManager party serialization; GameState `add_party_member` |
| R2 | Create `TownData` resource class (`scripts/resources/town_data.gd`) with display name, population, starting loyalty, faction affiliation | TownManager `get_town_summary`, `get_town` default dict |
| R3 | Create `BuildingData` resource catalogue with building ids, display names, prerequisites, loyalty thresholds, and costs | TownManager `construct_building`, `get_available_buildings` |

### SaveManager (`autoloads/save_manager.gd`)

| # | Item | Notes |
|---|------|-------|
| S1 | Replace raw-dict party deserialization with full `PartyMemberData` resource loading | In `_deserialize_into_game_state` — load `.tres` by `resource_path`, overlay saved `current_hp`/`current_mp`/`experience`/`level`. Blocked on R1. |
| S2 | Add real migration rules to `_migrate_save()` | Add `if from_version == "x.y.z":` blocks each time the save schema changes. Currently a pass-through stub. |
| S3 | Extend `_scene_path_to_label()` label map | Add an entry for each new scene as they are created. Currently only overworld and battle are mapped. |

### AudioManager (`autoloads/audio_manager.gd`)

| # | Item | Notes |
|---|------|-------|
| A1 | Configure loop on each BGM `AudioStream` resource in the editor | Looping is set per-resource in the Import tab, not in code. Every new music track needs this done or it will play once and stop. |
| A2 | Implement SFX pooling for overlapping sounds | `play_sfx()` uses a single `AudioStreamPlayer` — the second call cuts off the first. Needed for rapid hits, simultaneous UI sounds, etc. |
| A3 | Assign "Music" and "SFX" audio buses if the project adds them | Currently both players use the default bus. Update `_bgm_player.bus` and `_sfx_player.bus` in `_ready()` when the Audio layout is set up. |

### EventManager (`autoloads/event_manager.gd`)

| # | Item | Notes |
|---|------|-------|
| E1 | Implement `evaluate_condition()` | Currently returns `true` unconditionally. Needs real `flag_required`, `flag_not`, and `scene_id` checks against `GameState.has_flag()`. **Must be done before any QA pass.** |
| E2 | Implement `trigger_event()` | Needs dialogue UI integration: display description, present choices, await player selection, then call `apply_outcome()`. |
| E3 | Implement `check_events_for_scene()` | Needs iteration loop over `_events`, calling `evaluate_condition()` + `is_event_completed()` filter, then `trigger_event()` for matches. Wire up call from `SceneManager.transition_finished` signal. |
| E4 | Implement `apply_outcome()` | Needs handlers for: `set_flag`, `set_flag_2`, `town_loyalty_delta`, `add_item`, `add_party_member`, `remove_party_member`, `set_completion_flag`. `trigger_event()` must inject `event_id` into the outcome dict before calling so the completion flag key can be constructed. |

### TownManager (`autoloads/town_manager.gd`)

| # | Item | Notes |
|---|------|-------|
| T1 | Implement `set_town_owner()` | Write change to `_towns` + `GameState.set_town()`, emit `town_ownership_changed`. Add faction relationship side-effects (rival factions lose loyalty when player takes their town). **Note:** the function was renamed from `set_owner` to avoid a Godot built-in conflict — use `set_town_owner` everywhere, including any callers in other files. Also update `.claude/agents/town-world.md` to document this when implementing. |
| T2 | Implement `adjust_loyalty()` | Clamp to 0–100, write back to GameState, emit `town_loyalty_changed`. Add threshold-crossing detection: loyalty → 0 triggers revolt event; crossing 60→61 unlocks Friendly-tier quests. |
| T3 | Implement `construct_building()` | Validate: player-owned, not already built, prerequisites met (from BuildingData catalogue). On success: update `constructed_buildings`, write to GameState, emit `building_constructed`. Blocked on R3. |
| T4 | Implement `get_available_buildings()` | Filter BuildingData catalogue against: not already built, prerequisites met, player owns town, loyalty threshold met. Blocked on R3. |
| T5 | Implement `get_town_summary()` | Populate `name` from TownData resource. Blocked on R2. |
| T6 | Add threshold-check in `_on_town_data_changed()` | After cache refresh from external write, check whether any loyalty thresholds or ownership triggers should fire (same logic as T2). |

### SceneManager (`autoloads/scene_manager.gd`)

| # | Item | Notes |
|---|------|-------|
| SC1 | Consider a history stack for `transition_back()` | Currently tracks only one level of history. Nested menu flows (e.g. overworld → town → shop → item detail) may need a full stack. |
| SC2 | Wire `transition_finished` to `EventManager.check_events_for_scene()` | After each transition completes, SceneManager should notify EventManager so scene-entry events can fire. Blocked on E3. |

### Battle System (`scenes/battle/battle_scene.gd`)

| # | Item | Notes |
|---|------|-------|
| B1 | Remove `ui_cancel` escape hatch from `_unhandled_input` | Temporary test shortcut that exits battle immediately on Escape/Cancel. Lets you verify the full overworld → battle → overworld loop works before the real battle system exists — very satisfying to see end to end. Remove or gate it behind a debug flag once real battle-end conditions are implemented. |

---

## Manual Setup Required in Godot Editor

Steps that cannot be automated and must be done by hand in the Godot editor. Check this list when onboarding or setting up a fresh project clone.

### AudioStream Loop Points
BGM looping is configured on the AudioStream resource in the Godot editor, not in code. Every music file added to `assets/audio/` must have its loop mode enabled manually in the Import tab. If a BGM track plays once and stops, this is why. The AudioManager code assumes loop is already set on the resource.

*More entries will be added here as the project grows.*

---

*Last updated: 2026 — update this file as the project evolves.*
