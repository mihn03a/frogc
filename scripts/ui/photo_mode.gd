extends CanvasLayer
## =====================================================================
##  PHOTO_MODE.GD - Photo Mode (se deschide din meniul de pauză)
## =====================================================================
##  Jocul rămâne înghețat; o cameră liberă se rotește în jurul broaștei.
##   Mouse (trage cu stânga)  rotire          Rotița / Q E   zoom
##   W A S D                  mută camera     R F            sus / jos
##   1-6                      filtru          V              poza broaștei
##   H                        ascunde textul  ENTER / F12    salvează poza
##   ESC                      înapoi la pauză
##  Pozele se salvează în Pictures/FROGC (sau în folderul jocului).
## =====================================================================

signal closed

const UI = preload("res://scripts/ui/ui_style.gd")
const FILTERS := [
	{"name": "NORMAL", "saturation": 1.0, "contrast": 1.0, "brightness": 1.0},
	{"name": "VIVID", "saturation": 1.7, "contrast": 1.15, "brightness": 1.05},
	{"name": "BLACK & WHITE", "saturation": 0.0, "contrast": 1.1, "brightness": 1.0},
	{"name": "NOIR", "saturation": 0.0, "contrast": 1.6, "brightness": 0.85},
	{"name": "DREAMY", "saturation": 0.75, "contrast": 0.85, "brightness": 1.2},
	{"name": "RETRO", "saturation": 0.45, "contrast": 1.3, "brightness": 0.95},
]
const POSES := [["fly", "happy"], ["victory", "serious"], ["idle", "happy"], ["sad", "sad"], ["showcase", "hurt"]]
const HELP_LINES := [
	"Mouse drag: rotate   |   Wheel or Q/E: zoom",
	"W A S D: move   |   R / F: up / down",
	"1-6: filter   |   V: frog pose   |   H: hide this text",
	"ENTER or F12: save photo   |   ESC: back",
]
const MIN_DISTANCE := 2.5
const MAX_DISTANCE := 40.0

var player
var env: Environment
var camera: Camera3D
var game_camera: Camera3D        # camera jocului, o punem la loc la închidere
# poziția camerei, în jurul broaștei:
var yaw := 0.4                   # unghiul orizontal
var pitch := -0.25               # unghiul vertical
var distance := 8.0
var camera_offset := Vector3.ZERO       # cât am mutat camera cu WASD
var filter_index := 0
var pose_index := 0
var dragging := false
var help_box: Control
var status_label: Label
var saved_adjustments := {}      # setările de culoare de dinainte


func open(the_player, environment: Environment) -> void:
	player = the_player
	env = environment
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	create_help_text()
	game_camera = get_viewport().get_camera_3d()
	camera = Camera3D.new()
	camera.process_mode = Node.PROCESS_MODE_ALWAYS
	camera.fov = 60.0
	camera.far = 1500.0
	get_tree().current_scene.add_child(camera)
	camera.current = true
	remember_color_settings()
	# broasca își poate schimba poza chiar dacă jocul e înghețat
	if player and player.model:
		player.model.process_mode = Node.PROCESS_MODE_ALWAYS
	apply_filter()
	update_camera()


func remember_color_settings() -> void:
	if env == null:
		return
	saved_adjustments = {"on": env.adjustment_enabled, "saturation": env.adjustment_saturation,
		"contrast": env.adjustment_contrast, "brightness": env.adjustment_brightness}
	env.adjustment_enabled = true


func create_help_text() -> void:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	help_box = VBoxContainer.new()
	help_box.position = Vector2(24, 20)
	screen.add_child(help_box)
	help_box.add_child(left_label("PHOTO MODE", 44, UI.YELLOW, 12))
	for line in HELP_LINES:
		help_box.add_child(left_label(line, 20, Color(1, 1, 1, 0.9), 6))
	status_label = left_label("", 22, Color(0.6, 1.0, 1.0), 6)
	help_box.add_child(status_label)


func left_label(text: String, font_size: int, color: Color, outline: int) -> Label:
	var new_label := UI.label(text, font_size, color, outline)
	new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return new_label


# =====================================================================
#  TASTATURĂ ȘI MOUSE
# =====================================================================
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		handle_mouse_button(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * 0.008
		pitch = clampf(pitch - event.relative.y * 0.006, -1.4, 1.2)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		handle_key(event.keycode)
		get_viewport().set_input_as_handled()


func handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		distance = maxf(distance - 0.6, MIN_DISTANCE)
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		distance = minf(distance + 0.6, MAX_DISTANCE)


func handle_key(key: Key) -> void:
	if key == KEY_ESCAPE or key == KEY_P:
		close()
	elif key == KEY_H:
		help_box.visible = not help_box.visible
	elif key == KEY_V:
		next_pose()
	elif key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_F12:
		take_photo()
	elif key >= KEY_1 and key <= KEY_6:
		filter_index = key - KEY_1
		apply_filter()


func next_pose() -> void:
	pose_index = (pose_index + 1) % POSES.size()
	player.model.pose = POSES[pose_index][0]
	player.model.set_expression(POSES[pose_index][1])
	status_label.text = "POSE: " + str(POSES[pose_index][0]).to_upper()


# =====================================================================
#  CAMERA (în fiecare cadru)
# =====================================================================
func _process(delta: float) -> void:
	if camera == null:
		return
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move.z -= 1
	if Input.is_key_pressed(KEY_S):
		move.z += 1
	if Input.is_key_pressed(KEY_A):
		move.x -= 1
	if Input.is_key_pressed(KEY_D):
		move.x += 1
	if Input.is_key_pressed(KEY_R):
		move.y += 1
	if Input.is_key_pressed(KEY_F):
		move.y -= 1
	if Input.is_key_pressed(KEY_Q):
		distance = maxf(distance - delta * 8.0, MIN_DISTANCE)
	if Input.is_key_pressed(KEY_E):
		distance = minf(distance + delta * 8.0, MAX_DISTANCE)
	if move != Vector3.ZERO:
		# W merge "înainte" în direcția în care privește camera
		var flat_move := Basis(Vector3.UP, yaw) * Vector3(move.x, 0, move.z)
		camera_offset += (flat_move + Vector3(0, move.y, 0)) * delta * 8.0
	update_camera()


func update_camera() -> void:
	var target: Vector3 = player.global_position + Vector3(0, 0.8, 0) + camera_offset
	# coordonate sferice: din unghiuri + distanță calculăm poziția camerei
	var direction := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	camera.global_position = target + direction * distance
	camera.look_at(target, Vector3.UP)


func apply_filter() -> void:
	var filter: Dictionary = FILTERS[filter_index]
	if env:
		env.adjustment_saturation = filter["saturation"]
		env.adjustment_contrast = filter["contrast"]
		env.adjustment_brightness = filter["brightness"]
	status_label.text = "FILTER %d: %s" % [filter_index + 1, filter["name"]]


# =====================================================================
#  SALVAREA POZEI
# =====================================================================
func take_photo() -> void:
	var help_was_visible := help_box.visible
	help_box.visible = false   # textul nu apare în poză
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := photo_folder().path_join("frogc_%s.png" % time_stamp())
	var error := image.save_png(path)
	help_box.visible = help_was_visible
	AudioManager.play("click", 0.6)
	FX.flash(Color(1, 1, 1), 0.7)
	if error == OK:
		status_label.text = "SAVED: " + path
	else:
		status_label.text = "Could not save the photo"


func photo_folder() -> String:
	var folder := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if folder == "" or not DirAccess.dir_exists_absolute(folder):
		folder = ProjectSettings.globalize_path("user://")
	folder = folder.path_join("FROGC")
	DirAccess.make_dir_recursive_absolute(folder)
	return folder


func time_stamp() -> String:
	# "2026-11-15T02:30:00" -> "2026-11-15_02-30-00" (fără ":" în numele fișierului)
	return Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")


# =====================================================================
#  ÎNCHIDERE: punem totul la loc
# =====================================================================
func close() -> void:
	if env and not saved_adjustments.is_empty():
		env.adjustment_enabled = saved_adjustments["on"]
		env.adjustment_saturation = saved_adjustments["saturation"]
		env.adjustment_contrast = saved_adjustments["contrast"]
		env.adjustment_brightness = saved_adjustments["brightness"]
	if player and is_instance_valid(player) and player.model:
		player.model.process_mode = Node.PROCESS_MODE_INHERIT
		player.model.pose = "fly"
		player.model.set_expression("happy")
	if game_camera and is_instance_valid(game_camera):
		game_camera.current = true
	if camera:
		camera.queue_free()
	closed.emit()
	queue_free()
