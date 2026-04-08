# ==============================================================================
# generate_overworld.gd
# Part of: godot4-dragon-warrior-clone
# Description: One-shot EditorScript that paints the Dragon Warrior overworld
#              onto the TileMapLayer in overworld.tscn. Run once from the Godot
#              editor; the tile data is baked into the scene file and is then
#              freely editable with the standard tilemap painter.
#
# HOW TO USE:
#   1. Open scenes/world/overworld.tscn in the Godot editor.
#   2. Open this script in the Script editor (double-click it in FileSystem).
#   3. Click File > Run (or Shift+Ctrl+X) in the Script editor toolbar.
#   4. Wait for "generate_overworld: done" to print in the Output panel.
#   5. Save overworld.tscn (Ctrl+S) — tile data is now baked in.
#   6. You can freely paint over tiles with the tilemap editor afterward.
#
# GEOGRAPHY NOTE:
#   Coordinates approximate Dragon Warrior NES overworld layout based on
#   documented fan maps. Coastlines, terrain borders, and landmark positions
#   are intentionally designed to be massaged in the tilemap editor after
#   generation. Every fill region and landmark is labeled for easy tweaking.
#
# Attached to: (not attached to any node — run as EditorScript only)
# ==============================================================================

@tool
extends EditorScript

# ------------------------------------------------------------------------------
# Tile type indices — must match the atlas column order built in _build_tileset.
# overworld.gd also imports these constants; keep both files in sync if you
# ever reorder them.
# ------------------------------------------------------------------------------
const OCEAN    = 0   # impassable — deep water
const PLAINS   = 1   # walkable  — open grassland
const FOREST   = 2   # walkable  — slows movement in original game
const MOUNTAIN = 3   # impassable — rocky peaks
const SWAMP    = 4   # walkable  — deals damage per step in original game
const DESERT   = 5   # walkable  — slightly slower movement
const BRIDGE   = 6   # walkable  — spans ocean channels
const TOWN     = 7   # walkable  — triggers town scene transition
const CAVE     = 8   # walkable  — triggers dungeon scene transition
const CASTLE   = 9   # walkable  — triggers castle scene transition

const MAP_W = 120
const MAP_H = 120

# Internal map buffer: _map[y][x] = tile type int
var _map = []


# ==============================================================================
# ENTRY POINT
# ==============================================================================

func _run():
	var scene_root = get_scene()
	if scene_root == null:
		push_error("generate_overworld: no scene open — open overworld.tscn first")
		return

	# The TileMapLayer must already exist in the scene tree (it was placed in
	# the editor). We find it by type so it doesn't matter where it sits.
	var tilemap = scene_root.find_child("TileMapLayer", true, false)
	if tilemap == null:
		push_error("generate_overworld: TileMapLayer node not found in scene")
		return

	print("generate_overworld: building map data …")
	_init_map()
	_paint_continent()
	_paint_terrain()
	_place_landmarks()
	_paint_bridges()

	print("generate_overworld: building TileSet …")
	tilemap.tile_set = _build_tileset()

	print("generate_overworld: writing %d tiles to TileMapLayer …" % (MAP_W * MAP_H))
	_apply_to_tilemap(tilemap)

	print("generate_overworld: DONE — save overworld.tscn (Ctrl+S) to bake.")


# ==============================================================================
# MAP BUFFER HELPERS
# ==============================================================================

func _init_map():
	# Allocate the 2-D buffer and fill the entire map with ocean.
	# Every subsequent paint call overrides ocean with land features.
	_map.clear()
	for _y in range(MAP_H):
		var row = []
		for _x in range(MAP_W):
			row.append(OCEAN)
		_map.append(row)


# Fill a rectangle with a tile type.
# x1,y1 = top-left (inclusive). x2,y2 = bottom-right (exclusive).
# Out-of-bounds coordinates are silently clamped so fill calls can be liberal.
func _fill(x1, y1, x2, y2, tile):
	for y in range(max(0, y1), min(MAP_H, y2)):
		for x in range(max(0, x1), min(MAP_W, x2)):
			_map[y][x] = tile


# Place a single tile. Out-of-bounds coordinates are ignored.
func _place(x, y, tile):
	if x >= 0 and x < MAP_W and y >= 0 and y < MAP_H:
		_map[y][x] = tile


# ==============================================================================
# CONTINENT SHAPE
# Approximation of Dragon Warrior NES overworld geography.
# Fills are applied top-to-bottom in this function; later fills override earlier.
# The broad strategy:
#   1. Paint a large rectangular land blob covering most of the map.
#   2. Carve ocean bays and channels into it to produce irregular coastlines.
#   3. Restore land for the key islands carved out by step 2.
# ==============================================================================

func _paint_continent():
	# ── 1. MAIN WESTERN LANDMASS ─────────────────────────────────────────────
	# Covers the northern reaches, Garinham (northwest), Tantegel (center-left),
	# and the plains south of the castle.
	_fill(7,   7,  72,  90, PLAINS)

	# ── 2. EASTERN LANDMASS ──────────────────────────────────────────────────
	# Covers the forests and mountains east of center, extending to the coast.
	_fill(68,  7, 115,  90, PLAINS)

	# ── 3. SOUTHWEST LAND (Cantlin / Erdrick's Cave region) ──────────────────
	_fill(7,  87,  44, 115, PLAINS)

	# ── 4. SOUTHEAST LAND ────────────────────────────────────────────────────
	_fill(68, 87, 115, 115, PLAINS)

	# ── 5. CARVE OCEAN BAYS AND CHANNELS ─────────────────────────────────────

	# Northwest bay — a body of water tucked into the western coast just south
	# of Garinham's peninsula. Boats cannot cross; a bridge skirts the edge.
	_fill(7,  48,  24,  65, OCEAN)

	# Central-west coastal recess — narrows the west coast below the bay.
	_fill(7,  70,  18,  87, OCEAN)

	# Eastern channel — the famous strait that separates Rimuldar island from
	# the main continent. The long bridge (added in _paint_bridges) spans it.
	_fill(74, 42,  92,  72, OCEAN)

	# Southern interior sea — large bay in the south where Charlock's island
	# sits. Surrounded by mountains and swamp; only accessible via boat or
	# specific game-progression paths.
	_fill(35, 93,  80, 117, OCEAN)

	# Southwest coast recession — keeps the Cantlin area looking like a
	# peninsula rather than a squared-off corner.
	_fill(7, 100,  22, 117, OCEAN)

	# Southeast coast recession.
	_fill(92, 98, 115, 117, OCEAN)

	# ── 6. ISLANDS ───────────────────────────────────────────────────────────

	# Rimuldar island — eastern island reached via the long bridge.
	# Painted after the channel carve so it stands as its own landmass.
	_fill(91, 49, 108,  70, PLAINS)

	# Charlock island — the Dragonlord's fortress sits in the center of the
	# southern interior sea. Surrounded by swamp; most of the island is
	# impassable mountain until terrain overlays reduce the clear center.
	_fill(51, 99,  69, 115, PLAINS)

	# Small scattered islands
	_fill(10, 100,  19, 110, PLAINS)  # tiny southwest island
	_fill(105,  8, 114,  18, PLAINS)  # small northeast island


# ==============================================================================
# TERRAIN REGIONS
# Overlay specific terrain types on top of the plains base.
# Applied in order: forest → mountain → swamp → desert → clear-for-landmarks.
# ==============================================================================

func _paint_terrain():
	# ── FOREST ───────────────────────────────────────────────────────────────

	# Northwest forest — the dense woodland around Garinham. The Grave of Garin
	# and some early-game caves are hidden in here.
	_fill(7,  20,  33,  50, FOREST)

	# Northern forest belt — flanks the road to Kol.
	_fill(44,  7,  74,  22, FOREST)

	# Eastern forest — large woodland east of center, beyond the mountain range.
	_fill(92,  7, 115,  42, FOREST)

	# Southeast forest — fills the southeastern quadrant.
	_fill(80,  60, 115,  90, FOREST)

	# Central-west scattered forest — makes the plains between Tantegel and the
	# southwestern desert feel more varied.
	_fill(28,  56,  46,  74, FOREST)

	# ── MOUNTAIN ─────────────────────────────────────────────────────────────

	# Central-west range — forms a natural barrier dividing the Tantegel plains
	# from the southwest desert. Players must find the pass or bridge around it.
	_fill(32,  52,  44,  65, MOUNTAIN)

	# Eastern mountain spine — runs north-south in the east, separating the
	# forests from the eastern channel.
	_fill(92,  38, 115,  75, MOUNTAIN)

	# Northern mountain cluster — near the cave north of Kol.
	_fill(60,  18,  72,  34, MOUNTAIN)

	# Southern interior sea shores — ring of mountains bordering the sea that
	# prevents the player from just walking in on foot.
	_fill(35,  88,  80,  96, MOUNTAIN)

	# Charlock island mountains — most of the island is impassable rock; the
	# center and the castle itself will be cleared back to plains below.
	_fill(51,  99,  69, 115, MOUNTAIN)

	# ── SWAMP ────────────────────────────────────────────────────────────────

	# South-central swamp — surrounds Hauksness and the approach to the
	# interior sea. Deals damage per step in the original game.
	_fill(48,  74,  70,  90, SWAMP)

	# ── DESERT ───────────────────────────────────────────────────────────────

	# Southwest desert — the arid region leading to Cantlin. Slightly slower
	# movement; merchants here are the last civilisation before Charlock.
	_fill(7,   74,  40,  96, DESERT)

	# ── CLEAR PLAINS AROUND LANDMARK ZONES ───────────────────────────────────
	# Each named location gets a small cleared area so NPCs and the player can
	# walk freely, and so the landmark tile isn't swallowed by dense terrain.

	# Tantegel Castle and Brecconary — the starting area
	_fill(38,  38,  56,  54, PLAINS)

	# Kol — northern plains clearing
	_fill(52,  12,  66,  22, PLAINS)

	# Garinham — small clearing in the northwest forest
	_fill(11,  22,  24,  33, PLAINS)

	# Rimuldar island — walkable interior
	_fill(89,  48, 109,  71, PLAINS)

	# Hauksness — clearing in the swamp
	_fill(44,  76,  60,  88, PLAINS)

	# Cantlin — desert town clearing
	_fill(23,  84,  40,  97, PLAINS)

	# Charlock island — small navigable area around the castle
	_fill(53, 100,  67, 113, PLAINS)
	_fill(55, 102,  65, 111, PLAINS)


# ==============================================================================
# LANDMARKS
# Individual tile placements for castles, towns, and cave entrances.
# Coordinates match the nearest-correct positions on the painted continent.
# ==============================================================================

func _place_landmarks():
	# ── CASTLES ───────────────────────────────────────────────────────────────
	_place(45, 43, CASTLE)   # Tantegel Castle  — hero's starting location
	_place(58, 105, CASTLE)  # Charlock Castle  — Dragonlord's fortress (endgame)

	# ── TOWNS ─────────────────────────────────────────────────────────────────
	_place(44, 47, TOWN)     # Brecconary       — first town; just south of Tantegel
	_place(17, 27, TOWN)     # Garinham         — northwest; harp and Silver Shield
	_place(58, 17, TOWN)     # Kol              — north; Fairy Flute and healer
	_place(92, 55, TOWN)     # Rimuldar         — eastern island; sells keys
	_place(30, 89, TOWN)     # Cantlin          — southwest; strongest weapons
	_place(51, 81, TOWN)     # Hauksness        — south; Armor of Erdrick nearby

	# ── CAVES AND DUNGEONS ────────────────────────────────────────────────────
	_place(26, 24, CAVE)     # Grave of Garin   — northwest forest; Silver Harp
	_place(62, 22, CAVE)     # Mountain Cave    — north of Kol; multi-floor dungeon
	_place(64, 46, CAVE)     # Swamp Cave       — central; connects east/west
	_place(26, 90, CAVE)     # Erdrick's Cave   — southwest; Erdrick's Seal
	_place(52, 78, CAVE)     # Hauksness cave   — approach dungeon
	_place(87, 18, CAVE)     # Cave of Domdora  — northeast; keys and treasures


# ==============================================================================
# BRIDGES
# Thin walkable paths spanning ocean channels. Each bridge is a straight line
# of BRIDGE tiles. Dragon Warrior only had two main bridges; extras are placed
# where the terrain logically needs a crossing.
# ==============================================================================

func _paint_bridges():
	# ── EAST BRIDGE — the longest bridge in the original game ─────────────────
	# Runs horizontally from the mainland's eastern coast (x≈74) across the
	# channel to Rimuldar island (x≈90), at the latitude of Rimuldar town (y=55).
	for x in range(74, 91):
		_place(x, 55, BRIDGE)

	# ── NORTHWEST BAY BRIDGE ──────────────────────────────────────────────────
	# A short vertical bridge on the eastern shore of the northwest bay,
	# letting the player travel south without going all the way around.
	for y in range(48, 57):
		_place(24, y, BRIDGE)

	# ── NORTHERN PASS BRIDGE ─────────────────────────────────────────────────
	# Small horizontal bridge near the northern forests, bridging a narrow gap
	# on the road from the central plains up toward Kol.
	for x in range(42, 46):
		_place(x, 22, BRIDGE)


# ==============================================================================
# TILESET CONSTRUCTION
# Builds a TileSet entirely in code so no external PNG is required.
# The atlas is a 320×32 ImageTexture with 10 solid-color 32×32 tiles.
# Collision shapes (full-tile rectangles) are added to OCEAN and MOUNTAIN so
# the player CharacterBody2D stops at impassable terrain.
# ==============================================================================

func _build_tileset():
	# ── Placeholder atlas image ───────────────────────────────────────────────
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

	# ── TileSet ───────────────────────────────────────────────────────────────
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(32, 32)

	# No physics layer — terrain blocking is handled by player.gd reading the
	# atlas column index of the destination tile before committing the move.
	# This avoids the version-dependent TileData physics polygon API.

	# ── Atlas source ─────────────────────────────────────────────────────────
	var source = TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = Vector2i(32, 32)

	# Register all 10 tile entries so set_cell() can reference them by atlas coord.
	for i in range(10):
		source.create_tile(Vector2i(i, 0))

	# Source ID will be 0 (first and only source in this tileset).
	tileset.add_source(source)
	return tileset


# ==============================================================================
# APPLY TO TILEMAP
# Clears any existing tile data and writes every cell from the buffer.
# Source ID 0 matches the single atlas source added in _build_tileset.
# Atlas coords are Vector2i(tile_type, 0) — one row of tiles in the atlas.
# ==============================================================================

func _apply_to_tilemap(tilemap):
	tilemap.clear()
	for y in range(MAP_H):
		for x in range(MAP_W):
			tilemap.set_cell(Vector2i(x, y), 0, Vector2i(_map[y][x], 0))
