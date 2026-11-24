extends SceneTree

var failures := 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	for bus_name in ["Music", "Sfx"]:
		var index := AudioServer.get_bus_index(bus_name)
		_check(index > 0, "%s bus must exist before audio manager startup" % bus_name)
		if index > 0:
			_check(AudioServer.get_bus_send(index) == "Master", "%s bus must send to Master" % bus_name)
	call_deferred("_run")


func _run() -> void:
	var app_state := root.get_node("AppState")
	var audio := root.get_node("AudioManager")
	var saved_music: bool = app_state.music_enabled
	var saved_sfx: bool = app_state.sfx_enabled
	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("Sfx")
	if music_bus > 0 and sfx_bus > 0:
		app_state.music_enabled = false
		app_state.sfx_enabled = true
		audio.refresh_settings()
		_check(AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(sfx_bus),
			"Music and sound effect settings must mute their buses independently")
		app_state.music_enabled = true
		app_state.sfx_enabled = false
		audio.refresh_settings()
		_check(not AudioServer.is_bus_mute(music_bus) and AudioServer.is_bus_mute(sfx_bus),
			"Music and sound effect settings must unmute their buses independently")
	app_state.music_enabled = saved_music
	app_state.sfx_enabled = saved_sfx
	audio.refresh_settings()
	print("audio_manager_test: %d failure(s)" % failures)
	quit(1 if failures else 0)
