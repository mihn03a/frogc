extends CharacterBody3D
## =====================================================================
##  BATTLE_FROG.GD - un luptător din modul Battle (om sau bot)
## =====================================================================
##  Aceleași reguli de bounce ca în arena boss-ului:
##   - aterizezi pe capul altei broaște    -> damage + o săritură mare
##   - Perfect Bounce (SPACE chiar înainte de aterizare)
##                                         -> undă de șoc care rănește și împinge
##   - cazi din arenă sau ajungi la 0 HP   -> pierzi o viață, revii după 2 s
##
##  REȚEA: fiecare broască are un "proprietar" (multiplayer authority) =
##  calculatorul care o controlează (boții aparțin host-ului).
##  Proprietarul simulează broasca și trimite starea ei de ~30 de ori pe
##  secundă; ceilalți doar o afișează. Loviturile sunt trimise proprietarului
##  victimei, care scade viața - așa HP-ul e mereu același peste tot.
## =====================================================================

signal knocked_out(frog)
signal damaged(frog, amount: float)

const PlayerModel = preload("res://scripts/player/player_model.gd")
const GRAVITY := 26.0
const SPEED := 13.0
const BOUNCE := 12.0
const PERFECT_BOUNCE := 18.0
const PAD_BOUNCE := 25.0
const STOMP_DAMAGE := 22.0
const PERFECT_STOMP := 34.0
const WAVE_DAMAGE := 12.0
const WAVE_RADIUS := 5.5
const MAX_HP := 100.0
const PERFECT_WINDOW := 0.2
# netezirea mișcării în rețea
const SEND_RATE := 1.0 / 30.0     # trimitem starea de 30 de ori pe secundă
const INTERP_DELAY := 0.1         # afișăm broaștele altora cu 0,1 s "în trecut"
const MAX_EXTRAPOLATE := 0.25     # cât "ghicim" înainte dacă întârzie pachetele

# ---------------------------------------------------------------- setări (din battle.gd)
var player_id := 1
var display_name := "P1"
var color := Color(0.36, 0.8, 0.26)
var is_bot := true
var arena_center := Vector3.ZERO
var arena_radius := 20.0
var others: Array = []            # toate broaștele din meci
var net_mode := false             # true = meci în rețea
var frozen := true                # true până se termină numărătoarea inversă

# ---------------------------------------------------------------- stare
var hp := MAX_HP
var stocks := 3                   # vieți rămase
var alive := true
var kos := 0                      # câte broaște a eliminat
var model

# ---------------------------------------------------------------- interne
var clock := 0.0
var last_brace_time := -10.0
var invuln := 0.0
var respawn_timer := 0.0
var wave_cooldown := 0.0
var last_hitter = null            # cine ne-a lovit ultimul (primește KO-ul)
var send_timer := 0.0
var snapshots: Array = []         # stările primite: [{t, pos, vel, yaw}]
# creierul botului
var bot_think_timer := 0.0
var bot_target = null
var bot_skill := 0.6


func setup(id: int, name_text: String, frog_color: Color, bot: bool, center: Vector3, radius: float) -> void:
	player_id = id
	display_name = name_text
	color = frog_color
	is_bot = bot
	arena_center = center
	arena_radius = radius
	bot_skill = randf_range(0.45, 0.8)


func _ready() -> void:
	add_to_group("battle_frog")
	collision_layer = 2
	collision_mask = 1 | 2      # lumea + celelalte broaște
	var shape := SphereShape3D.new()
	shape.radius = 0.95
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)
	model = PlayerModel.new()
	model.body_color_override = color
	add_child(model)
	model.build(3)
	model.pose = "fly"
	add_name_tag()


func add_name_tag() -> void:
	var tag := Label3D.new()
	tag.text = display_name
	tag.font_size = 64
	tag.outline_size = 14
	tag.modulate = color.lightened(0.3)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.pixel_size = 0.01
	tag.position = Vector3(0, 2.6, 0)
	add_child(tag)


# =====================================================================
#  ÎN FIECARE CADRU
# =====================================================================
func _physics_process(delta: float) -> void:
	clock += delta
	if net_mode and not is_multiplayer_authority():
		show_remote_frog()   # broasca altcuiva: doar o afișăm
		return
	if net_mode:
		send_state_regularly(delta)
	if frozen:
		return
	if not alive:
		respawn_timer -= delta
		if respawn_timer <= 0.0 and stocks > 0:
			respawn()
		return
	invuln = maxf(invuln - delta, 0.0)
	wave_cooldown -= delta
	model.set_blink(invuln > 0.0)
	var input := Vector2.ZERO
	if is_bot:
		input = bot_decide(delta)
	else:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if Input.is_action_just_pressed("bounce"):
			brace()
	move(input, delta)


func send_state_regularly(delta: float) -> void:
	send_timer -= delta
	if send_timer <= 0.0:
		send_timer = SEND_RATE
		receive_state.rpc(global_position, velocity, model.rotation.y, hp, stocks, alive, kos, invuln > 0.0, str(model.pose))


func brace() -> void:
	last_brace_time = clock
	model.squash()


func is_braced() -> bool:
	return clock - last_brace_time <= PERFECT_WINDOW


func move(input: Vector2, delta: float) -> void:
	var wanted := Vector3(input.x, 0, input.y) * SPEED
	velocity.x = move_toward(velocity.x, wanted.x, 50.0 * delta)
	velocity.z = move_toward(velocity.z, wanted.z, 50.0 * delta)
	velocity.y = maxf(velocity.y - GRAVITY * delta, -30.0)
	var collision := move_and_collide(velocity * delta)
	if collision:
		handle_collision(collision)
	if global_position.y < -10.0:
		knock_out("fell off the arena")
	# broasca se întoarce în direcția în care merge
	var flat := Vector3(velocity.x, 0, velocity.z)
	if flat.length() > 1.0:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-flat.x, -flat.z), delta * 10.0)
	model.pitch = clampf(velocity.y / 20.0, -1.0, 1.0)


# =====================================================================
#  COLIZIUNI
# =====================================================================
func handle_collision(collision: KinematicCollision3D) -> void:
	var other = collision.get_collider()
	var normal := collision.get_normal()
	if other != null and other.is_in_group("battle_frog"):
		hit_other_frog(other, normal)
		return
	# ricoșeu din podea / pereți (ca o minge)
	var into_surface := velocity.dot(normal)
	if into_surface < 0.0:
		velocity -= 1.8 * into_surface * normal
	if normal.y > 0.5:
		land_on_floor(other)


func hit_other_frog(other, normal: Vector3) -> void:
	if normal.y > 0.5 and other.alive:
		# am aterizat pe capul ei
		var perfect := is_braced()
		var damage := STOMP_DAMAGE
		var jump := BOUNCE
		if perfect:
			damage = PERFECT_STOMP
			jump = PERFECT_BOUNCE
			last_brace_time = -10.0
		other.request_hit(damage, self)
		velocity.y = jump + 4.0
	else:
		# ne-am lovit din lateral: ne împingem
		var push := normal
		push.y = 0.0
		velocity += push.normalized() * 8.0


func land_on_floor(floor_body) -> void:
	var on_pad := false
	if floor_body != null:
		on_pad = str(floor_body.get_meta("kind", "")) == "pad"
	var perfect := is_braced()
	var jump := BOUNCE
	if on_pad:
		jump = PAD_BOUNCE
	elif perfect:
		jump = PERFECT_BOUNCE
	velocity.y = maxf(velocity.y, jump)
	model.squash()
	if perfect and wave_cooldown <= 0.0:
		last_brace_time = -10.0
		wave_cooldown = 0.4
		shockwave()
	else:
		AudioManager.play("bounce", randf_range(0.9, 1.2), 0.05)


func shockwave() -> void:
	# Perfect Bounce: rănește toate broaștele din jur.
	show_wave_effects()
	if net_mode:
		show_wave_effects_everywhere.rpc()
	for frog in others:
		if frog == self or not frog.alive:
			continue
		if frog.global_position.distance_to(global_position) < WAVE_RADIUS:
			frog.request_hit(WAVE_DAMAGE, self, 15.0)


func show_wave_effects() -> void:
	AudioManager.play("perfect")
	FX.burst(global_position, color.lightened(0.4), 32, 12.0, 0.45, -2.0)
	FX.popup(global_position + Vector3.UP * 2.0, "PERFECT!", Color(0.4, 1.0, 1.0), 60)


# =====================================================================
#  DAMAGE, ELIMINARE, REVENIRE
# =====================================================================
## Folosește ASTA ca să rănești o broască: merge local și în rețea.
func request_hit(amount: float, attacker, knock := 11.0) -> void:
	if not net_mode or is_multiplayer_authority():
		take_hit(amount, attacker, knock)
	else:
		# trimitem lovitura calculatorului care deține broasca
		receive_hit.rpc_id(get_multiplayer_authority(), amount, String(attacker.name), knock)


func take_hit(amount: float, attacker, knock := 11.0) -> void:
	if not alive or invuln > 0.0 or frozen:
		return
	hp = maxf(hp - amount, 0.0)
	invuln = 0.6
	last_hitter = attacker
	var away: Vector3 = global_position - (attacker as Node3D).global_position
	away.y = 0.0
	velocity = away.normalized() * knock + Vector3.UP * 9.0
	show_hit_effects(amount)
	if net_mode:
		show_hit_effects_everywhere.rpc(amount)
	damaged.emit(self, amount)
	if hp <= 0.0:
		knock_out("splatted")


func knock_out(_reason: String) -> void:
	if not alive:
		return
	alive = false
	stocks -= 1
	visible = false
	collision_layer = 0
	respawn_timer = 2.0
	FX.burst(global_position, color, 32, 12.0, 0.5)
	AudioManager.play("enemy_die", 0.7)
	give_ko_to_last_hitter()
	knocked_out.emit(self)


func give_ko_to_last_hitter() -> void:
	if last_hitter == null or not is_instance_valid(last_hitter) or last_hitter == self:
		return
	if net_mode and not last_hitter.is_multiplayer_authority():
		last_hitter.add_ko.rpc_id(last_hitter.get_multiplayer_authority())
	else:
		last_hitter.kos += 1


func show_hit_effects(amount: float) -> void:
	model.hurt(0.6)
	AudioManager.play("damage", randf_range(0.9, 1.2))
	FX.burst(global_position, Color(1.0, 0.4, 0.3), 20, 8.0, 0.3)
	FX.popup(global_position + Vector3.UP * 1.6, "-%d" % int(amount), Color(1.0, 0.45, 0.35), 64)
	FX.shake(0.2)


## Un jucător care a ieșit din meci: eliminat definitiv.
func force_eliminate() -> void:
	stocks = 0
	alive = false
	visible = false
	collision_layer = 0
	knocked_out.emit(self)


func respawn() -> void:
	alive = true
	hp = MAX_HP
	visible = true
	collision_layer = 2
	last_hitter = null
	# reapare din cer, într-un loc aleator din arenă
	var angle := randf() * TAU
	var distance := minf(6.0, maxf(arena_radius - 4.0, 0.5))
	global_position = arena_center + Vector3(cos(angle) * distance, 10.0, sin(angle) * distance)
	velocity = Vector3.ZERO
	invuln = 1.5
	FX.burst(global_position, Color(1, 1, 1), 24, 6.0, 0.3, 0.0)


## Rundă nouă: viață plină, toate viețile, înapoi la locul de start.
func reset_for_round(spawn: Vector3, lives: int) -> void:
	hp = MAX_HP
	stocks = lives
	alive = true
	visible = true
	collision_layer = 2
	kos = 0
	last_hitter = null
	invuln = 0.0
	respawn_timer = 0.0
	velocity = Vector3.ZERO
	global_position = spawn
	snapshots.clear()
	frozen = true
	model.pose = "fly"
	model.set_expression("happy")


# =====================================================================
#  REȚEA
# =====================================================================
func seconds_now() -> float:
	return Time.get_ticks_msec() / 1000.0


## "Snapshot interpolation": desenăm broaștele altora puțin în trecut,
## între două stări primite, ca mișcarea să fie lină chiar dacă pachetele
## vin neregulat.
func show_remote_frog() -> void:
	if snapshots.is_empty() or not alive:
		return
	var render_time := seconds_now() - INTERP_DELAY
	# aruncăm stările prea vechi (păstrăm măcar 2)
	while snapshots.size() > 2 and float(snapshots[1]["t"]) <= render_time:
		snapshots.pop_front()
	var older: Dictionary = snapshots[0]
	var has_newer := snapshots.size() >= 2 and float(snapshots[1]["t"]) > render_time
	if has_newer and float(older["t"]) <= render_time:
		# suntem între 2 stări: amestecăm pozițiile
		var newer: Dictionary = snapshots[1]
		var duration := maxf(float(newer["t"]) - float(older["t"]), 0.001)
		var blend := clampf((render_time - float(older["t"])) / duration, 0.0, 1.0)
		global_position = (older["pos"] as Vector3).lerp(newer["pos"], blend)
		model.rotation.y = lerp_angle(float(older["yaw"]), float(newer["yaw"]), blend)
	else:
		# nu avem încă o stare mai nouă: ghicim puțin înainte din ultima viteză
		var latest: Dictionary = snapshots[snapshots.size() - 1]
		var ahead := clampf(render_time - float(latest["t"]), 0.0, MAX_EXTRAPOLATE)
		global_position = (latest["pos"] as Vector3) + (latest["vel"] as Vector3) * ahead
		model.rotation.y = float(latest["yaw"])


## Primim starea broaștei de la proprietarul ei.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func receive_state(pos: Vector3, vel: Vector3, yaw: float, new_hp: float, new_stocks: int, is_alive: bool, new_kos: int, blinking: bool, pose_name: String) -> void:
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return   # doar proprietarul are voie să trimită
	velocity = vel
	snapshots.append({"t": seconds_now(), "pos": pos, "vel": vel, "yaw": yaw})
	if snapshots.size() > 20:
		snapshots.pop_front()
	model.set_blink(blinking)
	if model.pose != pose_name:
		model.pose = pose_name
	hp = new_hp
	kos = new_kos
	if is_alive != alive:
		set_alive_from_network(is_alive, pos)
	if new_stocks < stocks:
		stocks = new_stocks
		knocked_out.emit(self)
	stocks = new_stocks


func set_alive_from_network(is_alive: bool, pos: Vector3) -> void:
	alive = is_alive
	visible = is_alive
	if is_alive:
		collision_layer = 2
		global_position = pos
		snapshots.clear()
	else:
		collision_layer = 0
		FX.burst(global_position, color, 32, 12.0, 0.5)
		AudioManager.play("enemy_die", 0.7)


@rpc("any_peer", "call_remote", "reliable")
func receive_hit(amount: float, attacker_name: String, knock: float) -> void:
	var attacker = get_parent().get_node_or_null(attacker_name)
	if attacker != null:
		take_hit(amount, attacker, knock)


@rpc("any_peer", "call_remote", "reliable")
func add_ko() -> void:
	kos += 1


@rpc("any_peer", "call_remote", "reliable")
func show_hit_effects_everywhere(amount: float) -> void:
	show_hit_effects(amount)


@rpc("any_peer", "call_remote", "reliable")
func show_wave_effects_everywhere() -> void:
	show_wave_effects()


# =====================================================================
#  CREIERUL BOTULUI
# =====================================================================
func bot_decide(delta: float) -> Vector2:
	bot_think_timer -= delta
	var target_gone: bool = bot_target == null or not is_instance_valid(bot_target) or not bot_target.alive
	if bot_think_timer <= 0.0 or target_gone:
		bot_think_timer = randf_range(0.6, 1.4)
		bot_target = closest_living_frog()
	var direction := Vector3.ZERO
	if bot_target != null:
		direction = bot_target.global_position - global_position
		# când urcă, țintește puțin în fața țintei (ca să aterizeze pe ea)
		if velocity.y > 2.0:
			direction += Vector3(bot_target.velocity.x, 0, bot_target.velocity.z) * 0.3
	direction.y = 0.0
	# nu te apropia de margine
	var from_center := global_position - arena_center
	from_center.y = 0.0
	if from_center.length() > arena_radius - 4.0:
		direction = -from_center
	# încearcă un Perfect Bounce (boții nu sunt perfecți)
	var falling_near_floor := velocity.y < -2.0 and global_position.y - arena_center.y < 1.6
	if falling_near_floor and randf() < bot_skill * 0.25:
		brace()
	var flat := Vector2(direction.x, direction.z)
	if flat.length() < 1.2:
		return Vector2.ZERO
	return flat.normalized() * (0.75 + bot_skill * 0.25)


func closest_living_frog():
	var closest = null
	var best_distance := 1e9
	for frog in others:
		if frog != self and frog.alive:
			var distance: float = global_position.distance_to(frog.global_position)
			if distance < best_distance:
				best_distance = distance
				closest = frog
	return closest
