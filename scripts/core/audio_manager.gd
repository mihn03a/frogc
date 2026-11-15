extends Node
## =====================================================================
##  AUDIO_MANAGER.GD - sunetele și muzica (autoload: AudioManager)
## =====================================================================
##  Toate efectele sonore și muzica sunt GENERATE DIN COD la pornire
##  (sinteză de sunet), deci jocul nu are nevoie de fișiere audio.
##
##  Excepție: melodiile tale din res://assets/audio/ (ogg, mp3 sau wav):
##    menu.*     -> muzica din meniul principal (încet, în buclă)
##    victory.*  -> melodia din scena de victorie
##    intro.*    -> o dată la pornire (dezactivat acum în main_menu.gd)
## =====================================================================

const SAMPLE_RATE := 22050       # câte "eșantioane" pe secundă
const PLAYER_COUNT := 14         # câte sunete pot cânta în același timp
const CUSTOM_DIR := "res://assets/audio/"
const CUSTOM_EXTENSIONS := ["ogg", "mp3", "wav"]
const CUSTOM_MUSIC_VOLUME := {"menu": -7.0}   # volumul melodiilor tale (în dB)

# Fiecare efect = o listă de bucăți: [frecvență_start, frecvență_final, durată, formă_de_undă, volum]
# Formele de undă: "sine" (moale), "square" (retro), "saw" (aspru), "tri" (între), "noise" (zgomot)
const SFX := {
	"bounce": [[220, 560, 0.18, "sine", 0.75]],
	"wall": [[320, 170, 0.12, "tri", 0.6]],
	"perfect": [[880, 880, 0.06, "square", 0.3], [1175, 1175, 0.06, "square", 0.3], [1568, 1568, 0.08, "square", 0.3], [2093, 2093, 0.22, "square", 0.28]],
	"damage": [[0, 0, 0.08, "noise", 0.5], [420, 80, 0.32, "saw", 0.6]],
	"collect": [[1320, 1900, 0.08, "square", 0.22]],
	"pu_shield": [[300, 900, 0.18, "tri", 0.5], [900, 1200, 0.25, "sine", 0.45]],
	"pu_super": [[150, 1200, 0.42, "square", 0.32]],
	"pu_speed": [[500, 1900, 0.28, "saw", 0.32]],
	"pu_magnet": [[500, 470, 0.1, "sine", 0.5], [700, 670, 0.1, "sine", 0.5], [940, 900, 0.22, "sine", 0.5]],
	"pu_end": [[800, 260, 0.28, "tri", 0.4]],
	"enemy_die": [[900, 110, 0.22, "square", 0.38]],
	"enemy_shoot": [[1300, 380, 0.13, "saw", 0.22]],
	"reflect": [[500, 1500, 0.16, "square", 0.32], [1500, 1500, 0.08, "sine", 0.3]],
	"boss_hit": [[0, 0, 0.06, "noise", 0.5], [220, 55, 0.4, "square", 0.55]],
	"boss_roar": [[130, 60, 0.9, "saw", 0.6]],
	"boss_shoot": [[520, 180, 0.22, "square", 0.3]],
	"slam": [[0, 0, 0.55, "noise", 0.7]],
	"victory": [[523, 523, 0.14, "square", 0.32], [659, 659, 0.14, "square", 0.32], [784, 784, 0.14, "square", 0.32], [1047, 1047, 0.32, "square", 0.32], [784, 784, 0.12, "square", 0.3], [1047, 1047, 0.7, "square", 0.32]],
	"defeat": [[392, 370, 0.3, "tri", 0.5], [370, 349, 0.3, "tri", 0.5], [349, 330, 0.3, "tri", 0.5], [330, 220, 1.0, "tri", 0.5]],
	"click": [[1000, 1000, 0.04, "square", 0.18]],
	"evolve": [[180, 1700, 1.2, "tri", 0.4], [1700, 2400, 0.4, "sine", 0.35]],
	"level_complete": [[660, 660, 0.1, "square", 0.3], [880, 880, 0.1, "square", 0.3], [990, 990, 0.1, "square", 0.3], [1320, 1320, 0.5, "square", 0.3]],
	"turbo": [[280, 760, 0.22, "saw", 0.38]],
}

# Muzica pe teme: [nota de bază (Hz), gama (semitonuri), tempo (BPM), forma undei melodiei]
const MUSIC := {
	"menu": [196.0, [0, 2, 4, 7, 9], 112, "tri"],
	"valley": [220.0, [0, 2, 4, 7, 9], 128, "square"],
	"lava": [146.83, [0, 3, 5, 6, 7, 10], 140, "saw"],
	"cyber": [164.81, [0, 3, 7, 10, 12], 150, "square"],
	"boss": [130.81, [0, 1, 5, 7, 8], 164, "saw"],
}

var sounds := {}                  # numele efectului -> sunetul generat
var music_cache := {}             # muzica generată (o facem o singură dată pe temă)
var sfx_players: Array[AudioStreamPlayer] = []
var next_sfx_player := 0
var music_player: AudioStreamPlayer
var current_music := ""
var custom_player: AudioStreamPlayer   # pentru melodiile tale (victory, intro)
var music_after_custom := ""           # ce muzică pornește după melodia ta
var intro_played := false


# =====================================================================
#  PORNIRE
# =====================================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	create_audio_buses()
	for i in PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		sfx_players.append(player)
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	add_child(music_player)
	music_player.finished.connect(on_music_finished)
	custom_player = AudioStreamPlayer.new()
	custom_player.bus = "Music"
	add_child(custom_player)
	custom_player.finished.connect(on_custom_finished)
	for sound_name in SFX:
		sounds[sound_name] = make_sound(SFX[sound_name])
	apply_settings()


func create_audio_buses() -> void:
	# Canale separate pentru Muzică și Efecte, ca să aibă volume diferite.
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")


func apply_settings() -> void:
	var settings: Dictionary = GameState.settings
	set_bus_volume("Master", float(settings["master"]))
	set_bus_volume("Music", float(settings["music"]))
	set_bus_volume("SFX", float(settings["sfx"]))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), bool(settings.get("muted", false)))


func set_bus_volume(bus_name: String, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		# volumul din setări e 0..1, dar Godot vrea decibeli
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))


# =====================================================================
#  EFECTE SONORE
# =====================================================================
func play(sound_name: String, pitch: float = 1.0, random_pitch: float = 0.06) -> void:
	if not sounds.has(sound_name):
		return
	# Luăm pe rând câte un player, ca mai multe sunete să se poată suprapune.
	var player := sfx_players[next_sfx_player]
	next_sfx_player = (next_sfx_player + 1) % sfx_players.size()
	player.stream = sounds[sound_name]
	# o mică variație de ton, ca sunetele repetate să nu sune robotic
	player.pitch_scale = clampf(pitch + randf_range(-random_pitch, random_pitch), 0.3, 3.0)
	player.play()


# =====================================================================
#  MUZICĂ
# =====================================================================
func play_music(theme: String) -> void:
	if custom_player.playing:
		music_after_custom = theme    # așteptăm să se termine melodia ta
		return
	if theme == current_music and music_player.playing:
		return
	# Dacă ai pus o melodie cu numele temei (ex: assets/audio/menu.mp3), o folosim pe ea.
	var your_track := find_custom_track(theme)
	if your_track:
		current_music = theme
		music_player.stream = your_track
		music_player.volume_db = CUSTOM_MUSIC_VOLUME.get(theme, -6.0)
		music_player.play()
		return
	if not MUSIC.has(theme):
		return
	if not music_cache.has(theme):
		music_cache[theme] = make_music(theme)
	current_music = theme
	music_player.stream = music_cache[theme]
	music_player.volume_db = 0.0
	music_player.play()


func stop_music() -> void:
	current_music = ""
	music_player.stop()
	custom_player.stop()
	music_after_custom = ""


func on_music_finished() -> void:
	if current_music != "":
		music_player.play()   # buclă


func find_custom_track(track_name: String) -> AudioStream:
	for extension in CUSTOM_EXTENSIONS:
		var path: String = CUSTOM_DIR + track_name + "." + extension
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream:
				return stream
	return null


## Cântă melodia ta res://assets/audio/<nume>.(ogg|mp3|wav), dacă există.
## Întoarce false dacă nu există, ca apelantul să folosească un sunet generat.
func play_custom(track_name: String, then_music: String = "") -> bool:
	var stream := find_custom_track(track_name)
	if stream == null:
		return false
	current_music = ""
	music_player.stop()
	music_after_custom = then_music
	custom_player.stream = stream
	custom_player.play()
	return true


func custom_playing() -> bool:
	return custom_player.playing


func on_custom_finished() -> void:
	if music_after_custom != "":
		var theme := music_after_custom
		music_after_custom = ""
		play_music(theme)


# =====================================================================
#  SINTEZA SUNETULUI (generăm unda sonoră număr cu număr)
# =====================================================================
func wave_value(wave: String, phase: float) -> float:
	# Valoarea undei (între -1 și 1) într-un punct al ciclului.
	var position_in_cycle := fposmod(phase, 1.0)
	if wave == "sine":
		return sin(phase * TAU)
	if wave == "square":
		if position_in_cycle < 0.5:
			return 1.0
		return -1.0
	if wave == "saw":
		return position_in_cycle * 2.0 - 1.0
	if wave == "tri":
		return absf(position_in_cycle * 4.0 - 2.0) - 1.0
	if wave == "noise":
		return randf() * 2.0 - 1.0
	return 0.0


func make_sound(pieces: Array) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	for piece in pieces:
		var start_freq := float(piece[0])
		var end_freq := float(piece[1])
		var duration := float(piece[2])
		var wave := str(piece[3])
		var volume := float(piece[4])
		var count := int(duration * SAMPLE_RATE)
		var phase := 0.0
		for i in count:
			var progress := float(i) / count
			phase += lerpf(start_freq, end_freq, progress) / SAMPLE_RATE   # tonul alunecă
			# "anvelopa": pornește rapid și se stinge treptat
			var fade := minf(1.0, i / (SAMPLE_RATE * 0.004)) * pow(1.0 - progress, 1.4)
			samples.append(wave_value(wave, phase) * fade * volume)
	return samples_to_wav(samples)


func make_music(theme: String) -> AudioStreamWAV:
	# O buclă de 64 de optimi: bas + melodie + tobe. Seed-ul fix face ca
	# fiecare temă să aibă mereu aceeași melodie.
	var config: Array = MUSIC[theme]
	var root_freq: float = config[0]
	var notes: Array = config[1]
	var bpm: float = config[2]
	var lead_wave: String = config[3]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(theme)
	var steps := 64
	var samples_per_step := int(60.0 / bpm / 2.0 * SAMPLE_RATE)   # durata unei optimi
	var buffer := PackedFloat32Array()
	buffer.resize(samples_per_step * steps)
	var melody := make_melody(rng, notes, steps)
	var chords := [0, 3, 4, 2]
	for step in steps:
		var chord: int = chords[int(step / 16.0)] % notes.size()
		var bass_freq := root_freq * 0.5 * pow(2.0, float(notes[chord]) / 12.0)
		var note := melody[step]
		var melody_freq := root_freq * 2.0 * pow(2.0, note / 12.0)
		for i in samples_per_step:
			var t := float(i) / SAMPLE_RATE
			var value := music_sample(t, step, bass_freq, note, melody_freq, lead_wave)
			buffer[step * samples_per_step + i] = clampf(value, -1.0, 1.0)
	return samples_to_wav(buffer)


func make_melody(rng: RandomNumberGenerator, notes: Array, steps: int) -> Array[int]:
	# -100 înseamnă pauză (nicio notă).
	var melody: Array[int] = []
	for step in steps:
		if rng.randf() < 0.72:
			var note := int(notes[rng.randi_range(0, notes.size() - 1)])
			melody.append(note + 12 * rng.randi_range(0, 1))
		else:
			melody.append(-100)
	# a doua jumătate repetă prima, ca bucla să aibă un "refren"
	for step in range(32, 64):
		if step % 8 < 6:
			melody[step] = melody[step - 32]
	return melody


func music_sample(t: float, step: int, bass_freq: float, note: int, melody_freq: float, lead_wave: String) -> float:
	var value := 0.0
	# bas
	var bass := -1.0
	if fposmod(t * bass_freq, 1.0) < 0.5:
		bass = 1.0
	value += bass * 0.1 * exp(-t * 2.5)
	# melodia
	if note > -50:
		value += wave_value(lead_wave, t * melody_freq) * 0.13 * exp(-t * 5.0)
	# tobe: toba mare pe timpii 1 și 3, toba mică pe 2 și 4
	if step % 4 == 0:
		value += sin(TAU * (55.0 * t + 6.0 * (1.0 - exp(-t * 30.0)))) * exp(-t * 18.0) * 0.55
	elif step % 4 == 2:
		value += (randf() * 2.0 - 1.0) * exp(-t * 28.0) * 0.16
	# hi-hat (un mic zgomot pe fiecare pas)
	value += (randf() * 2.0 - 1.0) * exp(-t * 120.0) * 0.05
	return value


func samples_to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	# Transformăm numerele (-1..1) în format WAV pe 16 biți.
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav
