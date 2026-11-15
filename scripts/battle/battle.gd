extends Node3D
## =====================================================================
##  BATTLE.GD - arena de luptă pentru până la 4 broaște
## =====================================================================
##  OFFLINE: P1 ești tu, P2-P4 sunt boți.
##  ONLINE (din lobby): câte o broască pentru fiecare jucător.
##
##  Reguli:
##   - cine câștigă primul 2 runde ia meciul; în fiecare rundă ai 3 vieți
##   - rănești aterizând pe capete sau cu unda de șoc a Perfect Bounce
##   - dacă pici din arenă pierzi o viață
##   - după 30 de secunde arena se dărâmă inel cu inel (din exterior)
##   - cei eliminați privesc meciul (SPACE / click = următorul jucător)
##
##  Online, HOST-UL decide cine câștigă runda și când cad plăcile,
##  ca toate ecranele să arate la fel.
## =====================================================================

const UI = preload("res://scripts/ui/ui_style.gd")
const BattleFrog = preload("res://scripts/battle/battle_frog.gd")

const RADIUS := 20.0             # raza arenei
const TILE := 4.0                # mărimea unei plăci din podea
const LIVES := 3
const ROUNDS_TO_WIN := 2
const SHRINK_START := 30.0       # după câte secunde începe să se dărâme arena
const SHRINK_EVERY := 6.0        # la câte secunde cade următorul inel
const COLORS := [Color(0.36, 0.85, 0.26), Color(0.25, 0.55, 1.0), Color(1.0, 0.55, 0.12), Color(0.75, 0.35, 1.0)]
const FLOOR_COLOR := Color(0.08, 0.08, 0.15)
const VICTORY_SPOT := Vector3(0, 1.4, 0)   # unde stă câștigătorul în scena de victorie

var frogs: Array = []
var autoplay := false            # pentru teste: și broasca ta e controlată de bot
var net := false                 # meci în rețea?

var camera: Camera3D
var clock := 0.0
# interfața
var player_cards := []           # pentru fiecare broască: bara de viață, vieți, KO
var banner: Label                # textul mare din centru
var sub_banner: Label
var round_label: Label
var spectate_label: Label
var banner_tween: Tween
# rundele
var round_number := 0
var round_wins := [0, 0, 0, 0]
var round_active := false
var round_time := 0.0
var match_over := false
# arena
var rings := []                  # inelul -> lista de plăci (0 = centrul)
var rings_dropped := 0
var next_drop_time := 0.0
var pads := []
var current_radius := RADIUS
# rețea
var ready_players := {}
var match_started := false
# spectator
var spectate_index := 0


func _ready() -> void:
	get_tree().paused = false
	autoplay = OS.has_environment("FROGC_BATTLE_AUTOPLAY")
	net = Net.active and Net.match_running
	var env := FX.make_environment(self, Color(0.03, 0.02, 0.12), Color(0.35, 0.08, 0.5), Color(0.7, 0.8, 1.0), 0.9)
	env.glow_intensity = 1.1
	build_arena()
	spawn_frogs()
	build_hud()
	camera = Camera3D.new()
	camera.fov = 55.0
	add_child(camera)
	camera.current = true
	camera.position = Vector3(0, 30, 30)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	AudioManager.play_music("boss")
	if net:
		wait_for_all_players()
	else:
		match_started = true
		start_round(1)


func is_director() -> bool:
	# Cine ia deciziile: offline noi, online host-ul.
	return not net or Net.is_host()


# =====================================================================
#  ARENA
# =====================================================================
func build_arena() -> void:
	# Podeaua e făcută din plăci pătrate grupate pe inele, ca să poată cădea pe rând.
	var tiles_per_side := int(ceil(RADIUS / TILE))
	for i in tiles_per_side + 1:
		rings.append([])
	for grid_x in range(-tiles_per_side, tiles_per_side):
		for grid_z in range(-tiles_per_side, tiles_per_side):
			var center := Vector3((grid_x + 0.5) * TILE, 0, (grid_z + 0.5) * TILE)
			var distance := Vector2(center.x, center.z).length()
			if distance > RADIUS:
				continue   # placa e în afara cercului
			var ring := int(distance / TILE)
			rings[ring].append(create_tile(center, ring))
	# ștergem inelele goale de la final
	while not rings.is_empty() and (rings[rings.size() - 1] as Array).is_empty():
		rings.pop_back()
	for i in 4:
		create_pad(i * TAU / 4.0 + PI / 4.0)
	var glow := FX.make_emitter(Color(1.0, 0.25, 0.8), 60, 3.0, Vector3.UP, 20.0, 1.0, 3.0, Vector3.ZERO, 0.3, Vector3(RADIUS + 6, 0.5, RADIUS + 6))
	glow.position = Vector3(0, -14, 0)
	add_child(glow)
	glow.emitting = true


func create_tile(center: Vector3, ring: int) -> StaticBody3D:
	var tile := StaticBody3D.new()
	tile.position = Vector3(center.x, -0.6, center.z)
	var size := Vector3(TILE - 0.12, 1.2, TILE - 0.12)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	tile.add_child(collision)
	var top := FX.add_mesh(tile, FX.box_mesh(size), FX.mat(FLOOR_COLOR, 0.0, 0.9, 0.3))
	top.name = "Top"
	# marginea de neon alternează: turcoaz / roz
	var edge_color := Color(1.0, 0.25, 0.85)
	if ring % 2 == 0:
		edge_color = Color(0.2, 1.0, 1.0)
	var edge := FX.add_mesh(tile, FX.box_mesh(Vector3(TILE - 0.3, 0.05, TILE - 0.3)), FX.mat(edge_color, 1.6))
	edge.position.y = 0.62
	tile.set_meta("base_pos", tile.position)   # ca s-o putem pune la loc
	add_child(tile)
	return tile


func create_pad(angle: float) -> void:
	var pad := StaticBody3D.new()
	pad.position = Vector3(cos(angle) * 11.0, 0.25, sin(angle) * 11.0)
	pad.set_meta("kind", "pad")
	pad.set_meta("ring", int(11.0 / TILE))
	var shape := CylinderShape3D.new()
	shape.radius = 2.0
	shape.height = 0.5
	var collision := CollisionShape3D.new()
	collision.shape = shape
	pad.add_child(collision)
	FX.add_mesh(pad, FX.cyl_mesh(2.0, 2.0, 0.5, 24), FX.mat(Color(1.0, 0.3, 0.6), 2.0))
	FX.add_mesh(pad, FX.torus_mesh(1.7, 2.0, 24), FX.mat(Color(1.0, 0.95, 0.3), 4.0), Vector3(0, 0.3, 0))
	pad.set_meta("base_pos", pad.position)
	add_child(pad)
	pads.append(pad)


func reset_arena() -> void:
	for ring in rings:
		for tile in ring:
			restore_piece(tile)
	for pad in pads:
		restore_piece(pad)
	rings_dropped = 0
	set_arena_radius(RADIUS)


func set_arena_radius(radius: float) -> void:
	current_radius = radius
	for frog in frogs:
		frog.arena_radius = radius   # boții știu unde e marginea


func restore_piece(piece: Node3D) -> void:
	piece.position = piece.get_meta("base_pos")
	piece.visible = true
	(piece as CollisionObject3D).collision_layer = 1
	set_top_color(piece, FX.mat(FLOOR_COLOR, 0.0, 0.9, 0.3))


func set_top_color(piece: Node3D, material: Material) -> void:
	for child in piece.get_children():
		if child is MeshInstance3D and child.name == "Top":
			(child as MeshInstance3D).material_override = material


## Dărâmă cel mai din exterior inel rămas (rulează pe toți, decis de host).
@rpc("authority", "call_local", "reliable")
func drop_ring(ring_index: int) -> void:
	if ring_index < 1 or ring_index >= rings.size():
		return
	rings_dropped = maxi(rings_dropped, rings.size() - ring_index)
	set_arena_radius(ring_index * TILE)
	announce("THE ARENA IS CRUMBLING!", Color(1.0, 0.45, 0.3), 1.2)
	AudioManager.play("slam", 0.8)
	FX.shake(0.4)
	var pieces: Array = rings[ring_index].duplicate()
	for pad in pads:
		if int(pad.get_meta("ring")) >= ring_index:
			pieces.append(pad)
	for piece in pieces:
		crumble(piece)


func crumble(piece: Node3D) -> void:
	# 1,2 s: se înroșește și tremură, apoi cade
	set_top_color(piece, FX.mat(Color(0.9, 0.15, 0.1), 1.5, 0.3, 0.5))
	var start: Vector3 = piece.position
	var tween := piece.create_tween()
	for i in 6:
		var shake := Vector3(randf_range(-0.12, 0.12), 0, randf_range(-0.12, 0.12))
		tween.tween_property(piece, "position", start + shake, 0.1)
	tween.tween_property(piece, "position", start, 0.05)
	tween.tween_callback(piece.set.bind("collision_layer", 0))   # nu mai e solidă
	tween.tween_property(piece, "position", start + Vector3(0, -30, 0), 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(piece.hide)


# =====================================================================
#  BROAȘTELE
# =====================================================================
func spawn_frogs() -> void:
	var slots := make_player_slots()
	for i in slots.size():
		create_frog(i, slots[i])
	for frog in frogs:
		frog.others = frogs


func make_player_slots() -> Array:
	# Fiecare loc: [id-ul proprietarului, nume, culoare, e bot?]
	var slots := []
	if not net:
		slots.append([1, "YOU", 0, autoplay])
		for i in range(1, 4):
			slots.append([1, "BOT", i, true])
		return slots
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		var player: Dictionary = Net.players[id]
		slots.append([int(id), str(player["name"]), int(player["color"]), false])
	if Net.fill_bots:
		var used_colors := []
		for slot in slots:
			used_colors.append(slot[2])
		var color := 0
		while slots.size() < 4:
			while color in used_colors:
				color += 1
			slots.append([1, "BOT", color, true])   # boții aparțin host-ului
			used_colors.append(color)
	return slots


func create_frog(index: int, slot: Array) -> void:
	var owner_id: int = slot[0]
	var is_bot: bool = slot[3]
	var is_mine := not net or owner_id == multiplayer.get_unique_id()
	var label := "P%d %s" % [index + 1, slot[1]]
	if net and not is_bot and is_mine:
		label += " (YOU)"
	var frog := BattleFrog.new()
	frog.name = "Frog_%d" % (index + 1)   # același nume pe toate calculatoarele (necesar pentru RPC)
	frog.setup(index + 1, label, COLORS[int(slot[2]) % COLORS.size()], is_bot or not is_mine, Vector3.ZERO, RADIUS)
	frog.is_bot = is_bot
	frog.net_mode = net
	frog.set_multiplayer_authority(owner_id)
	frog.position = spawn_point(index)
	frog.stocks = LIVES
	add_child(frog)
	frog.knocked_out.connect(on_frog_knocked_out)
	frogs.append(frog)


func spawn_point(index: int) -> Vector3:
	var angle := index * TAU / 4.0
	return Vector3(cos(angle) * 9.0, 4.0, sin(angle) * 9.0)


func local_frog():
	# Broasca controlată de acest calculator.
	for frog in frogs:
		if frog.is_bot:
			continue
		if not net or frog.get_multiplayer_authority() == multiplayer.get_unique_id():
			return frog
	return null


# =====================================================================
#  PORNIREA ÎN REȚEA (așteptăm să fie toți gata)
# =====================================================================
func wait_for_all_players() -> void:
	Net.peer_left.connect(on_player_left)
	Net.disconnected.connect(on_disconnected)
	announce("WAITING FOR ALL PLAYERS...", Color(0.6, 1.0, 1.0), 30.0)
	if Net.is_host():
		ready_players[1] = true
		check_all_ready()
		# dacă cineva nu răspunde, pornim oricum după 8 secunde
		get_tree().create_timer(8.0).timeout.connect(start_if_not_started)
	else:
		client_is_ready.rpc_id(1)


func start_if_not_started() -> void:
	if not match_started:
		match_started = true
		start_round.rpc(1)


@rpc("any_peer", "call_remote", "reliable")
func client_is_ready() -> void:
	if not multiplayer.is_server():
		return
	ready_players[multiplayer.get_remote_sender_id()] = true
	check_all_ready()


func check_all_ready() -> void:
	for id in Net.players.keys():
		if not ready_players.has(int(id)):
			return
	start_if_not_started()


# =====================================================================
#  RUNDELE
# =====================================================================
@rpc("authority", "call_local", "reliable")
func start_round(number: int) -> void:
	round_number = number
	round_active = false
	round_time = 0.0
	next_drop_time = SHRINK_START
	reset_arena()
	for i in frogs.size():
		frogs[i].reset_for_round(spawn_point(i), LIVES)
	update_round_label()
	announce("ROUND %d" % number, Color(1.0, 0.9, 0.3), 0.9)
	await get_tree().create_timer(1.2).timeout
	for count in ["3", "2", "1"]:
		announce(count, Color(1.0, 0.9, 0.3), 0.45)
		AudioManager.play("click", 1.5)
		await get_tree().create_timer(0.75).timeout
	announce("BOUNCE!", Color(0.5, 1.0, 0.5), 0.7)
	AudioManager.play("perfect")
	for frog in frogs:
		if frog.stocks > 0:
			frog.frozen = false
	round_active = true


func on_frog_knocked_out(frog) -> void:
	if frog.stocks > 0:
		var word := "lives"
		if frog.stocks == 1:
			word = "life"
		announce("%s IS OUT!  (%d %s left)" % [frog.display_name, frog.stocks, word], frog.color.lightened(0.3))
	else:
		announce("%s IS ELIMINATED!" % frog.display_name, Color(1.0, 0.4, 0.3))
	check_round_end()


func check_round_end() -> void:
	if not round_active or not is_director():
		return
	var still_in := []
	for i in frogs.size():
		if frogs[i].stocks > 0:
			still_in.append(i)
	if still_in.size() > 1:
		return
	var winner := -1   # -1 = egalitate (toți au căzut deodată)
	if still_in.size() == 1:
		winner = still_in[0]
	if net:
		end_round.rpc(winner)
	else:
		end_round(winner)


@rpc("authority", "call_local", "reliable")
func end_round(winner_index: int) -> void:
	if not round_active:
		return
	round_active = false
	for frog in frogs:
		frog.frozen = true
	if winner_index >= 0:
		round_wins[winner_index] += 1
	update_round_label()
	var champion := find_champion()
	await get_tree().create_timer(1.0).timeout
	if champion >= 0:
		finish_match(frogs[champion])
		return
	if winner_index >= 0:
		var winner = frogs[winner_index]
		announce("%s WINS ROUND %d!" % [winner.display_name, round_number], winner.color.lightened(0.4), 2.6)
		winner.model.pose = "victory"
		winner.model.set_expression("serious")
	else:
		announce("ROUND %d: DRAW!" % round_number, Color.WHITE, 2.6)
	sub_banner.text = score_text()
	sub_banner.modulate.a = 1.0
	await get_tree().create_timer(3.5).timeout
	sub_banner.modulate.a = 0.0
	if is_director():
		if net:
			start_round.rpc(round_number + 1)
		else:
			start_round(round_number + 1)


func find_champion() -> int:
	for i in round_wins.size():
		if round_wins[i] >= ROUNDS_TO_WIN:
			return i
	return -1


func score_text() -> String:
	var parts := []
	for i in frogs.size():
		parts.append("%s: %d" % [frogs[i].display_name, round_wins[i]])
	return "ROUND WINS   " + "   |   ".join(parts) + "   (first to %d)" % ROUNDS_TO_WIN


func finish_match(winner) -> void:
	# Câștigătorul primește aceeași scenă de victorie ca la finalul jocului normal.
	match_over = true
	AudioManager.stop_music()
	# melodia ta de victorie (assets/audio/victory.*) dacă există, altfel fanfara
	if not AudioManager.play_custom("victory", ""):
		AudioManager.play("victory")
	stage_winner(winner)
	clear_hud_for_victory()
	create_victory_effects(winner.global_position)
	sub_banner.text = score_text()
	sub_banner.modulate.a = 0.0
	play_victory_cinematic(winner)


func stage_winner(winner) -> void:
	# Oprim toate broaștele, le ascundem pe celelalte și o punem pe cea
	# câștigătoare în centru, cu fața spre cameră, în poza de victorie.
	for frog in frogs:
		frog.set_physics_process(false)   # nici rețeaua nu le mai mută
		frog.velocity = Vector3.ZERO
		frog.visible = frog == winner
	winner.global_position = VICTORY_SPOT
	winner.model.rotation = Vector3(0, PI, 0)   # modelul privește spre -Z; îl întoarcem spre cameră
	winner.model.pose = "victory"
	winner.model.set_expression("serious")
	winner.model.set_blink(false)
	for child in winner.get_children():
		if child is Label3D:
			child.visible = false   # ascundem eticheta cu numele de deasupra capului


func clear_hud_for_victory() -> void:
	# Lăsăm pe ecran doar textul mare (sus) și sloganul, ca în scena de victorie.
	for element in banner.get_parent().get_children():
		if element != banner and element != sub_banner:
			element.visible = false
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.offset_left = -800
	banner.offset_right = 800
	banner.offset_top = 40
	banner.offset_bottom = 150
	sub_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sub_banner.offset_left = -900
	sub_banner.offset_right = 900
	sub_banner.offset_top = 150
	sub_banner.offset_bottom = 200


func create_victory_effects(spot: Vector3) -> void:
	# inele de neon sub broască, reflector, lumină turcoaz, confetti și aură
	for radius in [2.0, 3.5, 5.0]:
		FX.add_mesh(self, FX.torus_mesh(radius - 0.08, radius + 0.08, 48), FX.mat(Color(0.2, 1.0, 1.0), 3.5), spot + Vector3(0, -1.2, 0))
	var spotlight := SpotLight3D.new()
	spotlight.position = spot + Vector3(0, 9, 5)
	spotlight.light_energy = 9.0
	spotlight.spot_range = 25.0
	spotlight.spot_angle = 22.0
	add_child(spotlight)
	spotlight.look_at(spot, Vector3.UP)
	var rim_light := OmniLight3D.new()
	rim_light.position = spot + Vector3(0, 2, -2)
	rim_light.light_color = Color(0.3, 1.0, 1.0)
	rim_light.light_energy = 3.0
	rim_light.omni_range = 6.0
	add_child(rim_light)
	add_victory_emitter(FX.make_emitter(Color(1.0, 0.85, 0.3), 120, 4.0, Vector3.DOWN, 30.0, 1.0, 3.0, Vector3(0, -3, 0), 0.22, Vector3(10, 0.5, 6)), spot + Vector3(0, 11, 0))
	add_victory_emitter(FX.make_emitter(Color(0.4, 1.0, 0.5), 80, 4.0, Vector3.DOWN, 30.0, 1.0, 3.0, Vector3(0, -3, 0), 0.22, Vector3(10, 0.5, 6)), spot + Vector3(0, 11, 0))
	add_victory_emitter(FX.make_emitter(Color(0.3, 1.0, 1.0), 60, 1.5, Vector3.UP, 20.0, 1.0, 3.0, Vector3.ZERO, 0.15, Vector3(1.5, 0.2, 1.5)), spot + Vector3(0, -1.2, 0))


func add_victory_emitter(emitter: GPUParticles3D, pos: Vector3) -> void:
	emitter.position = pos
	add_child(emitter)
	emitter.emitting = true


func play_victory_cinematic(winner) -> void:
	# 1) camera se apropie încet de câștigător
	camera.position = VICTORY_SPOT + Vector3(0, 3.5, 16)
	var push_in := create_tween()
	push_in.tween_property(camera, "position", VICTORY_SPOT + Vector3(0, 1.9, 10.5), 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await get_tree().create_timer(1.2).timeout
	# 2) numele câștigătorului + sloganul, cu efect elastic
	FX.flash(Color(1, 1, 0.7), 0.4)
	announce("%s WINS!" % winner.display_name, winner.color.lightened(0.4), 9.0)
	sub_banner.text = "BOUNCE BACK. NEVER GIVE UP!"
	sub_banner.add_theme_color_override("font_color", UI.YELLOW)
	var slogan_in := create_tween()
	slogan_in.tween_property(sub_banner, "modulate:a", 1.0, 0.5)
	# 3) artificii
	for i in 6:
		var offset := Vector3(randf_range(-6, 6), randf_range(3, 7), randf_range(-4, 1))
		FX.burst(VICTORY_SPOT + offset, Color(randf(), 1.0, randf()), 32, 10.0, 0.35, -3.0)
		await get_tree().create_timer(0.5).timeout
	# 4) scorul rundelor, apoi înapoi în meniu
	await get_tree().create_timer(2.0).timeout
	sub_banner.text = score_text()
	await get_tree().create_timer(4.0).timeout
	leave()


# =====================================================================
#  ÎN FIECARE CADRU
# =====================================================================
func _process(delta: float) -> void:
	clock += delta
	update_player_cards()
	if round_active:
		round_time += delta
		if is_director() and round_time >= next_drop_time:
			next_drop_time += SHRINK_EVERY
			drop_next_ring()
		check_round_end()
	update_camera(delta)


func drop_next_ring() -> void:
	var ring_to_drop := rings.size() - 1 - rings_dropped
	if ring_to_drop < 1:
		return   # centrul nu cade niciodată
	if net:
		drop_ring.rpc(ring_to_drop)
	else:
		drop_ring(ring_to_drop)


func update_player_cards() -> void:
	for i in frogs.size():
		var frog = frogs[i]
		var card: Dictionary = player_cards[i]
		(card["hp"] as ProgressBar).value = frog.hp
		(card["lives"] as Label).text = "LIVES %d" % maxi(frog.stocks, 0)
		(card["ko"] as Label).text = "KO %d   WINS %d" % [frog.kos, round_wins[i]]
		var panel: Control = card["panel"]
		if frog.stocks > 0:
			panel.modulate.a = 1.0
		else:
			panel.modulate.a = 0.35   # eliminat: cartonaș estompat


func update_camera(delta: float) -> void:
	if match_over:
		# în scena de victorie camera privește broasca (puțin deasupra, pentru brațele ridicate)
		camera.look_at(VICTORY_SPOT + Vector3(0, 1.3, -2.0), Vector3.UP)
		return
	var me = local_frog()
	var spectating: bool = me != null and me.stocks <= 0 and not match_over and round_active
	spectate_label.visible = spectating
	if spectating:
		follow_spectated_frog(delta)
	else:
		follow_all_frogs(delta)


func follow_spectated_frog(delta: float) -> void:
	var living := []
	for frog in frogs:
		if frog.stocks > 0:
			living.append(frog)
	if living.is_empty():
		return
	spectate_index = posmod(spectate_index, living.size())
	var target = living[spectate_index]
	spectate_label.text = "SPECTATING: %s   (SPACE / CLICK = next player)" % target.display_name
	var target_pos: Vector3 = target.global_position
	camera.position = camera.position.lerp(target_pos + Vector3(0, 9, 13), 1.0 - exp(-delta * 4.0))
	camera.look_at(target_pos + Vector3(0, 1, 0), Vector3.UP)


func follow_all_frogs(delta: float) -> void:
	# Camera urmărește centrul tuturor broaștelor în viață.
	var middle := Vector3.ZERO
	var count := 0
	for frog in frogs:
		if frog.alive and frog.stocks > 0:
			middle += frog.global_position
			count += 1
	if count > 0:
		middle /= count
	middle.y = 0.0
	var zoom := lerpf(0.75, 1.0, current_radius / RADIUS)   # mai aproape când arena se micșorează
	var target := middle * 0.35 + Vector3(0, 27, 27) * zoom
	camera.position = camera.position.lerp(target + Vector3(sin(clock * 0.3) * 1.5, 0, 0), 1.0 - exp(-delta * 2.0))
	camera.look_at(middle * 0.5, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		leave()
		return
	var me = local_frog()
	if me != null and me.stocks <= 0:
		var clicked: bool = event is InputEventMouseButton and event.pressed
		if event.is_action_pressed("bounce") or clicked:
			spectate_index += 1


func leave() -> void:
	if net:
		Net.leave()
	GameState.go_main_menu()


# =====================================================================
#  EVENIMENTE DE REȚEA
# =====================================================================
func on_player_left(peer_id: int) -> void:
	for frog in frogs:
		if frog.get_multiplayer_authority() == peer_id and frog.stocks > 0 and not frog.is_bot:
			announce("%s LEFT THE GAME" % frog.display_name, Color(1.0, 0.5, 0.4))
			frog.force_eliminate()


func on_disconnected(reason: String) -> void:
	for frog in frogs:
		frog.set_physics_process(false)
	announce(reason, Color(1.0, 0.5, 0.4), 2.5)
	await get_tree().create_timer(3.0).timeout
	GameState.go_main_menu()


# =====================================================================
#  INTERFAȚA
# =====================================================================
func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	round_label = top_label("", 40, UI.YELLOW, 12, 600, 12, 66)
	screen.add_child(round_label)
	screen.add_child(top_label("WASD move   SPACE bounce (time it = PERFECT shockwave)   Land on heads!   ESC menu", 20, Color(1, 1, 1, 0.85), 6, 700, 64, 94))
	screen.add_child(create_player_cards())
	banner = center_label("", 72, Color.WHITE, 18, 800, -160, -60)
	screen.add_child(banner)
	sub_banner = center_label("", 26, Color(0.9, 0.95, 1.0), 8, 900, -50, 0)
	screen.add_child(sub_banner)
	spectate_label = top_label("", 30, Color(0.6, 1.0, 1.0), 10, 700, 100, 140)
	spectate_label.visible = false
	screen.add_child(spectate_label)


func top_label(text: String, font_size: int, color: Color, outline: int, half_width: float, top: float, bottom: float) -> Label:
	var new_label := UI.label(text, font_size, color, outline)
	new_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	new_label.offset_left = -half_width
	new_label.offset_right = half_width
	new_label.offset_top = top
	new_label.offset_bottom = bottom
	return new_label


func center_label(text: String, font_size: int, color: Color, outline: int, half_width: float, top: float, bottom: float) -> Label:
	var new_label := UI.label(text, font_size, color, outline)
	new_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	new_label.offset_left = -half_width
	new_label.offset_right = half_width
	new_label.offset_top = top
	new_label.offset_bottom = bottom
	new_label.modulate.a = 0.0
	return new_label


func create_player_cards() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_left = -760
	row.offset_right = 760
	row.offset_top = -150
	row.offset_bottom = -16
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	for frog in frogs:
		row.add_child(create_player_card(frog))
	return row


func create_player_card(frog) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.06, 0.1, 0.85), frog.color, 16, 5))
	panel.custom_minimum_size = Vector2(340, 120)
	var column := VBoxContainer.new()
	panel.add_child(column)
	column.add_child(UI.label(frog.display_name, 28, frog.color.lightened(0.3), 8))
	var hp_bar := UI.bar(frog.color, Vector2(300, 22))
	column.add_child(hp_bar)
	var info := HBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 24)
	column.add_child(info)
	var lives := UI.label("LIVES 3", 22, Color.WHITE, 6)
	var ko := UI.label("KO 0", 22, Color(1.0, 0.8, 0.4), 6)
	info.add_child(lives)
	info.add_child(ko)
	player_cards.append({"hp": hp_bar, "lives": lives, "ko": ko, "panel": panel})
	return panel


func update_round_label() -> void:
	round_label.text = "BATTLE  -  ROUND %d  (best of %d)" % [maxi(round_number, 1), ROUNDS_TO_WIN * 2 - 1]


func announce(text: String, color: Color, hold: float = 1.8) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	banner.scale = Vector2(0.5, 0.5)
	banner.pivot_offset = Vector2(800, 50)
	if banner_tween and banner_tween.is_valid():
		banner_tween.kill()
	banner_tween = create_tween()
	banner_tween.tween_property(banner, "modulate:a", 1.0, 0.15)
	banner_tween.parallel().tween_property(banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	banner_tween.tween_interval(hold)
	banner_tween.tween_property(banner, "modulate:a", 0.0, 0.4)
