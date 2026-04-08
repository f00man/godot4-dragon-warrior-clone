# ==============================================================================
# overworld.gd
# Part of: godot4-dragon-warrior-clone
# Description: Root script for the overworld scene. On first load (or whenever
#              the TileMapLayer has no tileset) generates the full Dragon Warrior
#              placeholder overworld map in memory. Detects when the player steps
#              onto a town/castle/cave tile and fires the appropriate scene
#              transition. Random encounter checks are delegated to
#              EncounterManager on every step.
#
# MAP GENERATION:
#   The map is generated at runtime if the tileset is missing. To bake the tiles
#   into the .tscn for editing in the tilemap painter, run
#   tools/generate_overworld.gd as an EditorScript (open it in the Script editor
#   with overworld.tscn active, then click File > Run), then save the scene.
#   After baking, the runtime generation is skipped automatically.
#
# Attached to: Node2D (Overworld) in scenes/world/overworld.tscn
# ==============================================================================

@tool
extends Node2D

# ------------------------------------------------------------------------------
# Tile type indices — must match the atlas column order in _build_tileset().
# tools/generate_overworld.gd uses the same constants; keep both in sync.
# ------------------------------------------------------------------------------
const OCEAN    = 0   # impassable — deep water
const PLAINS   = 1   # walkable   — open grassland
const FOREST   = 2   # walkable   — slows movement in original game
const MOUNTAIN = 3   # impassable — rocky peaks
const SWAMP    = 4   # walkable   — damages per step in original game
const DESERT   = 5   # walkable   — slightly slower movement
const BRIDGE   = 6   # walkable   — spans ocean channels
const TOWN     = 7   # walkable   — triggers town scene transition
const CAVE     = 8   # walkable   — triggers dungeon scene transition
const CASTLE   = 9   # walkable   — triggers castle scene transition

const MAP_W = 120
const MAP_H = 120

# Internal generation buffer: _map[y][x] = tile type int.
# Populated by _generate_map() and thrown away after _apply_to_tilemap().
var _map = []

# ------------------------------------------------------------------------------
# Landmark entrance map
# Maps "x,y" tile coordinate strings to destination scene paths.
# The player is transported as soon as they step onto the tile.
# Empty string = scene not yet built; logs a warning, does not crash.
# Extend this dictionary whenever a new town/cave/dungeon scene is added.
# ------------------------------------------------------------------------------
const ENTRANCES = {
	# Castles
	"45,43":  "res://scenes/world/tantegel_throne_room.tscn",

	# Towns — all routed to town_sample until individual scenes exist
	"44,47":  "res://scenes/towns/town_sample.tscn",   # Brecconary
	"17,27":  "res://scenes/towns/town_sample.tscn",   # Garinham     (placeholder)
	"58,17":  "res://scenes/towns/town_sample.tscn",   # Kol          (placeholder)
	"92,55":  "res://scenes/towns/town_sample.tscn",   # Rimuldar     (placeholder)
	"30,89":  "res://scenes/towns/town_sample.tscn",   # Cantlin      (placeholder)
	"51,81":  "res://scenes/towns/town_sample.tscn",   # Hauksness    (placeholder)

	# Caves — empty until dungeon scenes are built
	"26,24":  "",  # Grave of Garin
	"62,22":  "",  # Mountain Cave
	"64,46":  "",  # Swamp Cave
	"26,90":  "",  # Erdrick's Cave
	"52,78":  "",  # Hauksness cave
	"87,18":  "",  # Cave of Domdora

	# Charlock — endgame destination, no scene yet
	"58,105": "",
}

# ------------------------------------------------------------------------------
# Node references
# ------------------------------------------------------------------------------

@onready var player           = $Player
@onready var encounter_manager = $EncounterManager
@onready var tilemap          = $TileMapLayer


# ==============================================================================
# LIFECYCLE
# ==============================================================================

func _ready():
	# In the Godot editor, only generate the tilemap visuals — no game logic.
	# @tool makes _ready() run when the scene is opened, so the map appears
	# immediately in the 2D view without needing to play the game first.
	# Autoloads (GameState, EventManager, etc.) are not available in editor
	# mode so every game-logic call must be guarded by this check.
	if Engine.is_editor_hint():
		if tilemap.tile_set == null:
			_generate_map()
		return

	# Runtime: generate if the tileset wasn't baked into the .tscn yet.
	if tilemap.tile_set == null:
		print("overworld: generating Dragon Warrior map …")
		_generate_map()

	# Resume playtime — the player now has control of the overworld.
	GameState.resume_playtime()

	# Collision layer/mask 1 so the player interacts with NPC Area2D zones.
	player.collision_layer = 1
	player.collision_mask  = 1

	# Route every step to GameState (position persistence) and the encounter
	# system (random battle roll). Signals keep both subsystems decoupled.
	player.player_moved.connect(_on_player_moved)
	player.player_moved.connect(encounter_manager.on_player_stepped)

	# Fire any world-flag-triggered events registered for the overworld scene.
	EventManager.check_events_for_scene("overworld")


# ==============================================================================
# SIGNAL HANDLERS
# ==============================================================================

func _on_player_moved(new_tile_pos):
	# Keep GameState position in sync on every step.
	GameState.set_location(GameState.current_scene, new_tile_pos)
	# Check whether the new tile is a registered entrance.
	_check_tile_entrance(new_tile_pos)


func _check_tile_entrance(tile_pos):
	var key = "%d,%d" % [int(tile_pos.x), int(tile_pos.y)]
	if not ENTRANCES.has(key):
		return
	var dest = ENTRANCES[key]
	if dest == "":
		push_warning("overworld: entrance at %s has no scene assigned yet" % key)
		return
	SceneManager.transition_to(dest)


# ==============================================================================
# MAP GENERATION
# Approximation of the Dragon Warrior NES overworld (120×120 tiles).
# Fills applied in order — later fills override earlier ones.
# To bake this data into overworld.tscn so it is editable in the tilemap
# painter, run tools/generate_overworld.gd as an EditorScript.
# ==============================================================================

func _generate_map():
	_init_map()
	_paint_continent()
	_paint_terrain()
	_place_landmarks()
	_paint_bridges()
	tilemap.tile_set = _build_tileset()
	_apply_to_tilemap()


# ── Buffer helpers ─────────────────────────────────────────────────────────────

func _init_map():
	_map.clear()
	for _y in range(MAP_H):
		var row = []
		for _x in range(MAP_W):
			row.append(OCEAN)
		_map.append(row)


# Fill rectangle x1,y1 (inclusive) to x2,y2 (exclusive). Clamps to map bounds.
func _fill(x1, y1, x2, y2, tile):
	for y in range(max(0, y1), min(MAP_H, y2)):
		for x in range(max(0, x1), min(MAP_W, x2)):
			_map[y][x] = tile


# Place a single tile; silently ignores out-of-bounds coordinates.
func _place(x, y, tile):
	if x >= 0 and x < MAP_W and y >= 0 and y < MAP_H:
		_map[y][x] = tile


# ── Continent shape ────────────────────────────────────────────────────────────

func _paint_continent():
	# 1. Fill large rectangular land blobs that form the main continent body.
	_fill(7,   7,  72,  90, PLAINS)   # western/central landmass
	_fill(68,  7, 115,  90, PLAINS)   # eastern landmass
	_fill(7,  87,  44, 115, PLAINS)   # southwest (Cantlin region)
	_fill(68, 87, 115, 115, PLAINS)   # southeast

	# 2. Carve ocean bays and channels into the land to shape the coastlines.
	_fill(7,  48,  24,  65, OCEAN)    # northwest bay
	_fill(7,  70,  18,  87, OCEAN)    # central-west coastal recess
	_fill(74, 42,  92,  72, OCEAN)    # eastern channel (Rimuldar strait)
	_fill(35, 93,  80, 117, OCEAN)    # southern interior sea (Charlock's domain)
	_fill(7, 100,  22, 117, OCEAN)    # southwest coast recession
	_fill(92, 98, 115, 117, OCEAN)    # southeast coast recession

	# 3. Restore islands carved out in step 2.
	_fill(91, 49, 108,  70, PLAINS)   # Rimuldar island
	_fill(51, 99,  69, 115, PLAINS)   # Charlock island
	_fill(10, 100,  19, 110, PLAINS)  # small southwest island
	_fill(105,  8, 114,  18, PLAINS)  # small northeast island


# ── Terrain overlays ───────────────────────────────────────────────────────────

func _paint_terrain():
	# --- FOREST ---
	_fill(7,  20,  33,  50, FOREST)   # northwest forest (Garinham region)
	_fill(44,  7,  74,  22, FOREST)   # northern belt (road to Kol)
	_fill(92,  7, 115,  42, FOREST)   # eastern forest
	_fill(80, 60, 115,  90, FOREST)   # southeast forest
	_fill(28, 56,  46,  74, FOREST)   # central-west scattered forest

	# --- MOUNTAIN ---
	_fill(32, 52,  44,  65, MOUNTAIN) # central-west range (barrier south of Tantegel)
	_fill(92, 38, 115,  75, MOUNTAIN) # eastern mountain spine
	_fill(60, 18,  72,  34, MOUNTAIN) # northern cluster (near cave)
	_fill(35, 88,  80,  96, MOUNTAIN) # southern interior sea shores
	_fill(51, 99,  69, 115, MOUNTAIN) # Charlock island — mostly impassable rock

	# --- SWAMP ---
	_fill(48, 74,  70,  90, SWAMP)    # south-central swamp (Hauksness area)

	# --- DESERT ---
	_fill(7,  74,  40,  96, DESERT)   # southwest desert (approach to Cantlin)

	# --- CLEAR PLAINS around each landmark zone ---
	# Each named location gets breathing room so the player can approach freely.
	_fill(38, 38,  56,  54, PLAINS)   # Tantegel / Brecconary
	_fill(52, 12,  66,  22, PLAINS)   # Kol
	_fill(11, 22,  24,  33, PLAINS)   # Garinham
	_fill(89, 48, 109,  71, PLAINS)   # Rimuldar island interior
	_fill(44, 76,  60,  88, PLAINS)   # Hauksness
	_fill(23, 84,  40,  97, PLAINS)   # Cantlin
	_fill(53, 100,  67, 113, PLAINS)  # Charlock island approach
	_fill(55, 102,  65, 111, PLAINS)  # Charlock inner zone


# ── Landmark tiles ─────────────────────────────────────────────────────────────

func _place_landmarks():
	# Castles
	_place(45, 43, CASTLE)   # Tantegel Castle
	_place(58, 105, CASTLE)  # Charlock Castle (Dragonlord's keep)

	# Towns
	_place(44, 47, TOWN)     # Brecconary  — first town, south of Tantegel
	_place(17, 27, TOWN)     # Garinham    — northwest, Silver Harp
	_place(58, 17, TOWN)     # Kol         — north, Fairy Flute
	_place(92, 55, TOWN)     # Rimuldar    — eastern island, sells Keys
	_place(30, 89, TOWN)     # Cantlin     — southwest desert, strongest shop
	_place(51, 81, TOWN)     # Hauksness   — south ruins, Armor of Erdrick nearby

	# Caves and dungeons
	_place(26, 24, CAVE)     # Grave of Garin    — northwest forest
	_place(62, 22, CAVE)     # Mountain Cave     — north, beyond Kol
	_place(64, 46, CAVE)     # Swamp Cave        — central passage
	_place(26, 90, CAVE)     # Erdrick's Cave    — southwest near Cantlin
	_place(52, 78, CAVE)     # Hauksness dungeon
	_place(87, 18, CAVE)     # Cave of Domdora   — northeast


# ── Bridges ────────────────────────────────────────────────────────────────────

func _paint_bridges():
	# East bridge — the iconic long bridge to Rimuldar (17 tiles wide)
	for x in range(74, 91):
		_place(x, 55, BRIDGE)
	# Northwest bay bridge — vertical crossing on the bay's east shore
	for y in range(48, 57):
		_place(24, y, BRIDGE)
	# Northern pass bridge — small horizontal gap near the Kol road
	for x in range(42, 46):
		_place(x, 22, BRIDGE)


# ── TileSet builder ────────────────────────────────────────────────────────────

func _build_tileset():
	# Create a 320×32 image: 10 solid-color 32×32 tiles in a single row.
	var img = Image.create(320, 32, false, Image.FORMAT_RGBA8)
	var colors = [
		Color(0.10, 0.28, 0.55, 1.0),  # 0  OCEAN     — deep blue
		Color(0.28, 0.58, 0.20, 1.0),  # 1  PLAINS    — grass green
		Color(0.08, 0.32, 0.08, 1.0),  # 2  FOREST    — dark green
		Color(0.50, 0.42, 0.32, 1.0),  # 3  MOUNTAIN  — warm gray-brown
		Color(0.20, 0.38, 0.12, 1.0),  # 4  SWAMP     — murky green
		Color(0.80, 0.70, 0.30, 1.0),  # 5  DESERT    — sandy yellow
		Color(0.55, 0.40, 0.20, 1.0),  # 6  BRIDGE    — worn wood brown
		Color(0.85, 0.80, 0.25, 1.0),  # 7  TOWN      — warm golden
		Color(0.28, 0.22, 0.18, 1.0),  # 8  CAVE      — dark earth
		Color(0.60, 0.60, 0.70, 1.0),  # 9  CASTLE    — stone blue-gray
	]
	for i in range(10):
		img.fill_rect(Rect2i(i * 32, 0, 32, 32), colors[i])
	var tex = ImageTexture.create_from_image(img)

	# No physics layer on the TileSet — terrain blocking is handled entirely
	# in player.gd via _is_tile_blocked(), which reads the atlas column index
	# of the destination tile. This avoids the TileData physics polygon API
	# (which has version-dependent method names) and is more Dragon Warrior-
	# authentic: blocking is pure tile logic, not physics simulation.
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(32, 32)

	var source = TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = Vector2i(32, 32)
	for i in range(10):
		source.create_tile(Vector2i(i, 0))

	tileset.add_source(source)
	return tileset


# ── Apply buffer to TileMapLayer ───────────────────────────────────────────────

func _apply_to_tilemap():
	tilemap.clear()
	for y in range(MAP_H):
		for x in range(MAP_W):
			# Source ID 0 = the single atlas source added in _build_tileset.
			# Atlas coord x = tile type (one row of 10 tiles in the image).
			tilemap.set_cell(Vector2i(x, y), 0, Vector2i(_map[y][x], 0))
