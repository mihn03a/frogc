extends CanvasLayer
## =====================================================================
##  HUD.GD - informațiile de pe ecran în timpul jocului
## =====================================================================
##   stânga-sus:   viața, punctele de evoluție, turbo
##   centru-sus:   numele nivelului, progresul, bara boss-ului
##   dreapta-sus:  scorul
##   stânga:       combo-ul și multiplicatorul
##   jos-centru:   inelul de timing pentru Perfect Bounce
##   jos-stânga:   power-up-urile active, cu cronometru
##   centru:       mesajele mari ("PERFECT BOUNCE!", "OUCH!" ...)
##
##  HUD-ul ascultă semnalele din GameState și se actualizează singur.
## =====================================================================

const UI = preload("res://scripts/ui/ui_style.gd")
const PlayerScript = preload("res://scripts/player/player.gd")
const POWERUP_ICONS := {
	"shield": ["SH", Color(0.3, 0.9, 1.0)], "super": ["SB", Color(1.0, 0.6, 0.1)],
	"speed": ["SP", Color(1.0, 0.3, 0.35)], "magnet": ["MG", Color(0.8, 0.4, 1.0)],
}


## Inelul de timing: cercul exterior se micșorează pe măsură ce te apropii
## de o suprafață. Când ajunge la cercul verde, apasă SPACE.
class TimingRing extends Control:
	const OUTER := 52.0     # raza cercului mare
	const TARGET := 20.0    # raza cercului verde (ținta)
	var player
	var flash := 0.0        # strălucirea după un Perfect

	func _process(delta: float) -> void:
		flash = maxf(flash - delta * 2.5, 0.0)
		queue_redraw()   # redesenăm în fiecare cadru

	func _draw() -> void:
		var center := get_size() / 2.0
		draw_circle(center, OUTER + 6.0, Color(0, 0, 0, 0.35))
		draw_arc(center, OUTER, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		draw_circle(center, TARGET, Color(0.2, 1.0, 0.6, 0.25 + flash * 0.6))
		draw_arc(center, TARGET, 0.0, TAU, 32, Color(0.3, 1.0, 0.7), 3.0)
		var text := "SPACE"
		var text_color := Color(1, 1, 1, 0.6)
		if player != null and is_instance_valid(player):
			if player.is_braced():
				draw_circle(center, TARGET * 0.6, Color(1, 1, 1, 0.5))
			var time_left: float = player.time_to_impact
			var window: float = GameState.perfect_window()
			if time_left >= 0.0 and time_left < 0.8:
				var in_window := time_left <= window
				var danger: bool = player.impact_is_danger   # dedesubt e apă sau lavă
				var ring_color := Color(1.0, 0.85, 0.2)
				if danger:
					ring_color = Color(1.0, 0.3, 0.2)
					text = "DANGER!"
					text_color = Color(1.0, 0.45, 0.35)
				if in_window:
					text = "NOW!"
					if danger:
						text_color = Color(1.0, 0.45, 0.35)   # roșu: salvează-te!
					else:
						ring_color = Color(0.3, 1.0, 0.5)
						text_color = Color(0.4, 1.0, 0.6)
				draw_arc(center, ring_radius(time_left, window), 0.0, TAU, 40, ring_color, 6.0)
		if flash > 0.0:
			text = "PERFECT!"
			text_color = Color(0.4, 1.0, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(0, center.y + OUTER + 30.0), text, HORIZONTAL_ALIGNMENT_CENTER, get_size().x, 22, text_color)

	func ring_radius(time_left: float, window: float) -> float:
		# Înainte de fereastra Perfect: inelul coboară de la cercul mare la cel verde.
		if time_left > window:
			var progress := clampf((time_left - window) / (0.8 - window), 0.0, 1.0)
			return TARGET + (OUTER - TARGET) * progress
		# În fereastra Perfect: se strânge în interiorul cercului verde.
		return TARGET * clampf(time_left / window, 0.15, 1.0)


## Iconița unui power-up, cu un arc care arată cât timp a mai rămas.
class PowerIcon extends Control:
	var color := Color.WHITE
	var letters := "S"
	var time_fraction := 1.0   # 1 = plin, 0 = s-a terminat

	func _draw() -> void:
		var center := get_size() / 2.0
		draw_circle(center, 30.0, Color(0, 0, 0, 0.5))
		draw_circle(center, 24.0, color)
		draw_arc(center, 30.0, -PI / 2.0, -PI / 2.0 + TAU * time_fraction, 32, color.lightened(0.5), 5.0)
		draw_string(ThemeDB.fallback_font, Vector2(0, center.y + 9.0), letters, HORIZONTAL_ALIGNMENT_CENTER, get_size().x, 24, Color(0.05, 0.05, 0.05))


var player
var level_length := 500.0
var screen: Control
var hp_bar: ProgressBar
var hp_label: Label
var evo_label: Label
var turbo_label: Label
var score_label: Label
var level_label: Label
var progress_bar: ProgressBar
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var combo_label: Label
var multiplier_label: Label
var timing_ring: TimingRing
var powerup_icons := {}     # tip -> [cutia, iconița]
var message_label: Label
var message_tween: Tween
var achievement_label: Label
var fps_label: Label


# =====================================================================
#  PORNIRE
# =====================================================================
func _ready() -> void:
	layer = 10
	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	create_health_area()
	create_level_area()
	create_score()
	create_combo()
	create_timing_ring()
	create_powerup_icons()
	create_message_texts()
	create_controls_hint()
	connect_signals()


## Apelată de level.gd după ce creează jucătorul.
func setup(the_player, length: float) -> void:
	player = the_player
	level_length = length
	timing_ring.player = the_player
	the_player.bounced.connect(on_bounced)
	# afișăm valorile actuale
	on_health_changed(GameState.hp, GameState.max_hp())
	on_score_changed(GameState.score)
	on_combo_changed(GameState.combo, GameState.combo_multiplier())
	on_evo_changed(GameState.evo_points)


func connect_signals() -> void:
	GameState.score_changed.connect(on_score_changed)
	GameState.combo_changed.connect(on_combo_changed)
	GameState.health_changed.connect(on_health_changed)
	GameState.evo_points_changed.connect(on_evo_changed)
	GameState.boss_health_changed.connect(on_boss_health_changed)
	GameState.show_message.connect(on_message)
	GameState.achievement_unlocked.connect(on_achievement)


# =====================================================================
#  CONSTRUCȚIA ELEMENTELOR
# =====================================================================
func create_health_area() -> void:
	var column := VBoxContainer.new()
	column.position = Vector2(24, 18)
	screen.add_child(column)
	var hp_row := HBoxContainer.new()
	column.add_child(hp_row)
	hp_row.add_child(UI.label("HP", 30, UI.YELLOW))
	hp_bar = UI.bar(Color(0.35, 0.9, 0.3), Vector2(320, 30))
	hp_row.add_child(hp_bar)
	hp_label = UI.label("100/100", 22)
	hp_row.add_child(hp_label)
	evo_label = left_label("EVO 0", 22, Color(0.6, 1.0, 1.0))
	column.add_child(evo_label)
	turbo_label = left_label("", 20, Color(1.0, 0.7, 0.3))
	column.add_child(turbo_label)
	fps_label = UI.label("", 18, Color(1, 1, 1, 0.8), 6)
	fps_label.position = Vector2(24, 140)
	screen.add_child(fps_label)


func create_level_area() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	column.offset_left = -260
	column.offset_right = 260
	column.offset_top = 14
	screen.add_child(column)
	level_label = UI.label("LEVEL %d - %s" % [GameState.current_level, GameState.LEVEL_NAMES[GameState.current_level - 1]], 30, UI.YELLOW)
	column.add_child(level_label)
	progress_bar = UI.bar(Color(1.0, 0.85, 0.2), Vector2(520, 12))
	progress_bar.value = 0
	column.add_child(progress_bar)
	boss_box = VBoxContainer.new()
	boss_box.visible = false
	column.add_child(boss_box)
	boss_box.add_child(UI.label("THE BIG NIC", 28, Color(1.0, 0.45, 0.8)))
	boss_bar = UI.bar(Color(0.9, 0.2, 0.6), Vector2(520, 26))
	boss_box.add_child(boss_bar)


func create_score() -> void:
	score_label = UI.label("0", 46, Color.WHITE)
	score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	score_label.offset_left = -420
	score_label.offset_right = -24
	score_label.offset_top = 12
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	screen.add_child(score_label)


func create_combo() -> void:
	combo_label = left_label("", 54, Color(1.0, 0.6, 0.2), 14)
	combo_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	combo_label.offset_left = 30
	combo_label.offset_right = 380
	screen.add_child(combo_label)
	multiplier_label = left_label("", 34, UI.YELLOW)
	multiplier_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	multiplier_label.offset_left = 34
	multiplier_label.offset_right = 380
	multiplier_label.offset_top = 40
	multiplier_label.offset_bottom = 90
	screen.add_child(multiplier_label)


func create_timing_ring() -> void:
	timing_ring = TimingRing.new()
	timing_ring.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	timing_ring.offset_left = -80
	timing_ring.offset_right = 80
	timing_ring.offset_top = -190
	timing_ring.offset_bottom = -30
	timing_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(timing_ring)


func create_powerup_icons() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	row.offset_left = 24
	row.offset_top = -110
	row.offset_bottom = -24
	row.add_theme_constant_override("separation", 14)
	screen.add_child(row)
	for kind in POWERUP_ICONS:
		var letters: String = POWERUP_ICONS[kind][0]
		var color: Color = POWERUP_ICONS[kind][1]
		var icon := PowerIcon.new()
		icon.custom_minimum_size = Vector2(70, 70)
		icon.letters = letters
		icon.color = color
		var box := VBoxContainer.new()
		box.add_child(icon)
		box.add_child(UI.label(str(kind).to_upper(), 16, color, 6))
		box.visible = false
		row.add_child(box)
		powerup_icons[kind] = [box, icon]


func create_message_texts() -> void:
	message_label = UI.label("", 64, Color.WHITE, 16)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	message_label.offset_left = -600
	message_label.offset_right = 600
	message_label.offset_top = -200
	message_label.offset_bottom = -100
	message_label.pivot_offset = Vector2(600, 50)
	screen.add_child(message_label)
	achievement_label = UI.label("", 34, Color(1.0, 0.85, 0.3), 10)
	achievement_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	achievement_label.offset_left = -500
	achievement_label.offset_right = 500
	achievement_label.offset_top = 130
	achievement_label.offset_bottom = 180
	achievement_label.modulate.a = 0.0
	screen.add_child(achievement_label)


func create_controls_hint() -> void:
	var hint := UI.label("A/D steer   W glide   S dive   SPACE bounce   ESC pause", 18, Color(1, 1, 1, 0.7), 6)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -700
	hint.offset_right = -20
	hint.offset_top = -40
	hint.offset_bottom = -10
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	screen.add_child(hint)


func left_label(text: String, font_size: int, color: Color, outline: int = 10) -> Label:
	var new_label := UI.label(text, font_size, color, outline)
	new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return new_label


# =====================================================================
#  ÎN FIECARE CADRU
# =====================================================================
func _process(_delta: float) -> void:
	if GameState.settings["show_fps"]:
		fps_label.text = "FPS %d" % Engine.get_frames_per_second()
	else:
		fps_label.text = ""
	if player == null or not is_instance_valid(player):
		return
	update_powerup_icons()
	if player.mode == "run":
		var progress: float = -player.global_position.z / level_length
		progress_bar.value = clampf(progress, 0.0, 1.0) * 100.0
	if GameState.stage() >= 4:
		if player.turbo_ready():
			turbo_label.text = "TURBO HOP [SHIFT]: READY"
		else:
			turbo_label.text = "TURBO HOP [SHIFT]: ..."


func update_powerup_icons() -> void:
	for kind in powerup_icons:
		var time_left: float = player.powerups[kind]
		var box: Control = powerup_icons[kind][0]
		var icon: PowerIcon = powerup_icons[kind][1]
		box.visible = time_left > 0.0
		if time_left > 0.0:
			icon.time_fraction = time_left / float(PlayerScript.POWERUP_TIME[kind])
			icon.queue_redraw()


# =====================================================================
#  REACȚII LA SEMNALE
# =====================================================================
func show_boss_bar(on: bool) -> void:
	boss_box.visible = on
	progress_bar.visible = not on


func on_bounced(perfect: bool) -> void:
	if perfect:
		timing_ring.flash = 1.0


func on_health_changed(hp: float, max_hp: float) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_label.text = "%d/%d" % [int(ceil(hp)), int(max_hp)]


func on_score_changed(score: int) -> void:
	score_label.text = str(score)


func on_evo_changed(points: int) -> void:
	evo_label.text = "EVOLUTION POINTS: %d" % points


func on_combo_changed(combo: int, multiplier: float) -> void:
	if combo <= 1:
		combo_label.text = ""
		multiplier_label.text = ""
		return
	combo_label.text = "COMBO x%d" % combo
	multiplier_label.text = "SCORE x%.1f" % multiplier
	# textul "sare" puțin la fiecare combo
	combo_label.pivot_offset = Vector2(0, 30)
	combo_label.scale = Vector2(1.35, 1.35)
	var tween := create_tween()
	tween.tween_property(combo_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func on_boss_health_changed(hp: float, max_hp: float) -> void:
	show_boss_bar(true)
	boss_bar.max_value = max_hp
	boss_bar.value = hp


func on_message(text: String, color: Color) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", color)
	message_label.modulate.a = 1.0
	message_label.scale = Vector2(0.4, 0.4)
	# dacă un mesaj vechi încă dispare, îl oprim
	if message_tween and message_tween.is_valid():
		message_tween.kill()
	message_tween = create_tween()
	message_tween.tween_property(message_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	message_tween.tween_interval(0.9)
	message_tween.tween_property(message_label, "modulate:a", 0.0, 0.4)


func on_achievement(_id: String, title: String) -> void:
	AudioManager.play("level_complete", 1.2)
	achievement_label.text = "ACHIEVEMENT UNLOCKED: " + title
	var tween := create_tween()
	tween.tween_property(achievement_label, "modulate:a", 1.0, 0.25)
	tween.tween_interval(2.2)
	tween.tween_property(achievement_label, "modulate:a", 0.0, 0.5)
