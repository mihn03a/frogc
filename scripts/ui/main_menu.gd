extends Node3D
## =====================================================================
##  MAIN_MENU.GD - meniul principal
## =====================================================================
##  Fundal 3D animat (insule, nori, broasca care zboară în cerc) +
##  butoanele: Play, Level Select, Frog Skins, Achievements, High Scores,
##  Battle, How To Play, Settings, Credits, Quit.
##
##  Fiecare buton (în afară de Play/Battle/Quit) deschide o "pagină".
##  Conținutul paginii e reconstruit de fiecare dată când o deschizi,
##  ca să arate mereu informațiile actuale.
##
##  Secret: dă click pe broasca care zboară.
## =====================================================================

const UI = preload("res://scripts/ui/ui_style.gd")
const PlayerModel = preload("res://scripts/player/player_model.gd")
const PLAY_INTRO := false    # true = cântă intro.mp3 la prima pornire
const PAGE_TITLES := {"levels": "LEVEL SELECT", "skins": "FROG SKINS", "achievements": "ACHIEVEMENTS",
	"scores": "HIGH SCORES", "howto": "HOW TO PLAY", "settings": "SETTINGS", "credits": "CREDITS"}
const FROG_WORDS := ["RIBBIT!", "CROAK!", "HEY!", "BOING!", "STOP IT!", "RIBBIT?!"]
const HOW_TO_PLAY := [
	["CONTROLS", "A/D steer  -  W glide (fall slowly)  -  S dive  -  SPACE bounce  -  SHIFT turbo hop (stage 4)  -  ESC pause (PHOTO MODE inside)"],
	["BOUNCE", "Everything bounces you back: platforms, trees, walls, enemies. Bounces build COMBO and MOMENTUM (speed)."],
	["PERFECT BOUNCE", "Watch the ring at the bottom. Press SPACE when it turns green (NOW!). Bonus points, short invincibility, bigger jump."],
	["ENEMIES", "Land on them from above, or hit them during a Perfect Bounce / Super Bounce. Perfect-bounce their shots to send them BACK."],
	["FALLING", "Water, lava and the energy grid hurt a lot and send you back to the last platform (you lose speed and combo). The timing ring turns RED above them: press SPACE at NOW! for a PERFECT SPLASH (half damage, keep your combo, bounce straight back up)."],
	["HEALTH", "HP carries over between levels (only +35% heal). Bounce within 2.5 s after a hit for a COMEBACK BOUNCE bonus."],
	["POWER-UPS", "SHIELD blocks damage  -  SUPER BOUNCE jumps higher  -  SPEED BOOST  -  MAGNET pulls coins."],
	["EVOLUTION", "After each level your frog evolves: more HP, armor, new abilities. Spend evolution points on upgrades."],
	["BOSS", "Use the pink pads to fly high and stomp The Big Nic, or bounce his orbs back at him."],
]
const CREDITS := [
	["FROGC", "A game jam entry for the theme BOUNCE BACK"],
	["GAME DESIGN & DEVELOPMENT", "The FROGC team"],
	["ENGINE", "Godot 4.7 + GDScript"],
	["3D MODELS, EFFECTS, SFX & MUSIC", "Generated in code (no external assets)"],
	["INTRO & VICTORY TRACKS", "Added by the team (assets/audio)"],
	["SPECIAL THANKS", "Everyone who never gives up. Always bounce back!"],
]

var frog
var camera: Camera3D
var clock := 0.0
var title: Label
var pages := {}             # numele paginii -> panoul ei
var page_contents := {}     # numele paginii -> coloana în care punem conținutul
var hop := 0.0              # săritura broaștei când dai click (1 -> 0)
var spin := 0.0             # rotirea broaștei când dai click
var toast: Label            # mesajul mic de sus
var footer: Label           # cel mai bun scor etc.
var reset_confirm := false  # RESET PROGRESS trebuie apăsat de 2 ori


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	if Net.active:
		Net.leave()   # ne-am întors din Battle
	create_background()
	create_interface()
	GameState.apply_settings()
	start_music()


func start_music() -> void:
	if PLAY_INTRO and not AudioManager.intro_played:
		AudioManager.intro_played = true
		if AudioManager.play_custom("intro", "menu"):
			return
	AudioManager.play_music("menu")


# =====================================================================
#  FUNDALUL 3D
# =====================================================================
func create_background() -> void:
	FX.make_environment(self, Color(0.22, 0.5, 0.95), Color(0.8, 0.92, 1.0), Color(1.0, 0.96, 0.85))
	camera = Camera3D.new()
	camera.position = Vector3(0, 3, 14)
	add_child(camera)
	camera.look_at(Vector3(4, 1.5, 0), Vector3.UP)
	camera.current = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 42   # seed fix = mereu același fundal
	for i in 9:
		create_island(rng)
	for i in 14:
		create_cloud(rng)
	create_flying_frog()


func create_island(rng: RandomNumberGenerator) -> void:
	var pos := Vector3(rng.randf_range(-30, 30), rng.randf_range(-8, -2), rng.randf_range(-40, -5))
	var radius := rng.randf_range(2.5, 6.0)
	FX.add_mesh(self, FX.cyl_mesh(radius, radius, 1.2, 10), FX.mat(Color(0.38, 0.82, 0.3)), pos)
	FX.add_mesh(self, FX.cyl_mesh(radius * 0.95, 0.3, radius * 1.5, 10), FX.mat(Color(0.55, 0.36, 0.2)), pos + Vector3(0, -radius * 0.8, 0))
	FX.add_mesh(self, FX.sphere_mesh(1.3, 8), FX.mat(Color(0.2, 0.65, 0.25)), pos + Vector3(radius * 0.4, 2.4, 0))


func create_cloud(rng: RandomNumberGenerator) -> void:
	var pos := Vector3(rng.randf_range(-45, 45), rng.randf_range(4, 18), rng.randf_range(-60, -15))
	for k in 4:
		var radius := rng.randf_range(1.5, 3.0)
		var offset := Vector3(k * 2.0, rng.randf_range(-0.5, 0.8), 0)
		FX.add_mesh(self, FX.sphere_mesh(radius, 8), FX.mat(Color(1, 1, 1), 0.2, 0.0, 1.0), pos + offset)


func create_flying_frog() -> void:
	frog = PlayerModel.new()
	add_child(frog)
	frog.build(best_stage())
	frog.pose = "fly"
	FX.make_clickable(frog, 2.2, on_frog_clicked)
	var trail := FX.make_emitter(Color(1, 1, 0.7), 40, 0.6, Vector3(0, 0, 1), 10.0, 0.5, 1.0, Vector3.ZERO, 0.25)
	trail.position = Vector3(0, 0, 1.3)
	frog.add_child(trail)
	trail.emitting = true


func best_stage() -> int:
	# Broasca din meniu arată cea mai mare evoluție la care ai ajuns.
	return mini(int(GameState.save["best_level"]), 5)


# =====================================================================
#  INTERFAȚA
# =====================================================================
func create_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE   # click-urile ajung și la broasca 3D
	layer.add_child(screen)
	create_main_page(screen)
	for key in PAGE_TITLES:
		create_sub_page(screen, key)
	toast = UI.label("", 30, Color(1.0, 0.85, 0.3), 10)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast.offset_left = -500
	toast.offset_right = 500
	toast.offset_top = 20
	toast.offset_bottom = 70
	toast.modulate.a = 0.0
	screen.add_child(toast)
	GameState.achievement_unlocked.connect(on_achievement)
	show_page("main")


# ---------------------------------------------------------------- stilul meniului (simplu, aerisit)
const NAVY := Color(0.07, 0.1, 0.2)
const SOFT_WHITE := Color(0.96, 0.95, 0.9)
const MUTED := Color(0.96, 0.95, 0.9, 0.62)


func create_main_page(screen: Control) -> void:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(page)
	pages["main"] = page
	# panou lateral semi-transparent, ca textul să se citească peste cer
	var sidebar := ColorRect.new()
	sidebar.color = Color(NAVY, 0.62)
	sidebar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	sidebar.offset_right = 520
	sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(sidebar)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	column.offset_left = 72
	column.offset_right = 470
	column.offset_top = 52
	column.offset_bottom = -36
	column.add_theme_constant_override("separation", 4)
	page.add_child(column)
	title = plain_label("FROGC", 84, UI.YELLOW)
	title.pivot_offset = Vector2(0, 60)
	column.add_child(title)
	column.add_child(plain_label("B O U N C E   B A C K", 20, Color(0.6, 1.0, 0.5, 0.85)))
	add_gap(column, 28)
	column.add_child(pill_button("PLAY", play))
	add_gap(column, 18)
	add_menu_links(column)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	footer = plain_label("", 20, MUTED)
	column.add_child(footer)
	column.add_child(sound_link())
	var hint := plain_label("psst... click the flying frog", 18, Color(1, 1, 1, 0.55))
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -420
	hint.offset_right = -32
	hint.offset_top = -52
	hint.offset_bottom = -20
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	page.add_child(hint)


func add_menu_links(column: VBoxContainer) -> void:
	# Opțiunile, grupate: joc / colecție / ajutor / ieșire
	column.add_child(menu_link("Level Select", show_page.bind("levels")))
	column.add_child(menu_link("Battle  ·  multiplayer", open_battle_lobby))
	add_gap(column, 10)
	column.add_child(menu_link("Frog Skins", show_page.bind("skins")))
	column.add_child(menu_link("Achievements", show_page.bind("achievements")))
	column.add_child(menu_link("High Scores", show_page.bind("scores")))
	add_gap(column, 10)
	column.add_child(menu_link("How to Play", show_page.bind("howto")))
	column.add_child(menu_link("Settings", show_page.bind("settings")))
	column.add_child(menu_link("Credits", show_page.bind("credits")))
	add_gap(column, 10)
	column.add_child(menu_link("Quit", quit_game))


func add_gap(column: VBoxContainer, height: float) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	column.add_child(gap)


func plain_label(text: String, font_size: int, color: Color) -> Label:
	# Text fără contur gros (stilul nou, mai curat).
	var new_label := Label.new()
	new_label.text = text
	new_label.add_theme_font_size_override("font_size", font_size)
	new_label.add_theme_color_override("font_color", color)
	new_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.25))
	new_label.add_theme_constant_override("shadow_offset_y", 2)
	return new_label


func flat_box(background: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


## Un link de meniu: doar text; la hover devine alb, cu un fundal discret.
func menu_link(text: String, action: Callable) -> Button:
	var link := Button.new()
	link.text = text
	link.alignment = HORIZONTAL_ALIGNMENT_LEFT
	link.custom_minimum_size = Vector2(0, 40)
	link.add_theme_font_size_override("font_size", 24)
	link.add_theme_color_override("font_color", MUTED)
	link.add_theme_color_override("font_hover_color", SOFT_WHITE)
	link.add_theme_color_override("font_focus_color", SOFT_WHITE)
	link.add_theme_color_override("font_pressed_color", UI.YELLOW)
	link.add_theme_stylebox_override("normal", flat_box(Color(0, 0, 0, 0), 12))
	link.add_theme_stylebox_override("hover", flat_box(Color(1, 1, 1, 0.1), 12))
	link.add_theme_stylebox_override("pressed", flat_box(Color(1, 1, 1, 0.16), 12))
	link.add_theme_stylebox_override("focus", flat_box(Color(1, 1, 1, 0.06), 12))
	link.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	link.pressed.connect(UI.play_click)
	link.pressed.connect(action)
	return link


## Butonul principal: o "pastilă" galbenă.
func pill_button(text: String, action: Callable) -> Button:
	var pill := Button.new()
	pill.text = text
	pill.custom_minimum_size = Vector2(0, 58)
	pill.add_theme_font_size_override("font_size", 30)
	pill.add_theme_color_override("font_color", NAVY)
	pill.add_theme_color_override("font_hover_color", NAVY)
	pill.add_theme_color_override("font_focus_color", NAVY)
	pill.add_theme_color_override("font_pressed_color", NAVY)
	pill.add_theme_stylebox_override("normal", flat_box(UI.YELLOW, 32))
	pill.add_theme_stylebox_override("hover", flat_box(UI.YELLOW.lightened(0.25), 32))
	pill.add_theme_stylebox_override("pressed", flat_box(UI.YELLOW.darkened(0.15), 32))
	pill.add_theme_stylebox_override("focus", flat_box(UI.YELLOW.lightened(0.15), 32))
	pill.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	pill.pressed.connect(UI.play_click)
	pill.pressed.connect(action)
	return pill


## Buton discret pentru sub-pagini: dreptunghi rotunjit, aproape transparent.
func soft_button(text: String, action: Callable, font_size: int) -> Button:
	var soft := Button.new()
	soft.text = text
	soft.custom_minimum_size = Vector2(160, 48)
	soft.add_theme_font_size_override("font_size", font_size)
	soft.add_theme_color_override("font_color", SOFT_WHITE)
	soft.add_theme_color_override("font_hover_color", SOFT_WHITE)
	soft.add_theme_color_override("font_focus_color", SOFT_WHITE)
	soft.add_theme_color_override("font_disabled_color", Color(SOFT_WHITE, 0.35))
	soft.add_theme_stylebox_override("normal", flat_box(Color(1, 1, 1, 0.08), 14))
	soft.add_theme_stylebox_override("hover", flat_box(Color(1, 1, 1, 0.16), 14))
	soft.add_theme_stylebox_override("pressed", flat_box(Color(1, 1, 1, 0.22), 14))
	soft.add_theme_stylebox_override("focus", flat_box(Color(1, 1, 1, 0.12), 14))
	soft.add_theme_stylebox_override("disabled", flat_box(Color(1, 1, 1, 0.03), 14))
	soft.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	soft.pressed.connect(UI.play_click)
	soft.pressed.connect(action)
	return soft


func sound_link() -> Button:
	# "Sound: on / off", tot ca link simplu; se actualizează și când apeși M.
	var link := menu_link("", GameState.toggle_mute)
	link.add_theme_font_size_override("font_size", 20)
	update_sound_link(link, bool(GameState.settings["muted"]))
	GameState.mute_changed.connect(on_mute_changed.bind(link))
	return link


func on_mute_changed(muted: bool, link: Button) -> void:
	update_sound_link(link, muted)


func update_sound_link(link: Button, muted: bool) -> void:
	if not is_instance_valid(link):
		return
	if muted:
		link.text = "Sound: off   (M)"
	else:
		link.text = "Sound: on   (M)"


func create_sub_page(screen: Control, key: String) -> void:
	# Fundal întunecat + panou centrat, aerisit: titlu, conținut, BACK.
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(page)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(NAVY, 0.45)
	page.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(center)
	var panel := PanelContainer.new()
	var panel_style := flat_box(Color(NAVY, 0.92), 28)
	panel_style.content_margin_left = 48
	panel_style.content_margin_right = 48
	panel_style.content_margin_top = 36
	panel_style.content_margin_bottom = 36
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size = Vector2(820, 0)
	panel.add_child(column)
	column.add_child(plain_label(PAGE_TITLES[key], 44, UI.YELLOW))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	column.add_child(content)
	add_gap(column, 8)
	var back := menu_link("‹  Back", show_page.bind("main"))
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(back)
	pages[key] = page
	page_contents[key] = content


# =====================================================================
#  PAGINILE
# =====================================================================
func show_page(page: String) -> void:
	for key in pages:
		pages[key].visible = (key == page)
	reset_confirm = false
	if page == "main":
		update_footer()
	elif page == "levels":
		fill_levels_page()
	elif page == "skins":
		fill_skins_page()
	elif page == "achievements":
		fill_achievements_page()
	elif page == "scores":
		fill_scores_page()
	elif page == "howto":
		fill_how_to_play_page()
	elif page == "settings":
		fill_settings_page()
	elif page == "credits":
		fill_credits_page()


func clear_page(page: String) -> VBoxContainer:
	var content: VBoxContainer = page_contents[page]
	for child in content.get_children():
		child.queue_free()
	return content


func text_line(text: String, font_size: int = 24, color: Color = Color.WHITE) -> Label:
	var line := UI.label(text, font_size, color, 6)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(800, 0)
	return line


func update_footer() -> void:
	var unlocked: Array = GameState.save["achievements"]
	footer.text = "Best score  %d   ·   %d/%d achievements" % [GameState.best_score(), unlocked.size(), GameState.ACHIEVEMENTS.size()]


func make_grid(columns: int, spacing: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", spacing)
	grid.add_theme_constant_override("v_separation", 10)
	return grid


# ---------------------------------------------------------------- LEVEL SELECT
func fill_levels_page() -> void:
	var content := clear_page("levels")
	content.add_child(text_line("Start from any level you have reached. Your frog starts at that level's evolution.", 22, Color(0.85, 0.95, 0.85)))
	var best_level: int = int(GameState.save["best_level"])
	var grid := make_grid(2, 12)
	content.add_child(grid)
	for i in 5:
		var number := i + 1
		var unlocked := number <= best_level
		var text := "%d. LOCKED" % number
		if unlocked:
			text = "%d. %s" % [number, GameState.LEVEL_NAMES[i]]
		var level_button := soft_button(text, start_at_level.bind(number), 24)
		level_button.custom_minimum_size = Vector2(400, 56)
		level_button.disabled = not unlocked
		grid.add_child(level_button)


func start_at_level(number: int) -> void:
	GameState.new_run()
	GameState.start_level(number)


# ---------------------------------------------------------------- SKINS
func fill_skins_page() -> void:
	var content := clear_page("skins")
	content.add_child(text_line("Pick your frog's look. Unlock more skins by playing. The flying frog shows a preview.", 22, Color(0.85, 0.95, 0.85)))
	var grid := make_grid(3, 10)
	content.add_child(grid)
	for skin in GameState.SKINS:
		grid.add_child(create_skin_button(skin))


func create_skin_button(skin: Dictionary) -> Button:
	var id: String = skin["id"]
	var unlocked := GameState.skin_unlocked(id)
	var equipped: bool = GameState.save["skin"] == id
	var text: String = str(skin["name"])
	if equipped:
		text += "\n[EQUIPPED]"
	elif unlocked:
		text += "\n[SELECT]"
	else:
		text += "\n" + str(skin["req"])   # cum se deblochează
	var skin_button := soft_button(text, pick_skin.bind(id), 18)
	skin_button.custom_minimum_size = Vector2(265, 76)
	skin_button.disabled = not unlocked
	if unlocked:
		# butonul are culoarea skin-ului; cel echipat are un chenar galben
		var skin_color: Color = skin["color"]
		var style := flat_box(skin_color, 14)
		if equipped:
			style.set_border_width_all(4)
			style.border_color = UI.YELLOW
		skin_button.add_theme_stylebox_override("normal", style)
		skin_button.add_theme_stylebox_override("hover", flat_box(skin_color.lightened(0.2), 14))
		skin_button.add_theme_color_override("font_color", NAVY)
		skin_button.add_theme_color_override("font_hover_color", NAVY)
	return skin_button


func pick_skin(id: String) -> void:
	GameState.select_skin(id)
	frog.build(best_stage())
	var skin_color: Color = GameState.current_skin()["color"]
	FX.burst(frog.global_position, skin_color, 30, 8.0, 0.35, 0.0)
	AudioManager.play("pu_shield")
	fill_skins_page()


# ---------------------------------------------------------------- ACHIEVEMENTS
func fill_achievements_page() -> void:
	var content := clear_page("achievements")
	var unlocked: Array = GameState.save["achievements"]
	content.add_child(text_line("UNLOCKED: %d / %d" % [unlocked.size(), GameState.ACHIEVEMENTS.size()], 26, Color(0.5, 1.0, 1.0)))
	for achievement in GameState.ACHIEVEMENTS:
		var done := GameState.has_achievement(achievement["id"])
		var line := str(achievement["title"]) + "  -  " + str(achievement["desc"])
		if done:
			content.add_child(text_line("[X] " + line, 22, Color(1.0, 0.85, 0.3)))
		else:
			content.add_child(text_line("[  ] " + line, 22, Color(0.6, 0.6, 0.6)))


# ---------------------------------------------------------------- HIGH SCORES
func fill_scores_page() -> void:
	var content := clear_page("scores")
	var list: Array = GameState.save["high_scores"]
	if list.is_empty():
		content.add_child(text_line("No scores yet. Go bounce!", 28, Color(0.85, 0.95, 0.85)))
		return
	content.add_child(text_line("#   SCORE        RATING   LEVEL   MODE       DATE", 22, Color(0.5, 1.0, 1.0)))
	var place := 1
	for entry in list:
		var reached := "L%d " % int(entry["level"])
		if entry["won"]:
			reached = "WIN!"
		var line := "%d.  %-10d   %-6s   %s   %-8s   %s" % [place, int(entry["score"]), str(entry["rating"]), reached, str(entry["difficulty"]), str(entry["date"])]
		var color := Color.WHITE
		if place == 1:
			color = UI.YELLOW
		content.add_child(text_line(line, 24, color))
		place += 1


# ---------------------------------------------------------------- HOW TO PLAY
func fill_how_to_play_page() -> void:
	var content := clear_page("howto")
	for item in HOW_TO_PLAY:
		var rich_text := RichTextLabel.new()
		rich_text.bbcode_enabled = true   # permite [b] bold și [color] în text
		rich_text.fit_content = true
		rich_text.scroll_active = false
		rich_text.custom_minimum_size = Vector2(800, 0)
		rich_text.add_theme_font_size_override("normal_font_size", 18)
		rich_text.add_theme_font_size_override("bold_font_size", 19)
		rich_text.text = "[b][color=#ffdb33]%s:[/color][/b]  %s" % [item[0], item[1]]
		content.add_child(rich_text)


# ---------------------------------------------------------------- SETTINGS
func fill_settings_page() -> void:
	var content := clear_page("settings")
	content.add_child(create_difficulty_row())
	content.add_child(text_line("EASY: less damage, wider Perfect window.  HARD: more damage, tighter window, x1.5 score.", 18, Color(0.75, 0.85, 0.75)))
	for key in ["master", "music", "sfx"]:
		content.add_child(create_volume_row(key))
	add_checkbox(content, "muted", "MUTE ALL SOUND (M)")
	add_checkbox(content, "shake", "CAMERA SHAKE")
	add_checkbox(content, "fullscreen", "FULLSCREEN")
	add_checkbox(content, "show_fps", "SHOW FPS")
	add_checkbox(content, "low_graphics", "LOW GRAPHICS (faster on laptops)")
	var reset := soft_button("Reset progress", reset_progress, 22)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reset.add_theme_stylebox_override("normal", flat_box(Color(0.75, 0.2, 0.2, 0.8), 14))
	content.add_child(reset)


func create_difficulty_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(setting_name("DIFFICULTY"))
	for key in ["easy", "normal", "hard"]:
		var difficulty_button := soft_button(str(GameState.DIFFICULTIES[key]["name"]), set_difficulty.bind(key), 22)
		difficulty_button.custom_minimum_size = Vector2(160, 48)
		if GameState.settings["difficulty"] == key:   # cea aleasă e galbenă
			difficulty_button.add_theme_stylebox_override("normal", flat_box(UI.YELLOW, 14))
			difficulty_button.add_theme_color_override("font_color", NAVY)
		row.add_child(difficulty_button)
	return row


func create_volume_row(key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(setting_name(key.to_upper() + " VOLUME"))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(GameState.settings[key])
	slider.custom_minimum_size = Vector2(420, 40)
	slider.value_changed.connect(on_volume_changed.bind(key))
	row.add_child(slider)
	return row


func add_checkbox(content: VBoxContainer, key: String, text: String) -> void:
	var checkbox := CheckButton.new()
	checkbox.text = text
	checkbox.add_theme_font_size_override("font_size", 24)
	checkbox.button_pressed = bool(GameState.settings[key])
	checkbox.toggled.connect(on_checkbox_toggled.bind(key))
	content.add_child(checkbox)


func setting_name(text: String) -> Label:
	var new_label := UI.label(text, 24)
	new_label.custom_minimum_size = Vector2(280, 44)
	new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return new_label


func set_difficulty(key: String) -> void:
	GameState.settings["difficulty"] = key
	GameState.apply_settings()
	fill_settings_page()


func on_volume_changed(value: float, key: String) -> void:
	GameState.settings[key] = value
	GameState.apply_settings()


func on_checkbox_toggled(on: bool, key: String) -> void:
	GameState.settings[key] = on
	GameState.apply_settings()
	if key == "muted":
		GameState.mute_changed.emit(on)   # actualizează și butonul SOUND


func reset_progress() -> void:
	if not reset_confirm:
		reset_confirm = true
		show_toast("Press RESET PROGRESS again to confirm", Color(1.0, 0.5, 0.4))
		return
	reset_confirm = false
	GameState.reset_progress()
	frog.build(1)
	show_toast("Progress reset", Color(1.0, 0.5, 0.4))


# ---------------------------------------------------------------- CREDITS
func fill_credits_page() -> void:
	var content := clear_page("credits")
	for item in CREDITS:
		content.add_child(text_line(str(item[0]), 24, UI.YELLOW))
		content.add_child(text_line(str(item[1]), 22, Color(0.92, 0.97, 0.92)))


# =====================================================================
#  ACȚIUNI
# =====================================================================
func play() -> void:
	GameState.new_run()
	GameState.start_level(1)


func open_battle_lobby() -> void:
	GameState.change_scene(GameState.LOBBY_SCENE)


func quit_game() -> void:
	get_tree().quit()


func on_achievement(_id: String, achievement_title: String) -> void:
	AudioManager.play("level_complete", 1.2)
	show_toast("ACHIEVEMENT UNLOCKED: " + achievement_title, Color(1.0, 0.85, 0.3))
	update_footer()


func show_toast(text: String, color: Color) -> void:
	toast.text = text
	toast.add_theme_color_override("font_color", color)
	var tween := create_tween()
	tween.tween_property(toast, "modulate:a", 1.0, 0.2)
	tween.tween_interval(2.0)
	tween.tween_property(toast, "modulate:a", 0.0, 0.5)


## Click pe broasca care zboară: sare, se învârte și orăcăie.
func on_frog_clicked() -> void:
	if not pages["main"].visible:
		return
	var pokes := GameState.add_poke()
	hop = 1.0
	spin = TAU
	frog.squash()
	AudioManager.play("bounce", 0.8 + randf() * 0.6)
	FX.burst(frog.global_position, Color(0.6, 1.0, 0.4), 20, 8.0, 0.3)
	FX.popup(frog.global_position + Vector3.UP * 1.5, FROG_WORDS[pokes % FROG_WORDS.size()], Color(1.0, 1.0, 0.5), 70)


# =====================================================================
#  ANIMAȚIA (broasca zboară în cerc, titlul "pulsează")
# =====================================================================
func _process(delta: float) -> void:
	clock += delta
	hop = move_toward(hop, 0.0, delta * 1.6)
	spin = move_toward(spin, 0.0, delta * 9.0)
	var angle := clock * 0.6
	var height := 1.5 + sin(clock * 1.7) * 1.0 + sin(hop * PI) * 2.5
	frog.position = Vector3(5.0 + cos(angle) * 4.0, height, sin(angle) * 4.0)
	var direction := Vector3(-sin(angle), 0, cos(angle))   # direcția de zbor pe cerc
	frog.rotation.y = atan2(-direction.x, -direction.z) + spin
	frog.bank = 0.8
	title.scale = Vector2.ONE * (1.0 + sin(clock * 2.0) * 0.015)
