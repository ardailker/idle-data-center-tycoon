extends Node

# Procedural Audio Engine for Idle Data Center Tycoon (§9)
# Synthesizes 5 UI sounds and 1 ambient server room drone without external files.

var sfx_player: AudioStreamPlayer
var ambient_player: AudioStreamPlayer

var sample_rate: float = 22050.0

func _ready() -> void:
	sfx_player = AudioStreamPlayer.new()
	sfx_player.bus = "Master"
	add_child(sfx_player)
	
	ambient_player = AudioStreamPlayer.new()
	ambient_player.bus = "Master"
	add_child(ambient_player)
	
	_setup_ambient_loop()

func _is_sfx_enabled() -> bool:
	if GameState and GameState.state.has("settings"):
		return bool(GameState.state["settings"].get("sfx_enabled", true))
	return true

func _is_music_enabled() -> bool:
	if GameState and GameState.state.has("settings"):
		return bool(GameState.state["settings"].get("music_enabled", true))
	return true

func play_click() -> void:
	if not _is_sfx_enabled():
		return
	_play_synth_sound(_generate_tone(880.0, 0.04, 0.3, "sine"))

func play_alarm() -> void:
	if not _is_sfx_enabled():
		return
	_play_synth_sound(_generate_tone(440.0, 0.15, 0.5, "saw"))

func play_research() -> void:
	if not _is_sfx_enabled():
		return
	_play_synth_sound(_generate_arpeggio([523.25, 659.25, 783.99, 1046.5], 0.06, 0.4))

func play_prestige() -> void:
	if not _is_sfx_enabled():
		return
	_play_synth_sound(_generate_arpeggio([440.0, 554.37, 659.25, 880.0], 0.10, 0.5))

func play_cash() -> void:
	if not _is_sfx_enabled():
		return
	_play_synth_sound(_generate_arpeggio([987.77, 1318.51], 0.08, 0.4))

func update_audio_settings() -> void:
	if _is_music_enabled():
		if not ambient_player.playing:
			ambient_player.play()
	else:
		if ambient_player.playing:
			ambient_player.stop()

func _setup_ambient_loop() -> void:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = int(sample_rate)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(sample_rate * 2.0)
	
	# Generate low server fan hum
	var data := PackedByteArray()
	var total_samples := int(sample_rate * 2.0)
	data.resize(total_samples)
	
	for i in range(total_samples):
		var t: float = float(i) / sample_rate
		var wave: float = sin(t * 60.0 * TAU) * 0.3 + sin(t * 120.0 * TAU) * 0.15 + (randf() * 0.05 - 0.025)
		var byte_val: int = int(clamp((wave + 1.0) * 0.5 * 255.0, 0.0, 255.0))
		data[i] = byte_val
	
	stream.data = data
	ambient_player.stream = stream
	if _is_music_enabled() and not OS.has_feature("template"):
		ambient_player.play()

func _play_synth_sound(data: PackedByteArray) -> void:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = int(sample_rate)
	stream.data = data
	sfx_player.stream = stream
	sfx_player.play()

func _generate_tone(freq: float, duration: float, volume: float, wave_type: String = "sine") -> PackedByteArray:
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	for i in range(total_samples):
		var t: float = float(i) / sample_rate
		var env: float = 1.0 - (float(i) / float(total_samples)) # Linear decay
		var sample: float = 0.0
		if wave_type == "sine":
			sample = sin(t * freq * TAU)
		elif wave_type == "saw":
			sample = (fmod(t * freq, 1.0) * 2.0 - 1.0)
		var val: float = sample * volume * env
		data[i] = int(clamp((val + 1.0) * 0.5 * 255.0, 0.0, 255.0))
	return data

func _generate_arpeggio(freqs: Array, note_duration: float, volume: float) -> PackedByteArray:
	var total_samples := int(sample_rate * note_duration * freqs.size())
	var data := PackedByteArray()
	data.resize(total_samples)
	
	var samples_per_note := int(sample_rate * note_duration)
	for n in range(freqs.size()):
		var freq: float = freqs[n]
		for i in range(samples_per_note):
			var idx: int = n * samples_per_note + i
			if idx >= total_samples:
				break
			var t: float = float(i) / sample_rate
			var env: float = 1.0 - (float(i) / float(samples_per_note))
			var sample: float = sin(t * freq * TAU) * volume * env
			data[idx] = int(clamp((sample + 1.0) * 0.5 * 255.0, 0.0, 255.0))
	return data
