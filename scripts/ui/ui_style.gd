extends RefCounted
## =====================================================================
##  UI_STYLE.GD - stilul comun al meniurilor (butoane, texte, panouri)
## =====================================================================
##  Folosire:  const UI = preload("res://scripts/ui/ui_style.gd")
##             apoi  UI.button("PLAY", funcția_mea)
##  Toate funcțiile sunt "static": le apelezi direct, fără să creezi obiect.
## =====================================================================

const YELLOW := Color(1.0, 0.86, 0.2)
const GREEN := Color(0.36, 0.82, 0.28)
const DARK_GREEN := Color(0.08, 0.2, 0.08)
const OUTLINE := Color(0.04, 0.08, 0.04)
const NAVY := Color(0.07, 0.1, 0.2)
const SOFT_WHITE := Color(0.96, 0.95, 0.9)


## Un text centrat, cu contur închis (se citește pe orice fundal).
static func label(text: String, font_size: int = 32, color: Color = Color.WHITE, outline: int = 10) -> Label:
	var new_label := Label.new()
	new_label.text = text
	new_label.add_theme_font_size_override("font_size", font_size)
	new_label.add_theme_color_override("font_color", color)
	new_label.add_theme_color_override("font_outline_color", OUTLINE)
	new_label.add_theme_constant_override("outline_size", outline)
	new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return new_label


## Un dreptunghi cu colțuri rotunjite, chenar și umbră.
static func box(background: Color, border: Color, radius: int = 18, border_width: int = 5) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_size = 6
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


## Un buton în stilul nou, aerisit: dreptunghi rotunjit albastru-închis,
## semi-transparent, fără chenar gros. Când e apăsat: face "click" și apelează `callback`.
static func button(text: String, callback: Callable, font_size: int = 32) -> Button:
	var new_button := Button.new()
	new_button.text = text
	new_button.custom_minimum_size = Vector2(340, 60)
	new_button.add_theme_font_size_override("font_size", font_size)
	new_button.add_theme_color_override("font_color", SOFT_WHITE)
	new_button.add_theme_color_override("font_hover_color", Color.WHITE)
	new_button.add_theme_color_override("font_pressed_color", YELLOW)
	new_button.add_theme_color_override("font_focus_color", Color.WHITE)
	new_button.add_theme_color_override("font_disabled_color", Color(SOFT_WHITE, 0.35))
	new_button.add_theme_stylebox_override("normal", flat_box(Color(0.17, 0.22, 0.4, 0.9)))
	new_button.add_theme_stylebox_override("hover", flat_box(Color(0.25, 0.31, 0.52, 0.95)))
	new_button.add_theme_stylebox_override("pressed", flat_box(Color(0.1, 0.13, 0.25, 0.95)))
	new_button.add_theme_stylebox_override("focus", flat_box(Color(0.22, 0.28, 0.48, 0.92), YELLOW))
	new_button.add_theme_stylebox_override("disabled", flat_box(Color(NAVY, 0.4)))
	# Butonul reacționează când APEȘI mouse-ul (nu când îl ridici) - e mai sigur.
	new_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	new_button.pressed.connect(play_click)
	new_button.pressed.connect(callback)
	return new_button


## Face un buton să fie cel principal de pe ecran: galben, ca PLAY din meniu.
static func make_primary(main_button: Button) -> Button:
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		main_button.add_theme_color_override(state, NAVY)
	main_button.add_theme_stylebox_override("normal", flat_box(YELLOW))
	main_button.add_theme_stylebox_override("hover", flat_box(YELLOW.lightened(0.25)))
	main_button.add_theme_stylebox_override("pressed", flat_box(YELLOW.darkened(0.15)))
	main_button.add_theme_stylebox_override("focus", flat_box(YELLOW.lightened(0.15), Color.WHITE))
	return main_button


## Fundalul unui buton: colțuri rotunjite; opțional o linie subțire de contur (focus).
static func flat_box(background: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.set_corner_radius_all(16)
	if border.a > 0.0:
		style.border_color = border
		style.set_border_width_all(2)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


static func play_click() -> void:
	# Funcțiile statice nu văd direct autoload-urile, așa că îl căutăm în arbore.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var audio := tree.root.get_node_or_null("AudioManager")
	if audio:
		audio.play("click")


## Butonul "SOUND: ON / OFF". Își schimbă singur textul (și când apeși M).
static func sound_button(game_state: Node) -> Button:
	var new_button := button("", game_state.toggle_mute, 22)
	new_button.custom_minimum_size = Vector2(230, 48)
	var update_text := func(muted: bool) -> void:
		if not is_instance_valid(new_button):
			return
		if muted:
			new_button.text = "SOUND: OFF  [M]"
		else:
			new_button.text = "SOUND: ON  [M]"
	update_text.call(bool(game_state.settings["muted"]))
	game_state.mute_changed.connect(update_text)
	# când butonul dispare (schimbăm scena), nu mai ascultăm semnalul
	new_button.tree_exiting.connect(func() -> void:
		if game_state.mute_changed.is_connected(update_text):
			game_state.mute_changed.disconnect(update_text))
	return new_button


## Panoul din meniuri: albastru-închis, colțuri rotunjite, fără chenar.
static func panel() -> PanelContainer:
	var new_panel := PanelContainer.new()
	var style := flat_box(Color(NAVY, 0.9))
	style.set_corner_radius_all(28)
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 32
	style.content_margin_bottom = 32
	new_panel.add_theme_stylebox_override("panel", style)
	return new_panel


## O bară de progres (viață, evoluție...). Valori 0..100.
static func bar(fill_color: Color, min_size: Vector2) -> ProgressBar:
	var new_bar := ProgressBar.new()
	new_bar.custom_minimum_size = min_size
	new_bar.show_percentage = false
	new_bar.min_value = 0
	new_bar.max_value = 100
	new_bar.value = 100
	var background := box(Color(0, 0, 0, 0.55), OUTLINE, 10, 3)
	remove_margins(background)
	var fill := box(fill_color, fill_color.lightened(0.4), 10, 2)
	fill.shadow_size = 0
	remove_margins(fill)
	new_bar.add_theme_stylebox_override("background", background)
	new_bar.add_theme_stylebox_override("fill", fill)
	return new_bar


static func remove_margins(style: StyleBoxFlat) -> void:
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0


## O coloană verticală centrată pe ecran. Pui elemente în ea cu add_child.
static func centered_vbox(parent: Node, separation: int = 16) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(column)
	return column
