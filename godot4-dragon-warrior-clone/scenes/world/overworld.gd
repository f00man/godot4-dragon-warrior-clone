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

# Click this button in the Inspector (with the Overworld node selected in the
# editor) to force the map to regenerate from the current generation code.
# Use this after pulling code changes — Godot caches compiled scripts and
# _ready() may not re-run automatically.
@export_tool_button("Regenerate Map") var _regen_btn = func(): _generate_map()

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
	"44,51":  "res://scenes/world/tantegel_throne_room.tscn",  # Tantegel Castle

	# Towns — all routed to town_sample until individual scenes exist
	"47,57":  "res://scenes/towns/town_sample.tscn",   # Brecconary
	"17,26":  "res://scenes/towns/town_sample.tscn",   # Garinham     (placeholder)
	"58,7":   "res://scenes/towns/town_sample.tscn",   # Kol          (placeholder)
	"95,50":  "res://scenes/towns/town_sample.tscn",   # Rimuldar     (placeholder)
	"37,103": "res://scenes/towns/town_sample.tscn",   # Cantlin      (placeholder)
	"42,73":  "res://scenes/towns/town_sample.tscn",   # Hauksness    (placeholder)

	# Caves — empty until dungeon scenes are built
	"14,30":  "",  # Grave of Garin
	"60,17":  "",  # Mountain Cave
	"63,47":  "",  # Swamp Cave
	"28,90":  "",  # Erdrick's Cave
	"45,76":  "",  # Hauksness cave
	"88,17":  "",  # Cave of Domdora

	# Charlock — endgame, no scene yet
	"57,108": "",
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
		# Always regenerate in editor mode so changes to the generation code
		# are reflected immediately when the scene is opened — no manual
		# EditorScript step required.
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
	# Continent shape based on the Dragon Warrior NES reference map.
	# Strategy: fill large land blobs, then carve ocean features into them.

	# ── 1. Northern neck leading to Kol ─────────────────────────────────────
	# A relatively thin strip of land at the very top of the map. Kol sits on
	# the north coast; the land widens as you go south toward Tantegel.
	_fill(25,  4,  72, 18, PLAINS)

	# ── 2. Northwest peninsula (Garinham region) ─────────────────────────────
	# A prominent western peninsula separated from the main continent by a
	# large bay. Connected on its southern edge around y=42.
	_fill(5,  14,  38, 44, PLAINS)

	# ── 3. Main western landmass ─────────────────────────────────────────────
	# The core continent body: Tantegel, Brecconary, and everything south
	# through to the interior sea coast.
	_fill(5,  18,  73, 82, PLAINS)

	# ── 4. Eastern landmass ──────────────────────────────────────────────────
	# Separated from the western body by the Rimuldar strait. Large forest-
	# heavy landmass; Cave of Domdora is here in the northeast.
	_fill(73, 14, 117, 80, PLAINS)

	# ── 5. Southwest peninsula (Cantlin region) ──────────────────────────────
	_fill(5,  80,  45, 117, PLAINS)

	# ── 6. Southeast extension ───────────────────────────────────────────────
	_fill(83, 80, 117, 110, PLAINS)

	# ── 7. Carve ocean features ───────────────────────────────────────────────

	# Northwest bay — the bay below the Garinham peninsula. A bridge on the
	# east side of this bay is the only land crossing.
	_fill(5,  43,  24,  63, OCEAN)

	# Rimuldar strait — the deep vertical channel dividing east from west.
	# The famous long bridge crosses it around y=50.
	_fill(73, 32,  88,  70, OCEAN)

	# Southern interior sea — large bay containing Charlock's island.
	# Surrounded by mountains and swamp; entered only by boat in the original.
	_fill(30, 83,  83, 118, OCEAN)

	# Southwest coast carve — gives the Cantlin peninsula its irregular shape.
	_fill(5, 102,  20, 118, OCEAN)

	# Southeast coast carve
	_fill(93, 105, 117, 118, OCEAN)

	# Minor western bay (mid-coast)
	_fill(5,  64,  18,  78, OCEAN)

	# ── 8. Islands ────────────────────────────────────────────────────────────

	# Rimuldar island — the eastern island reached by the long bridge.
	_fill(88, 37, 114,  68, PLAINS)

	# Charlock island — the Dragonlord's island in the southern interior sea.
	_fill(47, 95,  68, 115, PLAINS)

	# Small scattered islands
	_fill(8,  100,  18, 112, PLAINS)  # small island off the southwest coast


# ── Terrain overlays ───────────────────────────────────────────────────────────

func _paint_terrain():
	# Terrain based on the Dragon Warrior NES reference map.

	# ── FOREST ────────────────────────────────────────────────────────────────
	# Northwest forests — dense woodland around Garinham; Grave of Garin hidden here.
	_fill(5,  14,  35,  42, FOREST)
	# Northern forest belt — flanking the approach to Kol.
	_fill(27,  4,  72,  17, FOREST)
	# Eastern forests — large region east of the Rimuldar strait.
	_fill(88, 14, 117,  45, FOREST)
	# Southeast forests — south of the strait.
	_fill(83, 55, 117,  80, FOREST)
	# Central-east forest patch — between Tantegel and the strait.
	_fill(55, 35,  73,  60, FOREST)

	# ── MOUNTAIN ──────────────────────────────────────────────────────────────
	# Central range south of Tantegel — the main barrier between the populated
	# north and the dangerous south.
	_fill(30, 60,  50,  72, MOUNTAIN)
	# Mountain range along the north shore of the interior sea.
	_fill(32, 80,  82,  88, MOUNTAIN)
	# Northern mountain cluster — near the Mountain Cave north of Kol.
	_fill(57, 18,  70,  32, MOUNTAIN)
	# Eastern mountain spine — harsh terrain in the far east.
	_fill(90, 42, 117,  68, MOUNTAIN)
	# Charlock island — mostly impassable rock; castle and approaches cleared below.
	_fill(47, 95,  68, 115, MOUNTAIN)

	# ── SWAMP ─────────────────────────────────────────────────────────────────
	# Hauksness area — south-central swamp; damaging per step in the original.
	_fill(35, 68,  65,  82, SWAMP)

	# ── DESERT ────────────────────────────────────────────────────────────────
	# Southwest desert — the arid approach to Cantlin.
	_fill(8,  78,  42,  103, DESERT)

	# ── CLEAR PLAINS around landmark zones ───────────────────────────────────
	_fill(38, 46,  56,  62, PLAINS)   # Tantegel / Brecconary
	_fill(50,  3,  68,  12, PLAINS)   # Kol
	_fill(10, 21,  26,  34, PLAINS)   # Garinham
	_fill(86, 39, 112,  66, PLAINS)   # Rimuldar island interior
	_fill(35, 67,  53,  80, PLAINS)   # Hauksness
	_fill(28, 96,  50, 110, PLAINS)   # Cantlin
	_fill(48, 97,  68, 115, PLAINS)   # Charlock island (cleared, MOUNTAIN re-added above)
	_fill(52, 102,  64, 112, PLAINS)  # Charlock inner zone around the castle


# ── Landmark tiles ─────────────────────────────────────────────────────────────

func _place_landmarks():
	# Positions based on the Dragon Warrior NES reference overworld map.

	# Castles
	_place(44, 51, CASTLE)   # Tantegel Castle  — hero's origin; south of center
	_place(57, 108, CASTLE)  # Charlock Castle  — Dragonlord's keep on the southern island

	# Towns
	_place(47, 57, TOWN)     # Brecconary  — first town; SE of Tantegel
	_place(17, 26, TOWN)     # Garinham    — NW peninsula; Silver Harp
	_place(58,  7, TOWN)     # Kol         — far north coast; Fairy Flute
	_place(95, 50, TOWN)     # Rimuldar    — eastern island; sells Keys
	_place(37, 103, TOWN)    # Cantlin     — far SW; strongest weapons
	_place(42, 73, TOWN)     # Hauksness   — south ruins; Armor of Erdrick nearby

	# Caves and dungeons
	_place(14, 30, CAVE)     # Grave of Garin  — NW forest (Silver Harp)
	_place(60, 17, CAVE)     # Mountain Cave   — north; multi-floor dungeon
	_place(63, 47, CAVE)     # Swamp Cave      — central passage east↔west
	_place(28, 90, CAVE)     # Erdrick's Cave  — SW near Cantlin (Erdrick's Seal)
	_place(45, 76, CAVE)     # Hauksness cave  — approach dungeon
	_place(88, 17, CAVE)     # Cave of Domdora — NE forest


# ── Bridges ────────────────────────────────────────────────────────────────────

func _paint_bridges():
	# East bridge — the famous long bridge to Rimuldar island.
	# Runs horizontally across the Rimuldar strait at roughly the same latitude
	# as Rimuldar town (y=50). Spans the full width of the channel.
	for x in range(73, 89):
		_place(x, 50, BRIDGE)

	# Northwest bay bridge — vertical crossing on the east shore of the bay
	# below the Garinham peninsula. The only path south along the west coast
	# without going all the way around the peninsula.
	for y in range(43, 62):
		_place(24, y, BRIDGE)


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
