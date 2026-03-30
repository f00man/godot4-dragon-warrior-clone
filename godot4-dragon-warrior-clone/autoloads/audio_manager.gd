# ==============================================================================
# audio_manager.gd
# Part of: godot4-dragon-warrior-clone
# Description: Handles all background music (BGM) and sound effect (SFX)
#              playback for the game. Provides a clean API so other systems
#              never touch AudioStreamPlayer nodes directly.
# Attached to: Autoload (AudioManager)
# ==============================================================================

extends Node

# ------------------------------------------------------------------------------
# Private nodes — created dynamically in _ready(), NOT via @onready.
# @onready resolves at script-load time and requires the nodes to already be
# present in the scene tree. Because we build these players in code we use
# plain var declarations and assign them inside _ready() instead.
# ------------------------------------------------------------------------------

# Dedicated player for background music. Streams are long and expected to loop;
# loop settings are configured on the AudioStream resource itself in the editor.
var _bgm_player = null

# Dedicated player for sound effects. One-shot; does not loop.
var _sfx_player = null

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready():
	# Build the BGM player and attach it as a child of this autoload.
	# Parenting to AudioManager (a persistent autoload) means the player node
	# survives scene changes — critical for music that should continue across
	# room transitions without restarting.
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMPlayer"
	add_child(_bgm_player)

	# Build the SFX player in the same way. It shares the same default audio bus
	# as _bgm_player; if the project adds separate "Music" and "SFX" buses in
	# the Audio layout, assign them here (e.g. _bgm_player.bus = "Music").
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "SFXPlayer"
	add_child(_sfx_player)

# ------------------------------------------------------------------------------
# BGM API
# ------------------------------------------------------------------------------

# Assigns `stream` as the background music and starts playback immediately.
# Looping is controlled by the AudioStream resource itself — open the .ogg or
# .wav file in the Godot editor, enable "Loop" in the Import tab (or the Stream
# resource properties), and set loop points there. This keeps looping flexible
# per-track without requiring code changes for each new piece of music.
func play_bgm(stream):
	_bgm_player.stream = stream
	_bgm_player.play()

# Stops background music immediately. There is no fade; call this when you want
# a hard cut (e.g. entering battle). For a fade-out, tween set_bgm_volume()
# down to -80 first, then call stop_bgm().
func stop_bgm():
	_bgm_player.stop()

# Sets the BGM player volume in decibels.
# Valid range: -80.0 (effectively silent) to 6.0 (maximum hardware boost).
# Use 0.0 for nominal/full volume. Anything below -80 is treated as silence
# by Godot's audio engine (equivalent to AudioServer.linear_to_db(0) = -inf).
func set_bgm_volume(db):
	_bgm_player.volume_db = db

# Returns true if background music is currently playing, false if stopped or
# not yet started. Useful for checking before calling play_bgm() to avoid
# restarting a track that is already running.
func is_bgm_playing():
	return _bgm_player.playing

# ------------------------------------------------------------------------------
# SFX API
# ------------------------------------------------------------------------------

# Plays a one-shot sound effect using the shared SFX player.
# NOTE: _sfx_player can only play one stream at a time. If two SFX are
# triggered on the same frame (or close together), the second call will cut
# off the first. A pooled approach — multiple AudioStreamPlayer instances
# checked out from a pool — will be needed later for overlapping SFX such as
# rapid sword hits or simultaneous UI beeps. For now, this is sufficient for
# a skeleton implementation.
func play_sfx(stream):
	_sfx_player.stream = stream
	_sfx_player.play()

# Sets the SFX player volume in decibels.
# Valid range: -80.0 (effectively silent) to 6.0 (maximum hardware boost).
# Matches the same scale as set_bgm_volume() for consistency.
func set_sfx_volume(db):
	_sfx_player.volume_db = db
