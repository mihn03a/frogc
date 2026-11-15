extends Node
## =====================================================================
##  GAME_STATE.GD - "creierul" jocului (autoload: GameState)
## =====================================================================
##  Un autoload e un script care există mereu, în toate scenele.
##  Aici ținem tot ce trebuie să supraviețuiască schimbării scenei:
##   - scorul, combo-ul, viața, nivelul curent, upgrade-urile
##   - setările și progresul salvat (skin-uri, realizări, high scores)
##   - trecerea de la o scenă la alta (meniu -> nivel -> evoluție ...)
##
##  Alte scripturi află ce s-a schimbat ascultând SEMNALELE de mai jos
##  (de exemplu HUD-ul ascultă score_changed ca să afișeze scorul).
## =====================================================================

signal score_changed(score: int)
signal combo_changed(combo: int, multiplier: float)
signal health_changed(hp: float, max_hp: float)
signal evo_points_changed(points: int)
signal boss_health_changed(hp: float, max_hp: float)
signal show_message(text: String, color: Color)          # mesaj mare pe ecran
signal achievement_unlocked(id: String, title: String)
signal mute_changed(muted: bool)

# ---------------------------------------------------------------- scenele
const LEVEL_SCENE := "res://scenes/levels/level.tscn"
const MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"
const EVOLUTION_SCENE := "res://scenes/ui/evolution_screen.tscn"
const GAME_OVER_SCENE := "res://scenes/ui/game_over.tscn"
const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const LOBBY_SCENE := "res://scenes/battle/lobby.tscn"
const VICTORY_SCENE := "res://scenes/ui/victory.tscn"

# ---------------------------------------------------------------- nivelurile și evoluțiile
const LEVEL_NAMES := ["STEAGU", "BUNLOC", "TRACTORUL", "CODLEA", "GHIMBAV"]
const LEVEL_THEMES := ["valley", "valley", "lava", "lava", "cyber"]
const STAGE_NAMES := ["Tadpole Flyer", "Sky Hopper", "Iron Croaker", "Twin-Jet Toad", "Cyber Frog X"]
const STAGE_ABILITIES := [
	"BOUNCE BRACE: press SPACE right before impact for a PERFECT BOUNCE.",
	"KEEN EYES: bigger wings and a wider Perfect Bounce window.",
	"LAVA ARMOR: armor plates reduce all damage you take.",
	"TURBO HOP: press SHIFT in the air for an upward jet burst.",
	"PLASMA SHOCKWAVE: Perfect Bounces blast every nearby enemy.",
]
const BASE_HP := [100.0, 120.0, 145.0, 170.0, 200.0]   # viața de bază pe fiecare evoluție
const ARMOR := [1.0, 0.9, 0.78, 0.7, 0.62]             # cât din damage primești (1 = tot)
const UPGRADE_COST := 12
const UPGRADE_MAX := 3
const LEVEL_HEAL := 0.35      # la începutul unui nivel nou primești înapoi 35% din viață

const SAVE_PATH := "user://frogc_save.cfg"

# Dificultatea: cât damage primești, cât de larg e Perfect-ul, cât scor primești
const DIFFICULTIES := {
	"easy": {"name": "EASY", "damage": 0.85, "window": 0.05, "score": 0.8},
	"normal": {"name": "NORMAL", "damage": 1.15, "window": 0.0, "score": 1.0},
	"hard": {"name": "HARD", "damage": 1.8, "window": -0.04, "score": 1.5},
}

# Skin-uri pentru broască, deblocate jucând. color / emission (strălucire) / metal
const SKINS := [
	{"id": "classic", "name": "CLASSIC", "color": Color(0.36, 0.8, 0.26), "emission": 0.0, "metal": 0.0, "req": "Unlocked from the start"},
	{"id": "ocean", "name": "OCEAN", "color": Color(0.2, 0.55, 0.95), "emission": 0.0, "metal": 0.0, "req": "Complete Level 1"},
	{"id": "lava", "name": "LAVA TOAD", "color": Color(1.0, 0.42, 0.1), "emission": 0.25, "metal": 0.0, "req": "Reach Tractorul (level 3)"},
	{"id": "shadow", "name": "SHADOW", "color": Color(0.32, 0.18, 0.5), "emission": 0.0, "metal": 0.2, "req": "25 Perfect Bounces in one run"},
	{"id": "neon", "name": "NEON", "color": Color(0.1, 1.0, 0.85), "emission": 1.2, "metal": 0.0, "req": "Reach Ghimbav (level 5)"},
	{"id": "golden", "name": "GOLDEN FROG", "color": Color(1.0, 0.78, 0.2), "emission": 0.1, "metal": 0.9, "req": "Defeat The Big Nic"},
]

const ACHIEVEMENTS := [
	{"id": "first_hop", "title": "FIRST HOP", "desc": "Bounce for the first time"},
	{"id": "perfect_10", "title": "PERFECTIONIST", "desc": "10 Perfect Bounces in one run"},
	{"id": "combo_20", "title": "COMBO CROAKER", "desc": "Reach a x20 combo"},
	{"id": "comeback", "title": "BOUNCE BACK!", "desc": "Do a Comeback Bounce right after getting hit"},
	{"id": "untouchable", "title": "UNTOUCHABLE", "desc": "Finish a level without taking damage"},
	{"id": "power_hungry", "title": "POWER HUNGRY", "desc": "Use all 4 power-ups in one run"},
	{"id": "fly_swatter", "title": "FLY SWATTER", "desc": "Splat 25 enemies in one run"},
	{"id": "high_roller", "title": "HIGH ROLLER", "desc": "Score 50,000 points in one run"},
	{"id": "emperor_down", "title": "BIG NIC DOWN", "desc": "Defeat The Big Nic"},
	{"id": "hard_hero", "title": "IRON FROG", "desc": "Defeat the boss on HARD"},
	{"id": "frog_poke", "title": "PLEASE STOP", "desc": "Poke the frog in the main menu 20 times"},
	{"id": "dress_code", "title": "DRESS CODE", "desc": "Find the secret in the victory scene"},
]

# ---------------------------------------------------------------- starea partidei curente
var current_level: int = 1
var score: int = 0
var score_at_level_start: int = 0
var combo: int = 0
var highest_combo: int = 0
var perfect_count: int = 0
var levels_completed: int = 0
var enemies_defeated: int = 0
var evo_points: int = 0        # puncte de evoluție, cheltuite pe upgrade-uri
var upg_health: int = 0
var upg_bounce: int = 0
var upg_timing: int = 0
var hp: float = 100.0
var boss_defeated: bool = false
var player_dead: bool = false
var run_powerups := {}         # ce power-up-uri ai folosit în partida asta
var damage_this_level := false
var run_recorded := false      # scorul a fost deja salvat în High Scores?
var hp_at_level_start := 100.0
var is_fresh_run := true       # primul nivel al unei partide noi?

# ---------------------------------------------------------------- setări și progres salvat
var settings := {"master": 0.8, "music": 0.55, "sfx": 0.8, "shake": true, "fullscreen": false, "show_fps": false, "difficulty": "normal", "muted": false, "low_graphics": false}
var save := {"best_level": 1, "skin": "classic", "skins": ["classic"], "achievements": [], "high_scores": [], "pokes": 0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # merge și când jocul e pe pauză
	# Performanță: fără anti-aliasing MSAA (foarte greu pe plăcile video integrate).
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	setup_controls()
	load_save()


# =====================================================================
#  TASTELE (le definim din cod, ca să nu depindem de project.godot)
# =====================================================================
func setup_controls() -> void:
	add_keys("move_left", [KEY_A, KEY_LEFT])
	add_keys("move_right", [KEY_D, KEY_RIGHT])
	add_keys("move_up", [KEY_W, KEY_UP])
	add_keys("move_down", [KEY_S, KEY_DOWN])
	add_keys("bounce", [KEY_SPACE])
	add_keys("turbo", [KEY_SHIFT])
	add_keys("pause", [KEY_ESCAPE, KEY_P])
	add_keys("mute", [KEY_M])
	# controller (gamepad)
	add_gamepad_button("bounce", JOY_BUTTON_A)
	add_gamepad_button("turbo", JOY_BUTTON_B)
	add_gamepad_button("pause", JOY_BUTTON_START)
	add_gamepad_stick("move_left", JOY_AXIS_LEFT_X, -1.0)
	add_gamepad_stick("move_right", JOY_AXIS_LEFT_X, 1.0)
	add_gamepad_stick("move_up", JOY_AXIS_LEFT_Y, -1.0)
	add_gamepad_stick("move_down", JOY_AXIS_LEFT_Y, 1.0)


func add_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


func add_gamepad_button(action: String, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


func add_gamepad_stick(action: String, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)


# =====================================================================
#  STATISTICILE BROAȘTEI (depind de evoluție și upgrade-uri)
# =====================================================================
func stage() -> int:
	# Evoluția = numărul nivelului (1..5)
	return clampi(current_level, 1, 5)


func max_hp() -> float:
	return BASE_HP[stage() - 1] + upg_health * 20.0


func armor() -> float:
	return ARMOR[stage() - 1]


func bounce_power() -> float:
	return 1.0 + (stage() - 1) * 0.05 + upg_bounce * 0.08


func perfect_window() -> float:
	# Câte secunde înainte de impact poți apăsa SPACE ca să fie Perfect.
	var window := 0.15 + upg_timing * 0.025 + float(difficulty()["window"])
	if stage() >= 2:
		window += 0.05   # abilitatea "Keen Eyes"
	return window


func combo_multiplier() -> float:
	# La fiecare 5 sărituri la rând, multiplicatorul crește cu 0.5 (max x5).
	return minf(1.0 + floorf(combo / 5.0) * 0.5, 5.0)


func difficulty() -> Dictionary:
	return DIFFICULTIES.get(settings["difficulty"], DIFFICULTIES["normal"])


func damage_mult() -> float:
	return float(difficulty()["damage"])


# =====================================================================
#  SCOR, COMBO, VIAȚĂ
# =====================================================================
## Adaugă puncte (înmulțite cu combo-ul și dificultatea). Întoarce cât s-a adăugat.
func add_score(base: int) -> int:
	var points := int(round(base * combo_multiplier() * float(difficulty()["score"])))
	score += points
	score_changed.emit(score)
	if score >= 50000:
		unlock("high_roller")
	return points


## Adaugă puncte fără multiplicatori (bonusuri fixe).
func add_raw_score(points: int) -> void:
	score += points
	score_changed.emit(score)


func add_combo(amount: int = 1) -> void:
	combo += amount
	highest_combo = maxi(highest_combo, combo)
	if combo >= 20:
		unlock("combo_20")
	combo_changed.emit(combo, combo_multiplier())


func reset_combo() -> void:
	if combo == 0:
		return
	combo = 0
	combo_changed.emit(combo, combo_multiplier())


func add_evo(amount: int) -> void:
	evo_points += amount
	evo_points_changed.emit(evo_points)


func set_hp(value: float) -> void:
	hp = clampf(value, 0.0, max_hp())
	health_changed.emit(hp, max_hp())


## Cumpără un upgrade ("health", "bounce" sau "timing"). Întoarce true dacă a reușit.
func buy_upgrade(kind: String) -> bool:
	if evo_points < UPGRADE_COST:
		return false
	if kind == "health" and upg_health < UPGRADE_MAX:
		upg_health += 1
	elif kind == "bounce" and upg_bounce < UPGRADE_MAX:
		upg_bounce += 1
	elif kind == "timing" and upg_timing < UPGRADE_MAX:
		upg_timing += 1
	else:
		return false
	evo_points -= UPGRADE_COST
	evo_points_changed.emit(evo_points)
	return true


func rating() -> String:
	if score >= 70000:
		return "S - LEGENDARY FROG"
	if score >= 45000:
		return "A - ACE PILOT"
	if score >= 25000:
		return "B - BOUNCY"
	if score >= 12000:
		return "C - TADPOLE"
	return "D - KEEP HOPPING"


# =====================================================================
#  CURSUL JOCULUI (partidă nouă, nivel, final)
# =====================================================================
func new_run() -> void:
	current_level = 1
	score = 0
	score_at_level_start = 0
	combo = 0
	highest_combo = 0
	perfect_count = 0
	levels_completed = 0
	enemies_defeated = 0
	evo_points = 0
	upg_health = 0
	upg_bounce = 0
	upg_timing = 0
	boss_defeated = false
	player_dead = false
	run_powerups = {}
	run_recorded = false
	is_fresh_run = true
	hp = max_hp()


func start_level(number: int) -> void:
	current_level = clampi(number, 1, 5)
	score_at_level_start = score
	combo = 0
	boss_defeated = false
	player_dead = false
	damage_this_level = false
	# Viața se păstrează între niveluri, cu o vindecare parțială - deci damage-ul contează.
	if is_fresh_run:
		hp = max_hp()
		is_fresh_run = false
	else:
		hp = minf(max_hp(), hp + max_hp() * LEVEL_HEAL)
	hp_at_level_start = hp
	if current_level > int(save["best_level"]):
		save["best_level"] = current_level
		write_save()
	change_scene(LEVEL_SCENE)


func restart_level() -> void:
	score = score_at_level_start
	hp = hp_at_level_start - max_hp() * LEVEL_HEAL   # start_level adaugă vindecarea înapoi
	start_level(current_level)


func complete_level() -> void:
	levels_completed = maxi(levels_completed, current_level)
	add_raw_score(1000 * current_level)
	if not damage_this_level:
		unlock("untouchable")
	unlock_skins_for_level()
	save["best_level"] = maxi(int(save["best_level"]), mini(current_level + 1, 5))
	write_save()
	if current_level < 5:
		current_level += 1
		change_scene(EVOLUTION_SCENE)


func unlock_skins_for_level() -> void:
	unlock_skin("ocean")
	if current_level >= 2:
		unlock_skin("lava")
	if current_level >= 4:
		unlock_skin("neon")


func on_boss_defeated() -> void:
	boss_defeated = true
	levels_completed = 5
	add_raw_score(10000)
	unlock("emperor_down")
	unlock_skin("golden")
	if settings["difficulty"] == "hard":
		unlock("hard_hero")


func on_player_died() -> void:
	player_dead = true
	change_scene(GAME_OVER_SCENE)


func go_victory() -> void:
	change_scene(VICTORY_SCENE)


func go_main_menu() -> void:
	change_scene(MENU_SCENE)


func change_scene(path: String) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0   # oprim slow-motion-ul, dacă era pornit
	get_tree().call_deferred("change_scene_to_file", path)


# =====================================================================
#  SUNET ȘI SETĂRI
# =====================================================================
func _unhandled_input(event: InputEvent) -> void:
	# Tasta M merge peste tot (meniuri, niveluri, battle).
	if event.is_action_pressed("mute"):
		toggle_mute()


func toggle_mute() -> void:
	settings["muted"] = not bool(settings["muted"])
	apply_settings()
	mute_changed.emit(settings["muted"])
	if settings["muted"]:
		show_message.emit("SOUND OFF", Color(0.8, 0.9, 1.0))
	else:
		show_message.emit("SOUND ON", Color(0.8, 0.9, 1.0))


func apply_settings() -> void:
	write_save()
	AudioManager.apply_settings()
	if settings["fullscreen"]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


# =====================================================================
#  EVENIMENTE DIN JOC (verifică realizările)
# =====================================================================
func on_bounce() -> void:
	unlock("first_hop")


func on_perfect() -> void:
	if perfect_count >= 10:
		unlock("perfect_10")
	if perfect_count >= 25:
		unlock_skin("shadow")


func on_comeback() -> void:
	unlock("comeback")


func on_powerup(kind: String) -> void:
	run_powerups[kind] = true
	if run_powerups.size() >= 4:
		unlock("power_hungry")


func on_enemy_defeated() -> void:
	enemies_defeated += 1
	if enemies_defeated >= 25:
		unlock("fly_swatter")


## Broasca din meniu a fost apăsată. Întoarce de câte ori în total.
func add_poke() -> int:
	save["pokes"] = int(save["pokes"]) + 1
	if int(save["pokes"]) >= 20:
		unlock("frog_poke")
	write_save()
	return int(save["pokes"])


# =====================================================================
#  REALIZĂRI ȘI SKIN-URI
# =====================================================================
func has_achievement(id: String) -> bool:
	var unlocked: Array = save["achievements"]
	return unlocked.has(id)


func unlock(id: String) -> void:
	if has_achievement(id):
		return
	var unlocked: Array = save["achievements"]
	unlocked.append(id)
	write_save()
	for achievement in ACHIEVEMENTS:
		if achievement["id"] == id:
			achievement_unlocked.emit(id, achievement["title"])
			return


func skin_unlocked(id: String) -> bool:
	var unlocked: Array = save["skins"]
	return unlocked.has(id)


func unlock_skin(id: String) -> void:
	if skin_unlocked(id):
		return
	var unlocked: Array = save["skins"]
	unlocked.append(id)
	write_save()
	for skin in SKINS:
		if skin["id"] == id:
			show_message.emit("NEW SKIN: " + str(skin["name"]), Color(1.0, 0.85, 0.3))


func current_skin() -> Dictionary:
	for skin in SKINS:
		if skin["id"] == save["skin"]:
			return skin
	return SKINS[0]


func select_skin(id: String) -> void:
	if skin_unlocked(id):
		save["skin"] = id
		write_save()


# =====================================================================
#  HIGH SCORES
# =====================================================================
## Salvează partida terminată. Întoarce locul ei (1 = cel mai bun) sau 0 dacă nu e în top 5.
func record_run() -> int:
	if run_recorded or score <= 0:
		return 0
	run_recorded = true
	var entry := {
		"score": score,
		"rating": rating().split(" ")[0],       # doar litera (S, A, B...)
		"level": maxi(levels_completed, current_level),
		"difficulty": str(difficulty()["name"]),
		"won": boss_defeated,
		"date": Time.get_date_string_from_system(),
	}
	var list: Array = save["high_scores"]
	list.append(entry)
	list.sort_custom(higher_score_first)
	while list.size() > 5:
		list.pop_back()
	save["high_scores"] = list
	write_save()
	return list.find(entry) + 1


func higher_score_first(a: Dictionary, b: Dictionary) -> bool:
	return int(a["score"]) > int(b["score"])


func best_score() -> int:
	var list: Array = save["high_scores"]
	if list.is_empty():
		return 0
	return int(list[0]["score"])


# =====================================================================
#  SALVARE ȘI ÎNCĂRCARE (fișier pe disc)
# =====================================================================
func write_save() -> void:
	var file := ConfigFile.new()
	for key in save:
		file.set_value("progress", key, save[key])
	for key in settings:
		file.set_value("settings", key, settings[key])
	file.save(SAVE_PATH)


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		return
	for key in save.keys():
		save[key] = file.get_value("progress", key, save[key])
	for key in settings.keys():
		settings[key] = file.get_value("settings", key, settings[key])


func reset_progress() -> void:
	save = {"best_level": 1, "skin": "classic", "skins": ["classic"], "achievements": [], "high_scores": [], "pokes": 0}
	write_save()
