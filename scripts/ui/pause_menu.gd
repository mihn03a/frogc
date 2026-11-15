extends CanvasLayer
## =====================================================================
##  PAUSE_MENU.GD - meniul de pauză (ESC / P / Start pe controller)
## =====================================================================
##  process_mode = ALWAYS înseamnă că meniul merge și când jocul e pe pauză.
## =====================================================================

const UI = preload("res://scripts/ui/ui_style.gd")
const PhotoMode = preload("res://scripts/ui/photo_mode.gd")

var menu: Control
var photo_mode = null    # Photo Mode, când e deschis


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30   # deasupra HUD-ului
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	var dark_background := ColorRect.new()
	dark_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark_background.color = Color(0, 0, 0, 0.6)
	menu.add_child(dark_background)
	var column := UI.centered_vbox(menu, 18)
	column.add_child(UI.label("PAUSED", 80, UI.YELLOW, 16))
	column.add_child(UI.make_primary(UI.button("RESUME", toggle)))
	column.add_child(UI.button("PHOTO MODE", open_photo_mode))
	var sound := UI.sound_button(GameState)
	sound.custom_minimum_size = Vector2(340, 64)
	column.add_child(sound)
	column.add_child(UI.button("RESTART LEVEL", GameState.restart_level))
	column.add_child(UI.button("MAIN MENU", GameState.go_main_menu))
	menu.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if photo_mode != null:
		return   # Photo Mode are propriile taste
	if event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if GameState.player_dead:
		return
	var paused := not get_tree().paused
	get_tree().paused = paused
	menu.visible = paused


func open_photo_mode() -> void:
	var level := get_parent()
	var player = level.get("player")
	if player == null or not is_instance_valid(player) or player.dead:
		return
	menu.visible = false
	set_hud_visible(false)
	photo_mode = PhotoMode.new()
	get_tree().root.add_child(photo_mode)
	photo_mode.closed.connect(on_photo_mode_closed)
	photo_mode.open(player, find_environment(level))


func find_environment(level: Node) -> Environment:
	# Photo Mode are nevoie de "Environment" ca să schimbe filtrele.
	for child in level.get_children():
		if child is WorldEnvironment:
			return (child as WorldEnvironment).environment
	return null


func on_photo_mode_closed() -> void:
	photo_mode = null
	menu.visible = true
	set_hud_visible(true)


func set_hud_visible(on: bool) -> void:
	var hud = get_parent().get("hud")
	if hud:
		hud.visible = on
