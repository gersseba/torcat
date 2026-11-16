extends Node
## Central music/SFX playback. Creates the Music and Sfx buses at runtime
## (no bus layout file needed), crossfades music and pools SFX players.

const MUSIC_BUS := "Music"
const SFX_BUS := "Sfx"
const SFX_POOL_SIZE := 6
const CROSSFADE_SECONDS := 0.8
const SILENT_DB := -60.0
## Minimum seconds between two plays of the same SFX (guards rapid retriggers).
const SFX_MIN_INTERVAL := 0.06
const MUSIC_DIR := "res://resources/audio/music/"
const SFX_DIR := "res://resources/audio/sfx/"

## id -> [file, loops]. Only the three long tracks loop; stings are one-shots.
const MUSIC := {
	"menu": ["music_menu.mp3", true],
	"gameplay_a": ["music_gameplay_a.mp3", true],
	"gameplay_b": ["music_gameplay_b.mp3", true],
	"victory": ["music_victory.mp3", false],
	"defeat": ["music_defeat.mp3", false],
}
const SFX := {
	"ui_tap": "sfx_ui_tap.mp3",
	"ui_back": "sfx_ui_back.mp3",
	"tile_select": "sfx_tile_select.mp3",
	"move_step": "sfx_move_step.mp3",
	"blocked": "sfx_blocked.mp3",
	"pickup_resupply": "sfx_pickup_resupply.mp3",
	"enemy_hit": "sfx_enemy_hit.mp3",
	"level_complete": "sfx_level_complete.mp3",
}
const NO_TAP_META := &"no_tap_sfx"

var current_music_id := ""
var _music_players: Array[AudioStreamPlayer] = []
var _active_music := 0
var _music_tween: Tween
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx := 0
var _sfx_cache: Dictionary = {}
var _last_sfx_msec: Dictionary = {}


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	for i in 2:
		_music_players.append(_make_player(MUSIC_BUS))
	for i in SFX_POOL_SIZE:
		_sfx_players.append(_make_player(SFX_BUS))
	get_tree().node_added.connect(_on_node_added)
	refresh_settings()


## Applies AppState.music_enabled / sfx_enabled to the buses.
func refresh_settings() -> void:
	var app_state := get_node_or_null("/root/AppState")
	if app_state == null:
		return
	AudioServer.set_bus_mute(AudioServer.get_bus_index(MUSIC_BUS), not bool(app_state.get("music_enabled")))
	AudioServer.set_bus_mute(AudioServer.get_bus_index(SFX_BUS), not bool(app_state.get("sfx_enabled")))


## Crossfades to music `id`. No-op when it is already the current track.
func play_music(id: String) -> void:
	if id == current_music_id:
		return
	var stream := _load_music(id)
	if stream == null:
		return
	current_music_id = id
	var outgoing := _music_players[_active_music]
	_active_music = 1 - _active_music
	var incoming := _music_players[_active_music]
	if _music_tween != null:
		_music_tween.kill()
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(incoming, "volume_db", 0.0, CROSSFADE_SECONDS)
	if outgoing.playing:
		_music_tween.tween_property(outgoing, "volume_db", SILENT_DB, CROSSFADE_SECONDS)
		_music_tween.chain().tween_callback(outgoing.stop)


func stop_music() -> void:
	current_music_id = ""
	if _music_tween != null:
		_music_tween.kill()
	for player in _music_players:
		player.stop()


func play_sfx(id: String) -> void:
	var stream := _load_sfx(id)
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_sfx_msec.get(id, -10000)) < SFX_MIN_INTERVAL * 1000.0:
		return
	_last_sfx_msec[id] = now
	var player := _sfx_players[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx_players.size()
	player.stream = stream
	player.play()


## Gameplay track for a level: chapters alternate a/b; other levels use a.
static func gameplay_music_id(chapter_index: int) -> String:
	return "gameplay_b" if chapter_index >= 0 and chapter_index % 2 == 1 else "gameplay_a"


func _on_node_added(node: Node) -> void:
	if not (node is BaseButton) or node.has_meta(NO_TAP_META) or node.has_meta(&"audio_hooked"):
		return
	node.set_meta(&"audio_hooked", true)
	var button := node as BaseButton
	button.pressed.connect(func() -> void:
		if button.has_meta(NO_TAP_META):
			return
		play_sfx("ui_back" if button.name.to_lower().contains("back") else "ui_tap")
	)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")


func _make_player(bus_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus_name
	add_child(player)
	return player


func _load_music(id: String) -> AudioStream:
	if not MUSIC.has(id):
		push_error("Unknown music id: %s" % id)
		return null
	var stream := load(MUSIC_DIR + str(MUSIC[id][0])) as AudioStreamMP3
	if stream == null:
		push_error("Cannot load music: %s" % id)
		return null
	stream.loop = bool(MUSIC[id][1])
	return stream


func _load_sfx(id: String) -> AudioStream:
	if _sfx_cache.has(id):
		return _sfx_cache[id]
	if not SFX.has(id):
		push_error("Unknown sfx id: %s" % id)
		return null
	var stream := load(SFX_DIR + str(SFX[id])) as AudioStreamMP3
	if stream == null:
		push_error("Cannot load sfx: %s" % id)
		return null
	stream.loop = false
	_sfx_cache[id] = stream
	return stream
