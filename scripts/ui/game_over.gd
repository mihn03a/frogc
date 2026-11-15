extends Node3D
## =====================================================================
##  GAME_OVER.GD - ecranul de Game Over
## =====================================================================
##  Broasca tristă în prim-plan, în ploaie, cu o animație amuzantă:
##  cade încet pe o parte... stă puțin... apoi se ridică clătinându-se.
## =====================================================================

const UI = preload("res://scripts/ui/ui_style.gd")
const PlayerModel = preload("res://scripts/player/player_model.gd")

var frog
var clock := 0.0


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	create_dark_scene()
	create_sad_frog()
	create_screen_text()
	AudioManager.stop_music()
	AudioManager.play("defeat")


# =====================================================================
#  SCENA 3D
# =====================================================================
func create_dark_scene() -> void:
	var env := FX.make_environment(self, Color(0.03, 0.03, 0.06), Color(0.12, 0.1, 0.18), Color(0.6, 0.65, 0.8), 0.4)
	env.ambient_light_energy = 0.35
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.6, 7.5)
	add_child(camera)
	camera.look_at(Vector3(0, 0.6, 0), Vector3.UP)
	camera.current = true
	# reflector deasupra broaștei
	var spotlight := SpotLight3D.new()
	spotlight.position = Vector3(0, 8, 2)
	spotlight.light_energy = 6.0
	spotlight.spot_range = 15.0
	spotlight.spot_angle = 25.0
	spotlight.shadow_enabled = true
	add_child(spotlight)
	spotlight.look_at(Vector3.ZERO, Vector3.UP)
	FX.add_mesh(self, FX.cyl_mesh(3.0, 3.0, 0.3, 32), FX.mat(Color(0.15, 0.15, 0.2)), Vector3(0, -1.5, 0))
	var rain := FX.make_emitter(Color(0.5, 0.6, 1.0), 120, 1.2, Vector3.DOWN, 3.0, 8.0, 10.0, Vector3(0, -10, 0), 0.08, Vector3(5, 0.2, 4))
	rain.position = Vector3(0, 8, 0)
	add_child(rain)
	rain.emitting = true


func create_sad_frog() -> void:
	frog = PlayerModel.new()
	add_child(frog)
	frog.build(GameState.stage())
	frog.rotation.y = PI * 0.85
	frog.pose = "sad"
	frog.set_expression("sad")
	var smoke := FX.make_emitter(Color(0.4, 0.4, 0.4), 30, 1.5, Vector3.UP, 15.0, 1.0, 2.0, Vector3(0, 0.5, 0), 0.4)
	smoke.position = Vector3(0, 0.8, 0)
	frog.add_child(smoke)
	smoke.emitting = true


# =====================================================================
#  TEXTE ȘI BUTOANE
# =====================================================================
func create_screen_text() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(screen)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.25)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(shade)
	var title := UI.label("GAME OVER", 120, Color(1.0, 0.35, 0.3), 24)
	place_at_top(title, 600, 30, 170)
	screen.add_child(title)
	var info := UI.label(score_text(), 32)
	place_at_top(info, 700, 170, 220)
	screen.add_child(info)
	screen.add_child(create_buttons())


func score_text() -> String:
	var rank := GameState.record_run()   # salvăm partida în High Scores
	var extra := ""
	if rank == 1:
		extra = "     NEW HIGH SCORE!"
	elif rank > 1:
		extra = "     TOP 5 (#%d)" % rank
	var level_name: String = GameState.LEVEL_NAMES[GameState.current_level - 1]
	return "SCORE: %d     REACHED: %s%s" % [GameState.score, level_name, extra]


func place_at_top(control: Control, half_width: float, top: float, bottom: float) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	control.offset_left = -half_width
	control.offset_right = half_width
	control.offset_top = top
	control.offset_bottom = bottom


func create_buttons() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_left = -400
	row.offset_right = 400
	row.offset_top = -130
	row.offset_bottom = -50
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	row.add_child(UI.make_primary(UI.button("PLAY AGAIN", play_again)))
	row.add_child(UI.button("MAIN MENU", GameState.go_main_menu))
	return row


func play_again() -> void:
	# Resetare completă: nivelul 1, scor, viață, upgrade-uri, combo, boss, power-up-uri.
	GameState.new_run()
	GameState.start_level(1)


# =====================================================================
#  ANIMAȚIA (o buclă de 5 secunde)
# =====================================================================
func _process(delta: float) -> void:
	clock += delta
	var tilt := tilt_at(fmod(clock, 5.0))
	frog.position = Vector3(0, -0.3 - tilt * 0.25, 0)
	frog.root.rotation.z = tilt


func tilt_at(time: float) -> float:
	# 0 - 1,5 s: cade încet pe o parte
	if time < 1.5:
		return ease(time / 1.5, 2.5) * 1.35
	# 1,5 - 3 s: stă culcată
	if time < 3.0:
		return 1.35
	# 3 - 4,2 s: se ridică clătinându-se
	if time < 4.2:
		var progress := (time - 3.0) / 1.2
		return 1.35 * (1.0 - progress) + sin(progress * PI * 4.0) * 0.25 * (1.0 - progress)
	# restul: în picioare
	return 0.0
