# ==============================================================================
# overworld.gd
# Part of: godot4-dragon-warrior-clone
# Description: Root script for the overworld scene. Generates the full Dragon
#              Warrior placeholder overworld map (120×120 tiles) at runtime and
#              in the editor. Detects when the player steps onto a town/castle/
#              cave tile and fires the appropriate scene transition. Random
#              encounter checks are delegated to EncounterManager on every step.
# Attached to: Node2D (Overworld) in scenes/world/overworld.tscn
# ==============================================================================

@tool
extends Node2D

# Click this button in the Inspector (with the Overworld node selected) to
# force the map to regenerate from the current generation code. Use this any
# time after pulling new code — Godot caches compiled scripts and _ready() may
# not re-run automatically after a git pull.
@export_tool_button("Regenerate Map") var _regen_btn = func(): _generate_map()

# ------------------------------------------------------------------------------
# Tile type indices — must match the atlas column order in _build_tileset().
# ------------------------------------------------------------------------------
const OCEAN    = 0   # impassable — deep water
const PLAINS   = 1   # walkable   — open grassland
const FOREST   = 2   # walkable   — slows movement in the original
const MOUNTAIN = 3   # impassable — rocky peaks
const SWAMP    = 4   # walkable   — damages per step in the original
const DESERT   = 5   # walkable   — slightly slower in the original
const BRIDGE   = 6   # walkable   — spans ocean channels
const TOWN     = 7   # walkable   — triggers town scene transition
const CAVE     = 8   # walkable   — triggers dungeon scene transition
const CASTLE   = 9   # walkable   — triggers castle scene transition

const MAP_W = 120
const MAP_H = 120

# Internal generation buffer: _map[y][x] = tile type int.
# Populated by _generate_map() and discarded after _apply_to_tilemap().
var _map = []

# ------------------------------------------------------------------------------
# Entrance map
# Maps "x,y" tile coordinate strings to destination scene paths.
# The player is transported as soon as they step onto the tile.
# Empty string = scene not yet built; logs a warning and does not crash.
# Add an entry here whenever a new town/cave/dungeon scene is created.
# ------------------------------------------------------------------------------
const ENTRANCES = {
	# Castles
	"44,51":  "res://scenes/world/tantegel_throne_room.tscn",  # Tantegel Castle

	# Towns — all routed to town_sample until individual scenes are built
	"47,57":  "res://scenes/towns/town_sample.tscn",   # Brecconary
	"17,26":  "res://scenes/towns/town_sample.tscn",   # Garinham   (placeholder)
	"58,7":   "res://scenes/towns/town_sample.tscn",   # Kol        (placeholder)
	"95,50":  "res://scenes/towns/town_sample.tscn",   # Rimuldar   (placeholder)
	"37,103": "res://scenes/towns/town_sample.tscn",   # Cantlin    (placeholder)
	"42,73":  "res://scenes/towns/town_sample.tscn",   # Hauksness  (placeholder)

	# Caves — empty until dungeon scenes are built
	"14,30":  "",  # Grave of Garin
	"60,17":  "",  # Mountain Cave
	"63,47":  "",  # Swamp Cave
	"28,90":  "",  # Erdrick's Cave
	"45,76":  "",  # Hauksness approach cave
	"88,17":  "",  # Cave of Domdora

	# Charlock — endgame dungeon, no scene yet
	"57,108": "",
}

# ------------------------------------------------------------------------------
# Node references — resolved at runtime via @onready.
# In editor mode these still resolve because the scene tree is loaded.
# ------------------------------------------------------------------------------
@onready var tilemap           = $TileMapLayer
@onready var player            = $Player
@onready var encounter_manager = $EncounterManager


# ==============================================================================
# LIFECYCLE
# ==============================================================================

func _ready():
	# Always regenerate in editor mode so the map is visible in the 2D view
	# the moment you open the scene. Autoloads are NOT available in editor
	# mode, so we return immediately after generating tiles.
	if Engine.is_editor_hint():
		_generate_map()
		return

	# Runtime: always generate the map so code changes always take effect.
	# The tileset is built entirely in code — there is nothing baked in the
	# .tscn that would go stale.
	_generate_map()

	# Resume the playtime clock now that the player has overworld control.
	GameState.resume_playtime()

	# Collision layer/mask 1 so the player interacts with NPC Area2D zones.
	player.collision_layer = 1
	player.collision_mask  = 1

	# Connect step signal to both GameState persistence and encounter rolls.
	# Using signals keeps player.gd decoupled from both subsystems.
	player.player_moved.connect(_on_player_moved)
	player.player_moved.connect(encounter_manager.on_player_stepped)

	# Trigger any world-flag events registered for the overworld scene.
	EventManager.check_events_for_scene("overworld")


# ==============================================================================
# SIGNAL HANDLERS
# ==============================================================================

func _on_player_moved(new_tile_pos):
	# Persist position on every step so a save made mid-overworld is accurate.
	GameState.set_location(GameState.current_scene, new_tile_pos)
	# Check if the new tile is a registered entrance (town/cave/castle).
	_check_tile_entrance(new_tile_pos)


func _check_tile_entrance(tile_pos):
	# Build the lookup key and check the ENTRANCES dictionary.
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
# Fill operations are applied in order — later fills override earlier ones.
# ==============================================================================

func _generate_map():
	_init_map()          # allocate 120×120 buffer, default OCEAN
	_paint_continent()   # fill land blobs, carve ocean features
	_paint_terrain()     # overlay FOREST, MOUNTAIN, SWAMP, DESERT
	_place_landmarks()   # stamp TOWN, CAVE, CASTLE tiles
	_paint_bridges()     # draw BRIDGE tiles across the ocean channels
	tilemap.tile_set = _build_tileset()  # create 10-color atlas tileset
	_apply_to_tilemap()  # write _map buffer into the TileMapLayer


# ── Buffer helpers ─────────────────────────────────────────────────────────────

func _init_map():
	# Allocate a fresh MAP_H × MAP_W 2D array, filled entirely with OCEAN.
	_map.clear()
	for _y in range(MAP_H):
		var row = []
		for _x in range(MAP_W):
			row.append(OCEAN)
		_map.append(row)


func _fill(x1, y1, x2, y2, tile):
	# Fill the rectangle from (x1,y1) inclusive to (x2,y2) exclusive.
	# Coordinates are clamped to the map boundary so callers need not worry
	# about edge overflow.
	for y in range(max(0, y1), min(MAP_H, y2)):
		for x in range(max(0, x1), min(MAP_W, x2)):
			_map[y][x] = tile


func _place(x, y, tile):
	# Place a single tile. Silently ignores out-of-bounds coordinates.
	if x >= 0 and x < MAP_W and y >= 0 and y < MAP_H:
		_map[y][x] = tile


# ── Continent shape ────────────────────────────────────────────────────────────

func _paint_continent():
	# Build the Dragon Warrior NES continent shape using a fill-then-carve
	# strategy: paint large land blobs first, then cut ocean features out.

	# ── Land fills ────────────────────────────────────────────────────────────

	# Northern neck leading to Kol — thin strip along the north coast.
	_fill(25,  3,  72, 18, PLAINS)

	# Northwest peninsula — Garinham region; separated from main body by bay.
	_fill( 5, 14,  38, 44, PLAINS)

	# Main western landmass — Tantegel, Brecconary, Hauksness corridor.
	_fill( 5, 18,  73, 82, PLAINS)

	# Eastern landmass — large forested region east of Rimuldar strait.
	_fill(73, 14, 117, 80, PLAINS)

	# Southwest peninsula — Cantlin region.
	_fill( 5, 80,  45, 117, PLAINS)

	# Southeast extension — southern portion of the eastern continent.
	_fill(83, 80, 117, 110, PLAINS)

	# ── Ocean carve-outs ──────────────────────────────────────────────────────

	# Northwest bay — the bay below the Garinham peninsula. A vertical bridge
	# on the bay's east shore is the only crossing without sailing.
	_fill( 5, 43,  24,  63, OCEAN)

	# Rimuldar strait — the deep channel dividing east from west continents.
	# The long horizontal bridge at y=50 is the primary crossing.
	_fill(73, 32,  88,  70, OCEAN)

	# Southern interior sea — the large enclosed sea in the south. Contains
	# Charlock island. Inaccessible without the boat in the original.
	_fill(30, 83,  83, 118, OCEAN)

	# Southwest coast inlet — gives the Cantlin peninsula its irregular shape.
	_fill( 5, 102,  20, 118, OCEAN)

	# Southeast coast carve
	_fill(93, 105, 117, 118, OCEAN)

	# Minor western bay (mid-coast)
	_fill( 5,  64,  18,  78, OCEAN)

	# ── Islands ───────────────────────────────────────────────────────────────

	# Rimuldar island — reachable only via the long bridge or the boat.
	_fill(88, 37, 114,  68, PLAINS)

	# Charlock island — the Dragonlord's keep; the final destination.
	_fill(47, 95,  68, 115, PLAINS)

	# Small scattered island off the SW coast
	_fill( 8, 100,  18, 112, PLAINS)


# ── Terrain overlays ───────────────────────────────────────────────────────────

func _paint_terrain():
	# Overlay terrain types on top of the PLAINS continent base.
	# Applied in order: FOREST → MOUNTAIN → SWAMP → DESERT → landmark clearings.

	# ── FOREST ────────────────────────────────────────────────────────────────
	# Northwest forests — Garinham peninsula, home of the Grave of Garin.
	_fill( 5, 14,  35,  42, FOREST)
	# Northern forest belt — flanks the narrow approach to Kol.
	_fill(27,  3,  72,  17, FOREST)
	# Eastern forests — large region east of the Rimuldar strait.
	_fill(88, 14, 117,  45, FOREST)
	# Southeast forests — south of the strait crossing.
	_fill(83, 55, 117,  80, FOREST)
	# Central-east forest patch — between Tantegel and the strait.
	_fill(55, 35,  73,  60, FOREST)

	# ── MOUNTAIN ──────────────────────────────────────────────────────────────
	# Central range south of Tantegel — primary barrier to the south.
	_fill(30, 60,  50,  72, MOUNTAIN)
	# Mountain chain along the north shore of the interior sea.
	_fill(32, 80,  82,  88, MOUNTAIN)
	# Northern cluster — near the Mountain Cave north of Kol.
	_fill(57, 18,  70,  32, MOUNTAIN)
	# Eastern mountain spine — harsh terrain in the far east.
	_fill(90, 42, 117,  68, MOUNTAIN)
	# Charlock island — mostly impassable; approaches cleared below.
	_fill(47, 95,  68, 115, MOUNTAIN)

	# ── SWAMP ─────────────────────────────────────────────────────────────────
	# Hauksness area — the toxic south-central marsh; damages per step.
	_fill(35, 68,  65,  82, SWAMP)

	# ── DESERT ────────────────────────────────────────────────────────────────
	# Southwest desert — arid wasteland surrounding the approach to Cantlin.
	_fill( 8, 78,  42, 103, DESERT)

	# ── Clear plains around each landmark ─────────────────────────────────────
	# Ensures towns/castles/caves have walkable space and aren't hidden by
	# overlapping terrain fills from the blocks above.
	_fill(38, 46,  56,  62, PLAINS)   # Tantegel / Brecconary zone
	_fill(50,  3,  68,  12, PLAINS)   # Kol zone
	_fill(10, 21,  26,  34, PLAINS)   # Garinham zone
	_fill(86, 39, 112,  66, PLAINS)   # Rimuldar island interior
	_fill(35, 67,  53,  80, PLAINS)   # Hauksness zone
	_fill(28, 96,  50, 110, PLAINS)   # Cantlin zone
	_fill(52, 102,  64, 112, PLAINS)  # Charlock island inner zone


# ── Landmark tiles ─────────────────────────────────────────────────────────────

func _place_landmarks():
	# Positions derived from the Dragon Warrior NES reference map.

	# Castles
	_place(44, 51, CASTLE)    # Tantegel Castle  — hero's origin point
	_place(57, 108, CASTLE)   # Charlock Castle  — Dragonlord's keep

	# Towns
	_place(47, 57, TOWN)      # Brecconary  — first town, SE of Tantegel
	_place(17, 26, TOWN)      # Garinham    — NW peninsula, Silver Harp
	_place(58,  7, TOWN)      # Kol         — north coast, Fairy Flute
	_place(95, 50, TOWN)      # Rimuldar    — eastern island, sells Keys
	_place(37, 103, TOWN)     # Cantlin     — far SW, best weapons/armor
	_place(42, 73, TOWN)      # Hauksness   — southern ruins town

	# Caves and dungeons
	_place(14, 30, CAVE)      # Grave of Garin  (Silver Harp)
	_place(60, 17, CAVE)      # Mountain Cave   (multi-floor dungeon)
	_place(63, 47, CAVE)      # Swamp Cave      (east-west shortcut)
	_place(28, 90, CAVE)      # Erdrick's Cave  (Erdrick's Seal)
	_place(45, 76, CAVE)      # Hauksness cave  (approach dungeon)
	_place(88, 17, CAVE)      # Cave of Domdora (Token of Erdrick)


# ── Bridges ────────────────────────────────────────────────────────────────────

func _paint_bridges():
	# East bridge — the long horizontal crossing of the Rimuldar strait.
	# Spans from the western mainland to the Rimuldar island at latitude y=50.
	for x in range(73, 89):
		_place(x, 50, BRIDGE)

	# Northwest bay bridge — vertical crossing on the east shore of the bay
	# below the Garinham peninsula. The only land route south along the west
	# coast without a boat.
	for y in range(43, 62):
		_place(24, y, BRIDGE)


# ── TileSet builder ────────────────────────────────────────────────────────────

func _build_tileset():
	# Create a 320×32 image: 10 solid-color 32×32 tiles arranged in a row.
	# The column index of each tile equals its tile type constant above,
	# which is how player.gd reads atlas coords to determine passability.
	var img = Image.create(320, 32, false, Image.FORMAT_RGBA8)
	var colors = [
		Color(0.10, 0.28, 0.55, 1.0),  # 0  OCEAN     — deep blue
		Color(0.28, 0.58, 0.20, 1.0),  # 1  PLAINS    — grass green
		Color(0.08, 0.32, 0.08, 1.0),  # 2  FOREST    — dark green
		Color(0.50, 0.42, 0.32, 1.0),  # 3  MOUNTAIN  — warm grey-brown
		Color(0.20, 0.38, 0.12, 1.0),  # 4  SWAMP     — murky olive green
		Color(0.80, 0.70, 0.30, 1.0),  # 5  DESERT    — sandy yellow
		Color(0.55, 0.40, 0.20, 1.0),  # 6  BRIDGE    — worn wood brown
		Color(0.85, 0.80, 0.25, 1.0),  # 7  TOWN      — warm gold
		Color(0.28, 0.22, 0.18, 1.0),  # 8  CAVE      — dark earth
		Color(0.60, 0.60, 0.70, 1.0),  # 9  CASTLE    — stone blue-grey
	]
	for i in range(10):
		img.fill_rect(Rect2i(i * 32, 0, 32, 32), colors[i])

	var tex = ImageTexture.create_from_image(img)

	# No physics layer on the TileSet. Terrain blocking is handled entirely
	# in player.gd via _is_tile_blocked(), which reads the atlas column index
	# of the destination tile (col 0 = OCEAN, col 3 = MOUNTAIN → blocked).
	# This avoids the TileData physics polygon API (version-dependent) and is
	# more authentic to Dragon Warrior's pure tile-logic movement system.
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
	# Write every cell from the _map buffer into the TileMapLayer.
	# Source ID 0 = the single atlas source created in _build_tileset().
	# Atlas coord x = tile type (column index in the 10-tile row image).
	tilemap.clear()
	for y in range(MAP_H):
		for x in range(MAP_W):
			tilemap.set_cell(Vector2i(x, y), 0, Vector2i(_map[y][x], 0))
