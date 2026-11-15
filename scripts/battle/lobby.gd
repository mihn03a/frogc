extends Node3D
## =====================================================================
##  LOBBY.GD - camera de așteptare pentru Battle (multiplayer LAN, max 4)
## =====================================================================
##   HOST GAME    : devii server; prietenii intră cu IP-ul afișat pe ecran
##   JOIN         : scrii IP-ul host-ului și intri
##   PLAY VS BOTS : luptă offline cu 3 boți
##  Pe același Wi-Fi merge direct. Pe internet: o rețea virtuală
##  (Radmin VPN, ZeroTier) sau deschizi portul UDP 7777.
## =====================================================================

const UI = preload("res://scripts/ui/ui_style.gd")
const COLORS := [Color(0.36, 0.85, 0.26), Color(0.25, 0.55, 1.0), Color(1.0, 0.55, 0.12), Color(0.75, 0.35, 1.0)]
const RED := Color(1.0, 0.5, 0.4)
const GREEN := Color(0.5, 1.0, 0.5)

var name_edit: LineEdit
var ip_edit: LineEdit
var status_label: Label
var ip_label: Label
var player_slots: Array[Label] = []
var start_button: Button
var bots_checkbox: CheckButton
var host_button: Button
var join_button: Button


func _ready() -> void:
	get_tree().paused = false
	create_background()
	create_interface()
	Net.players_changed.connect(refresh)
	Net.connected.connect(on_connected)
	Net.connection_failed.connect(on_connection_problem)
	Net.disconnected.connect(on_connection_problem)
	refresh()
	AudioManager.play_music("menu")


func create_background() -> void:
	var env := FX.make_environment(self, Color(0.03, 0.02, 0.12), Color(0.35, 0.08, 0.5), Color(0.7, 0.8, 1.0), 0.8)
	env.glow_intensity = 1.0
	var camera := Camera3D.new()
	camera.position = Vector3(0, 6, 16)
	add_child(camera)
	camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	camera.current = true
	FX.add_mesh(self, FX.torus_mesh(9.0, 9.3, 64), FX.mat(Color(0.2, 1.0, 1.0), 4.0), Vector3(0, -2, 0))


# =====================================================================
#  INTERFAȚA
# =====================================================================
func create_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(screen)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var panel := UI.panel()
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(900, 0)
	panel.add_child(column)
	column.add_child(UI.label("BATTLE - MULTIPLAYER", 56, UI.YELLOW, 14))
	column.add_child(UI.label("Up to 4 frogs on the same network. Land on heads, Perfect-bounce shockwaves, 3 lives each.", 20, Color(0.85, 0.95, 0.85), 6))
	column.add_child(create_name_row())
	column.add_child(create_host_row())
	column.add_child(create_join_row())
	column.add_child(UI.label("PLAYERS", 30, UI.YELLOW, 8))
	column.add_child(create_player_slots())
	bots_checkbox = CheckButton.new()
	bots_checkbox.text = "Fill empty slots with bots"
	bots_checkbox.button_pressed = true
	bots_checkbox.add_theme_font_size_override("font_size", 22)
	bots_checkbox.toggled.connect(on_bots_toggled)
	column.add_child(bots_checkbox)
	column.add_child(create_bottom_buttons())
	status_label = UI.label("", 22, Color(1, 1, 1, 0.9), 6)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(880, 0)
	column.add_child(status_label)
	column.add_child(UI.label("Same Wi-Fi: use the host's IP.  Over the internet: Radmin VPN / ZeroTier IP, or forward UDP port 7777.", 18, Color(0.75, 0.85, 0.75), 6))


func create_name_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := UI.label("YOUR NAME", 24)
	name_label.custom_minimum_size = Vector2(220, 44)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(name_label)
	name_edit = make_text_box("Frog%d" % (randi() % 90 + 10), 12)
	row.add_child(name_edit)
	return row


func create_host_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	host_button = UI.button("HOST GAME", host_game, 26)
	host_button.custom_minimum_size = Vector2(280, 56)
	row.add_child(host_button)
	ip_label = UI.label("", 22, Color(0.6, 1.0, 1.0), 6)
	ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(ip_label)
	return row


func create_join_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	ip_edit = make_text_box("127.0.0.1", 40)
	ip_edit.placeholder_text = "Host IP, e.g. 192.168.1.23"
	row.add_child(ip_edit)
	join_button = UI.button("JOIN", join_game, 26)
	join_button.custom_minimum_size = Vector2(200, 56)
	row.add_child(join_button)
	return row


func create_player_slots() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	for i in 4:
		var slot := UI.label("", 26, Color.WHITE, 6)
		slot.custom_minimum_size = Vector2(430, 40)
		slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(slot)
		player_slots.append(slot)
	return grid


func create_bottom_buttons() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	start_button = UI.make_primary(UI.button("START MATCH", Net.start_match, 28))
	row.add_child(start_button)
	row.add_child(UI.button("PLAY VS BOTS", play_offline, 24))
	row.add_child(UI.button("BACK", go_back, 24))
	return row


func make_text_box(text: String, max_length: int) -> LineEdit:
	var box := LineEdit.new()
	box.text = text
	box.max_length = max_length
	box.custom_minimum_size = Vector2(380, 48)
	box.add_theme_font_size_override("font_size", 24)
	return box


# =====================================================================
#  ACȚIUNILE BUTOANELOR
# =====================================================================
func host_game() -> void:
	var error := Net.host(name_edit.text)
	if error != OK:
		set_status("Could not host (port 7777 busy?). Error %d" % error, RED)
		return
	Net.fill_bots = bots_checkbox.button_pressed
	var ips := Net.local_ips()
	if ips.is_empty():
		ip_label.text = "Your IP: 127.0.0.1"
	else:
		ip_label.text = "Your IP: " + ", ".join(ips)
	set_status("Hosting! Friends can now JOIN with your IP. Press START MATCH when ready.", GREEN)
	refresh()


func join_game() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		set_status("Type the host's IP first.", RED)
		return
	var error := Net.join(ip, name_edit.text)
	if error != OK:
		set_status("Could not start connecting. Error %d" % error, RED)
		return
	set_status("Connecting to %s ..." % ip, Color(0.6, 1.0, 1.0))
	refresh()


func play_offline() -> void:
	Net.leave()
	GameState.change_scene(GameState.BATTLE_SCENE)


func go_back() -> void:
	Net.leave()
	GameState.go_main_menu()


func on_bots_toggled(on: bool) -> void:
	Net.fill_bots = on
	refresh()


func on_connected() -> void:
	set_status("Connected! Waiting for the host to start...", GREEN)


func on_connection_problem(reason: String) -> void:
	set_status(reason, RED)
	refresh()


func set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)


# =====================================================================
#  LISTA DE JUCĂTORI
# =====================================================================
func refresh() -> void:
	var ids: Array = Net.players.keys()
	ids.sort()
	for i in 4:
		if i < ids.size():
			show_player_in_slot(player_slots[i], i, int(ids[i]))
		else:
			show_empty_slot(player_slots[i], i)
	var is_host := Net.is_host()
	var enough_players := ids.size() >= 2 or Net.fill_bots
	start_button.visible = is_host
	start_button.disabled = not is_host or not enough_players
	bots_checkbox.disabled = Net.active and not is_host   # doar host-ul alege
	host_button.disabled = Net.active
	join_button.disabled = Net.active
	if not Net.active:
		ip_label.text = ""


func show_player_in_slot(slot: Label, index: int, id: int) -> void:
	var player: Dictionary = Net.players[id]
	var text := "%d. %s" % [index + 1, player["name"]]
	if id == 1:
		text += "  (HOST)"
	if id == Net.my_id():
		text += "  (YOU)"
	slot.text = text
	slot.add_theme_color_override("font_color", COLORS[int(player["color"]) % 4].lightened(0.25))


func show_empty_slot(slot: Label, index: int) -> void:
	if Net.fill_bots:
		slot.text = "%d. BOT" % (index + 1)
	else:
		slot.text = "%d. - empty -" % (index + 1)
	slot.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
