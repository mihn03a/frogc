extends Node3D
## =====================================================================
##  EVOLUTION_SCREEN.GD - ecranul dintre niveluri
## =====================================================================
##  1) broasca veche se învârte și se transformă în evoluția nouă
##  2) apare panoul cu abilitatea nouă, viața și scorul
##  3) CONTINUE (sau Enter) pornește nivelul următor
## =====================================================================

const UI = preload("res://scripts/ui/ui_style.gd")
const PlayerModel = preload("res://scripts/player/player_model.gd")

var model
var new_stage := 2
var info_panel: Control
var stats_label: Label
var continue_button: Button
var leaving := false   # ca să nu pornim nivelul de 2 ori


func _ready() -> void:
	new_stage = GameState.stage()
	create_scene()
	create_interface()
	AudioManager.play_music("menu")
	play_transformation()


# =====================================================================
#  SCENA 3D: un piedestal cu broasca pe el
# =====================================================================
func create_scene() -> void:
	var env := FX.make_environment(self, Color(0.05, 0.06, 0.15), Color(0.2, 0.15, 0.4), Color(0.8, 0.85, 1.0), 0.6)
	env.glow_intensity = 1.3
	var camera := Camera3D.new()
	camera.position = Vector3(3.4, 2.0, 8.0)
	add_child(camera)
	camera.look_at(Vector3(3.4, 0.6, 0), Vector3.UP)
	camera.current = true
	var spotlight := SpotLight3D.new()
	spotlight.position = Vector3(0, 9, 2)
	spotlight.rotation_degrees = Vector3(-80, 0, 0)
	spotlight.light_energy = 6.0
	spotlight.spot_range = 20.0
	spotlight.spot_angle = 30.0
	spotlight.shadow_enabled = true
	add_child(spotlight)
	FX.add_mesh(self, FX.cyl_mesh(3.0, 3.2, 0.5, 32), FX.mat(Color(0.12, 0.12, 0.2), 0.0, 0.8, 0.3), Vector3(0, -1.6, 0))
	FX.add_mesh(self, FX.torus_mesh(3.0, 3.2, 48), FX.mat(Color(0.3, 1.0, 0.9), 4.0), Vector3(0, -1.3, 0))
	var sparkles := FX.make_emitter(Color(0.6, 1.0, 1.0), 50, 2.0, Vector3.UP, 30.0, 1.0, 2.5, Vector3.ZERO, 0.12, Vector3(3, 0.2, 3))
	sparkles.position = Vector3(0, -1.2, 0)
	add_child(sparkles)
	sparkles.emitting = true
	model = PlayerModel.new()
	add_child(model)
	model.build(new_stage - 1)   # la început arătăm evoluția VECHE
	model.pose = "showcase"
	model.rotation.y = PI * 0.85


# =====================================================================
#  INTERFAȚA
# =====================================================================
func create_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(screen)
	var title := UI.label("EVOLUTION!", 96, UI.YELLOW, 20)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -600
	title.offset_right = 600
	title.offset_top = 20
	title.offset_bottom = 140
	screen.add_child(title)
	info_panel = UI.panel()
	info_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	info_panel.offset_left = -740
	info_panel.offset_right = -40
	info_panel.offset_top = -200
	info_panel.offset_bottom = 160
	info_panel.modulate.a = 0.0   # invizibil până se termină transformarea
	screen.add_child(info_panel)
	fill_info_panel()
	refresh()


func fill_info_panel() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	info_panel.add_child(column)
	column.add_child(UI.label("STAGE %d: %s" % [new_stage, GameState.STAGE_NAMES[new_stage - 1]], 40, Color(0.5, 1.0, 1.0)))
	var ability := UI.label("NEW ABILITY\n" + str(GameState.STAGE_ABILITIES[new_stage - 1]), 24, Color(1.0, 0.9, 0.5), 8)
	ability.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ability.custom_minimum_size = Vector2(640, 0)
	column.add_child(ability)
	stats_label = UI.label("", 24, Color.WHITE, 8)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(stats_label)
	var next_level: String = GameState.LEVEL_NAMES[GameState.current_level - 1]
	continue_button = UI.make_primary(UI.button("CONTINUE: " + next_level, go_to_next_level, 28))
	column.add_child(continue_button)


## Afișează viața și scorul.
func refresh() -> void:
	stats_label.text = stats_text()


func stats_text() -> String:
	var old_max_hp: float = GameState.BASE_HP[new_stage - 2] + GameState.upg_health * 20.0
	var hp_next_level := minf(GameState.max_hp(), GameState.hp + GameState.max_hp() * GameState.LEVEL_HEAL)
	var lines := []
	lines.append("HEALTH NEXT LEVEL: %d / %d  (+35%% heal)" % [int(hp_next_level), int(GameState.max_hp())])
	lines.append("MAX HEALTH:   %d  ->  %d" % [int(old_max_hp), int(GameState.max_hp())])
	lines.append("TOTAL SCORE:  %d" % GameState.score)
	return "\n".join(lines)


func go_to_next_level() -> void:
	if leaving:
		return
	leaving = true
	GameState.start_level(GameState.current_level)


func _unhandled_input(event: InputEvent) -> void:
	# Enter = CONTINUE
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			go_to_next_level()


# =====================================================================
#  ANIMAȚIA DE TRANSFORMARE
# =====================================================================
func play_transformation() -> void:
	await get_tree().create_timer(0.8).timeout
	AudioManager.play("evolve")
	# 1) se învârte tot mai repede, cu scântei
	var spin_up := create_tween()
	spin_up.tween_property(model, "rotation:y", model.rotation.y + TAU * 4.0, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for i in 6:
		var color := Color(0.4, 1.0, 1.0).lerp(Color(1, 1, 0.4), i / 6.0)
		FX.burst(model.global_position, color, 20, 6.0 + i, 0.25, 0.0)
		await get_tree().create_timer(0.26).timeout
	# 2) flash alb + modelul nou apare
	FX.flash(Color(1, 1, 1), 0.9)
	FX.shake(0.5)
	model.build(new_stage)
	model.scale = Vector3.ONE * 0.3
	var grow := create_tween()
	grow.tween_property(model, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	FX.burst(model.global_position, Color(1.0, 1.0, 0.5), 32, 14.0, 0.4, 0.0)
	FX.burst(model.global_position, Color(0.4, 1.0, 1.0), 32, 10.0, 0.3, -4.0)
	AudioManager.play("perfect")
	# 3) apare panoul, iar broasca se rotește încet la nesfârșit
	var fade_in := create_tween()
	fade_in.tween_property(info_panel, "modulate:a", 1.0, 0.5)
	continue_button.grab_focus()
	var slow_spin := create_tween().set_loops()
	slow_spin.tween_property(model, "rotation:y", TAU, 8.0).as_relative()
