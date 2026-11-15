extends Node3D
## =====================================================================
##  VICTORY.GD - scena finală de victorie
## =====================================================================
##  Broasca câștigătoare în prim-plan face emote-ul de victorie, boss-ul
##  plânge comic în fundal, camera se apropie încet, apare sloganul
##  "BOUNCE BACK. NEVER GIVE UP!" și apoi statisticile finale.
##
##  Secret (easter egg): dacă dai click pe broască, se schimbă în costum
##  cu cătușe și apar blițuri de aparate foto.
## =====================================================================

const UI = preload("res://scripts/ui/ui_style.gd")
const PlayerModel = preload("res://scripts/player/player_model.gd")
const BossModel = preload("res://scripts/boss/boss_model.gd")

var env: Environment
var camera: Camera3D
var hero               # broasca noastră
var boss
var slogan: Label
var stats_panel: Control
var secret_found := false


func _ready() -> void:
	GameState.player_dead = false
	create_scene()
	create_interface()
	AudioManager.stop_music()
	# melodia ta (assets/audio/victory.*) dacă există, altfel fanfara generată
	if not AudioManager.play_custom("victory", "menu"):
		AudioManager.play("victory")
	play_cinematic()


# =====================================================================
#  SCENA 3D
# =====================================================================
func create_scene() -> void:
	env = FX.make_environment(self, Color(0.04, 0.02, 0.12), Color(0.4, 0.1, 0.55), Color(0.7, 0.8, 1.0), 0.8)
	env.glow_intensity = 1.4
	env.background_energy_multiplier = 1.0
	camera = Camera3D.new()
	camera.position = Vector3(0, 3.0, 17)
	camera.fov = 60
	add_child(camera)
	camera.look_at(Vector3(0, 1.3, 0), Vector3.UP)
	camera.current = true
	create_arena_floor()
	create_hero()
	create_crying_boss()
	create_lights()
	create_particles()


func create_arena_floor() -> void:
	FX.add_mesh(self, FX.cyl_mesh(22, 22, 1, 48), FX.mat(Color(0.07, 0.07, 0.13), 0.0, 0.9, 0.3), Vector3(0, -2.0, 0))
	for radius in [5.0, 10.0, 16.0]:
		FX.add_mesh(self, FX.torus_mesh(radius - 0.12, radius + 0.12, 48), FX.mat(Color(0.2, 1.0, 1.0), 3.5), Vector3(0, -1.48, 0))


func create_hero() -> void:
	# în față, cu fața spre cameră (+Z)
	hero = PlayerModel.new()
	add_child(hero)
	hero.build(5)
	hero.position = Vector3(0, 0.4, 3)
	hero.rotation.y = PI
	hero.pose = "victory"
	hero.set_expression("serious")
	FX.make_clickable(hero, 2.6, on_hero_clicked, Vector3(0, 1.0, 0))


func create_crying_boss() -> void:
	boss = BossModel.new()
	add_child(boss)
	boss.position = Vector3(0, 3.6, -9)
	boss.rotation.y = PI
	boss.set_mood("cry")


func create_lights() -> void:
	var spotlight := SpotLight3D.new()
	spotlight.position = Vector3(0, 10, 7)
	spotlight.light_energy = 9.0
	spotlight.spot_range = 25.0
	spotlight.spot_angle = 22.0
	spotlight.shadow_enabled = true
	add_child(spotlight)
	spotlight.look_at(Vector3(0, 0, 3), Vector3.UP)
	var rim_light := OmniLight3D.new()   # lumină turcoaz din spatele broaștei
	rim_light.position = Vector3(0, 3, 0)
	rim_light.light_color = Color(0.3, 1.0, 1.0)
	rim_light.light_energy = 3.0
	rim_light.omni_range = 6.0
	add_child(rim_light)


func create_particles() -> void:
	add_emitter(FX.make_emitter(Color(1.0, 0.85, 0.3), 120, 4.0, Vector3.DOWN, 30.0, 1.0, 3.0, Vector3(0, -3, 0), 0.22, Vector3(12, 0.5, 8)), Vector3(0, 12, 0))
	add_emitter(FX.make_emitter(Color(0.4, 1.0, 0.5), 80, 4.0, Vector3.DOWN, 30.0, 1.0, 3.0, Vector3(0, -3, 0), 0.22, Vector3(12, 0.5, 8)), Vector3(0, 12, 0))
	add_emitter(FX.make_emitter(Color(0.3, 1.0, 1.0), 60, 1.5, Vector3.UP, 20.0, 1.0, 3.0, Vector3.ZERO, 0.15, Vector3(1.5, 0.2, 1.5)), Vector3(0, -1.2, 3))


func add_emitter(emitter: GPUParticles3D, pos: Vector3) -> void:
	emitter.position = pos
	add_child(emitter)
	emitter.emitting = true


# =====================================================================
#  INTERFAȚA (slogan + statistici)
# =====================================================================
func create_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE   # click-urile ajung la broasca 3D
	layer.add_child(screen)
	slogan = UI.label("BOUNCE BACK. NEVER GIVE UP!", 84, UI.YELLOW, 22)
	slogan.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	slogan.offset_left = -900
	slogan.offset_right = 900
	slogan.offset_top = 40
	slogan.offset_bottom = 160
	slogan.pivot_offset = Vector2(900, 60)   # se mărește din centru
	slogan.modulate.a = 0.0
	screen.add_child(slogan)
	stats_panel = UI.panel()
	stats_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	stats_panel.offset_left = -560
	stats_panel.offset_right = -30
	stats_panel.offset_top = -230
	stats_panel.offset_bottom = 330
	stats_panel.modulate.a = 0.0
	stats_panel.visible = false
	screen.add_child(stats_panel)
	fill_stats_panel()


func fill_stats_panel() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	stats_panel.add_child(column)
	var rank := GameState.record_run()
	column.add_child(UI.label("FINAL SCORE: %d" % GameState.score, 44, UI.YELLOW, 14))
	if rank == 1:
		column.add_child(UI.label("NEW HIGH SCORE!", 32, Color(1.0, 0.5, 0.9), 10))
	elif rank > 1:
		column.add_child(UI.label("TOP 5 SCORE  (#%d)" % rank, 26, Color(1.0, 0.7, 0.9), 8))
	column.add_child(UI.label("RATING: " + GameState.rating(), 28, Color(0.5, 1.0, 1.0)))
	column.add_child(UI.label("LEVELS COMPLETED: %d / 5" % GameState.levels_completed, 26))
	column.add_child(UI.label("PERFECT BOUNCES: %d" % GameState.perfect_count, 26))
	column.add_child(UI.label("HIGHEST COMBO: %d" % GameState.highest_combo, 26))
	column.add_child(UI.label("ENEMIES SPLATTED: %d" % GameState.enemies_defeated, 26))
	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	buttons.add_child(UI.button("MAIN MENU", GameState.go_main_menu))
	buttons.add_child(UI.make_primary(UI.button("PLAY AGAIN", play_again)))


func play_again() -> void:
	GameState.new_run()
	GameState.start_level(1)


# =====================================================================
#  CINEMATICUL
# =====================================================================
func play_cinematic() -> void:
	# 1) camera se apropie încet, fundalul se întunecă puțin
	var push_in := create_tween().set_parallel(true)
	push_in.tween_property(camera, "position", Vector3(0, 2.0, 11.5), 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	push_in.tween_property(env, "background_energy_multiplier", 0.45, 4.0)
	push_in.tween_property(env, "ambient_light_energy", 0.4, 4.0)
	await get_tree().create_timer(1.5).timeout
	# 2) sloganul apare cu un efect elastic
	FX.flash(Color(1, 1, 0.7), 0.4)
	slogan.scale = Vector2(0.3, 0.3)
	var slogan_in := create_tween().set_parallel(true)
	slogan_in.tween_property(slogan, "modulate:a", 1.0, 0.4)
	slogan_in.tween_property(slogan, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# 3) artificii
	for i in 5:
		var spot := Vector3(randf_range(-6, 6), randf_range(3, 7), randf_range(-4, 2))
		FX.burst(spot, Color(randf(), 1.0, randf()), 32, 10.0, 0.35, -3.0)
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(2.0).timeout
	# 4) statisticile
	stats_panel.visible = true
	var stats_in := create_tween()
	stats_in.tween_property(stats_panel, "modulate:a", 1.0, 0.6)
	AudioManager.play_music("menu")   # așteaptă singură dacă melodia de victorie încă merge


func _process(_delta: float) -> void:
	if camera:
		camera.look_at(Vector3(0, 2.1, 1.0), Vector3.UP)


# =====================================================================
#  EASTER EGG
# =====================================================================
func on_hero_clicked() -> void:
	if secret_found:
		return
	secret_found = true
	put_on_suit()


func put_on_suit() -> void:
	GameState.unlock("dress_code")
	FX.flash(Color(1, 1, 1), 0.9)
	AudioManager.play("evolve", 1.4)
	hero.outfit = "suit"
	hero.build(5)   # reconstruim modelul, acum cu costum
	hero.pose = "victory"
	hero.set_expression("serious")
	FX.burst(hero.global_position, Color(1, 1, 1), 32, 10.0, 0.4, 0.0)
	camera_flashes()


func camera_flashes() -> void:
	# 14 blițuri de aparate foto, la intervale aleatorii
	for i in 14:
		var spot: Vector3 = hero.global_position + Vector3(randf_range(-6, 6), randf_range(0, 4), randf_range(1, 5))
		FX.burst(spot, Color(1, 1, 1), 12, 3.0, 0.5, 0.0)
		FX.flash(Color(1, 1, 1), randf_range(0.15, 0.4))
		AudioManager.play("click", randf_range(0.5, 0.9))
		await get_tree().create_timer(randf_range(0.08, 0.25)).timeout
