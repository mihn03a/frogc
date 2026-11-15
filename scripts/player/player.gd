extends CharacterBody3D
## =====================================================================
##  PLAYER.GD - broasca-avion controlată de jucător
## =====================================================================
##  Ideea principală: broasca sare (bounce) din orice suprafață atinge.
##
##  Moduri de joc:
##   "run"       - în niveluri: zboară singură înainte (axa -Z).
##                 A/D = stânga/dreapta, W = planare, S = picaj.
##   "arena"     - în lupta cu boss-ul: WASD mișcă broasca (W = spre boss).
##   "cinematic" - broasca nu mai poate fi controlată (final de nivel).
##
##  SPACE = "bounce brace". Dacă apeși chiar înainte de impact -> PERFECT BOUNCE.
##  SHIFT = "turbo hop" (doar de la evoluția 4).
## =====================================================================

# Semnale: alte scripturi (HUD, nivel) le "ascultă" ca să afle ce s-a întâmplat.
signal bounced(perfect: bool)      # broasca a sărit (perfect sau nu)
signal bounced_on(body: Object)    # pe ce obiect a sărit
signal died                        # broasca a murit

const PlayerModel = preload("res://scripts/player/player_model.gd")

# ---------------------------------------------------------------- constante
# Fizica
const GRAVITY := 26.0          # cât de repede cade broasca
const GLIDE_LIFT := 20.0       # cât reduce gravitația planarea (W)
const DIVE_PULL := 24.0        # cât adaugă picajul (S)
const BASE_SPEED := 17.0       # viteza înainte
const SIDE_SPEED := 15.5       # viteza stânga-dreapta
const MAX_FALL := 32.0         # viteza maximă de cădere
const GLIDE_FALL := 6.5        # viteza maximă de cădere când planezi
# Săriturile
const BOUNCE_UP := 14.0        # săritură normală
const PERFECT_UP := 20.0       # săritură perfectă
const PAD_UP := 30.0           # săritură de pe trambulina roz
# Timpi
const COMBO_TIMEOUT := 3.5     # secunde fără săritură până se pierde combo-ul
const LATE_PRESS_GRACE := 0.08 # cât de târziu poți apăsa SPACE și tot e Perfect
# Damage la căderea în apă / lavă, pe niveluri (1..5)
const FLOOR_DAMAGE := [10.0, 13.0, 16.0, 20.0, 24.0]
# Power-up-uri: cât durează (secunde), cum se numesc și ce culoare au
const POWERUP_TIME := {"shield": 8.0, "super": 8.0, "speed": 6.0, "magnet": 10.0}
const POWERUP_NAMES := {"shield": "SHIELD", "super": "SUPER BOUNCE", "speed": "SPEED BOOST", "magnet": "MAGNET"}
const POWERUP_COLORS := {"shield": Color(0.3, 0.9, 1.0), "super": Color(1.0, 0.6, 0.1), "speed": Color(1.0, 0.25, 0.3), "magnet": Color(0.8, 0.35, 1.0)}

# ---------------------------------------------------------------- variabile publice
var mode := "run"                  # "run", "arena" sau "cinematic"
var arena_center := Vector3.ZERO   # centrul arenei boss-ului
var boss: Node3D = null            # boss-ul (doar în arenă)
var model                          # modelul 3D al broaștei
var camera: Camera3D
var momentum := 0.0                # 0..1, crește cu săriturile și dă viteză
var invuln := 0.0                  # secunde de invulnerabilitate rămase
var powerups := {"shield": 0.0, "super": 0.0, "speed": 0.0, "magnet": 0.0}  # timp rămas
var time_to_impact := -1.0         # secunde până la impact (pentru inelul din HUD)
var impact_is_danger := false      # urmează să atingem apă / lavă / un pericol?
var dead := false

# ---------------------------------------------------------------- variabile interne
var clock := 0.0                   # ceas propriu (secunde de la start)
var input_dir := Vector2.ZERO      # direcția apăsată pe tastatură
var last_brace_time := -10.0       # când s-a apăsat ultima dată SPACE
var last_bounce_time := -10.0      # când a avut loc ultima săritură
var last_bounce_pos := Vector3.ZERO
var can_upgrade_to_perfect := false  # pentru apăsarea puțin întârziată
var score_cooldown := 0.0          # ca să nu primești puncte de 2 ori la aceeași săritură
var combo_timer := 0.0
var comeback_timer := 0.0          # bonus dacă sari repede după ce ai fost lovit
var turbo_cooldown := 0.0
var respawn_point := Vector3.ZERO  # ultima platformă pe care ai aterizat
# Obiecte vizuale
var yaw_node: Node3D               # rotește modelul (în arenă)
var shield_mesh: MeshInstance3D
var super_ring: MeshInstance3D
var magnet_ring: MeshInstance3D
var speed_trail: GPUParticles3D
var landing_marker: MeshInstance3D
var marker_green: StandardMaterial3D
var marker_red: StandardMaterial3D


# =====================================================================
#  PORNIRE
# =====================================================================
func _ready() -> void:
	add_to_group("player")
	setup_collision()
	create_model()
	create_camera()
	create_powerup_visuals()
	create_landing_marker()
	GameState.set_hp(GameState.hp)
	respawn_point = global_position


func setup_collision() -> void:
	collision_layer = 2          # stratul 2 = jucătorul
	collision_mask = 1 | 4       # se lovește de lume (1) și de inamici (3 -> valoarea 4)
	var shape := SphereShape3D.new()
	shape.radius = 0.95
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)


func create_model() -> void:
	yaw_node = Node3D.new()
	add_child(yaw_node)
	model = PlayerModel.new()
	yaw_node.add_child(model)
	model.build(GameState.stage())   # evoluția depinde de nivel


func create_camera() -> void:
	camera = Camera3D.new()
	camera.top_level = true          # camera nu se rotește odată cu broasca
	camera.fov = 72.0
	camera.far = 1200.0
	add_child(camera)
	camera.current = true
	camera.global_position = global_position + Vector3(0, 5, 11)


func create_powerup_visuals() -> void:
	shield_mesh = FX.add_mesh(self, FX.sphere_mesh(1.9, 20), FX.mat(Color(0.3, 0.9, 1.0), 1.5, 0.0, 0.2, 0.25))
	super_ring = FX.add_mesh(self, FX.torus_mesh(1.7, 2.0, 28), FX.mat(Color(1.0, 0.6, 0.1), 3.0), Vector3(0, -1.0, 0))
	magnet_ring = FX.add_mesh(self, FX.torus_mesh(2.3, 2.45, 28), FX.mat(Color(0.8, 0.35, 1.0), 3.0))
	shield_mesh.visible = false
	super_ring.visible = false
	magnet_ring.visible = false
	speed_trail = FX.make_emitter(Color(1.0, 0.95, 0.6), 60, 0.45, Vector3(0, 0, 1), 12.0, 0.5, 1.5, Vector3.ZERO, 0.3)
	speed_trail.position = Vector3(0, 0, 1.2)
	add_child(speed_trail)
	speed_trail.emitting = false


func create_landing_marker() -> void:
	# Cercul de sub broască: verde deasupra platformei, roșu deasupra pericolului.
	marker_green = FX.mat(Color(0.2, 1.0, 0.4), 1.5, 0.0, 1.0, 0.45)
	marker_red = FX.mat(Color(1.0, 0.15, 0.1), 1.5, 0.0, 1.0, 0.45)
	landing_marker = FX.add_mesh(self, FX.cyl_mesh(1.0, 1.0, 0.05, 20), marker_green)
	landing_marker.top_level = true


# =====================================================================
#  BUCLA PRINCIPALĂ (rulează de 60 de ori pe secundă)
# =====================================================================
func _physics_process(delta: float) -> void:
	if dead or mode == "cinematic":
		update_camera(delta)
		return
	clock += delta
	update_timers(delta)
	read_input()
	if mode == "run":
		move_in_level(delta)
	else:
		move_in_arena(delta)
	move_and_check_collision(delta)
	predict_impact()
	update_visuals(delta)
	update_camera(delta)


func read_input() -> void:
	input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Input.is_action_just_pressed("bounce"):
		press_bounce_button()
	if Input.is_action_just_pressed("turbo"):
		try_turbo()


func move_and_check_collision(delta: float) -> void:
	# move_and_collide mută broasca și ne spune dacă a lovit ceva.
	var collision := move_and_collide(velocity * delta)
	if collision != null:
		handle_collision(collision)


# =====================================================================
#  MIȘCARE
# =====================================================================
func move_in_level(delta: float) -> void:
	# 1) Viteza înainte (crește cu momentum-ul și cu Speed Boost)
	var forward_speed := BASE_SPEED + momentum * 12.0 + (GameState.stage() - 1) * 0.8
	var side_speed := SIDE_SPEED
	if has_powerup("speed"):
		forward_speed += 12.0
		side_speed *= 1.25
	velocity.z = move_toward(velocity.z, -forward_speed, 30.0 * delta)
	# 2) Stânga / dreapta
	velocity.x = move_toward(velocity.x, input_dir.x * side_speed, 60.0 * delta)
	# 3) Gravitație, planare (W) și picaj (S)
	var gravity := GRAVITY
	var max_fall := MAX_FALL
	if input_dir.y < -0.1:              # W apăsat
		gravity -= GLIDE_LIFT * -input_dir.y
		max_fall = GLIDE_FALL
	elif input_dir.y > 0.1:             # S apăsat
		gravity += DIVE_PULL * input_dir.y
	velocity.y -= gravity * delta
	# 4) Limite: nu cădea prea repede, nu urca prea sus
	if velocity.y < -max_fall:
		velocity.y = move_toward(velocity.y, -max_fall, 70.0 * delta)
	velocity.y = minf(velocity.y, 34.0)
	if global_position.y > 40.0 and velocity.y > 0.0:
		velocity.y *= 0.9


func move_in_arena(delta: float) -> void:
	var forward := direction_to_boss()
	var right := forward.cross(Vector3.UP)
	var speed := 15.0
	if has_powerup("speed"):
		speed *= 1.35
	var wanted := (right * input_dir.x - forward * input_dir.y) * speed
	velocity.x = move_toward(velocity.x, wanted.x, 45.0 * delta)
	velocity.z = move_toward(velocity.z, wanted.z, 45.0 * delta)
	velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL)


func direction_to_boss() -> Vector3:
	var target := arena_center
	if boss != null and is_instance_valid(boss):
		target = boss.global_position
	var dir := target - global_position
	dir.y = 0.0
	if dir.length() < 0.5:
		return Vector3.FORWARD
	return dir.normalized()


# =====================================================================
#  COLIZIUNI - ce se întâmplă când broasca atinge ceva
# =====================================================================
func handle_collision(collision: KinematicCollision3D) -> void:
	var other = collision.get_collider()
	var normal := collision.get_normal()     # direcția perpendiculară pe suprafață
	var point := collision.get_position()
	if other == null:
		return
	if other.is_in_group("enemy"):
		hit_enemy(other, normal, point)
		return
	if other.is_in_group("boss"):
		hit_boss(other, normal, point)
		return
	# Fiecare obiect din nivel are o etichetă "kind" care spune ce tip e.
	var kind := str(other.get_meta("kind", "solid"))
	if kind == "hazard":
		touch_hazard(other, normal)
	elif kind == "floor_hazard":
		fall_in_water_or_lava(point)
	elif kind == "pad":
		bounce(normal, point, other, PAD_UP)
	else:
		bounce(normal, point, other, 0.0)


func touch_hazard(hazard, normal: Vector3) -> void:
	var damage := float(hazard.get_meta("damage", 15.0))
	take_damage(damage, normal)
	velocity = velocity.bounce(normal) * 0.6 + normal * 12.0 + Vector3.UP * 6.0


func fall_in_water_or_lava(point: Vector3) -> void:
	FX.burst(point, Color(1.0, 0.8, 0.3), 30, 10.0, 0.4)
	if is_braced():
		perfect_splash()
		return
	# Căderea e o greșeală serioasă: damage mare, pierzi viteza și combo-ul
	# și te întorci la ultima platformă.
	take_damage(FLOOR_DAMAGE[GameState.stage() - 1], Vector3.UP, true)
	if dead:
		return
	if mode == "arena":
		global_position = arena_center + Vector3(0, 6, 10)
		velocity = Vector3(0, 8, 0)
	else:
		global_position = respawn_point
		velocity = Vector3(0, 2, -3)
	momentum = 0.0
	GameState.reset_combo()
	combo_timer = 0.0
	invuln = maxf(invuln, 1.5)
	GameState.show_message.emit("SPLASH! BACK TO THE LAST PLATFORM", Color(1.0, 0.6, 0.4))


func perfect_splash() -> void:
	# BOUNCE BACK: ai apăsat SPACE chiar înainte să atingi apa / lava.
	# Iei doar jumătate din damage, îți păstrezi combo-ul și sari înapoi în sus
	# chiar din locul unde ai căzut (nu te mai întorci la ultima platformă).
	last_brace_time = -10.0
	var saved_combo := GameState.combo
	take_damage(FLOOR_DAMAGE[GameState.stage() - 1] * 0.5, Vector3.UP, true)
	if dead:
		return
	GameState.reset_combo()      # take_damage a șters combo-ul; îl punem la loc
	GameState.add_combo(saved_combo)
	combo_timer = COMBO_TIMEOUT
	comeback_timer = 0.0
	velocity.y = PAD_UP          # o săritură mare, ca de pe trambulină
	global_position.y += 0.5
	invuln = maxf(invuln, 1.0)
	AudioManager.play("perfect")
	FX.burst(global_position, Color(0.3, 1.0, 0.9), 32, 12.0, 0.45, -2.0)
	FX.flash(Color(0.6, 1.0, 1.0), 0.22)
	GameState.show_message.emit("PERFECT SPLASH! BOUNCE BACK!", Color(0.3, 1.0, 0.9))


# =====================================================================
#  SĂRITURA (BOUNCE)
# =====================================================================
func bounce(normal: Vector3, point: Vector3, other, force_up: float) -> void:
	# Cât de tare "intră" broasca în suprafață (negativ = spre suprafață).
	var into_surface := velocity.dot(normal)
	if into_surface > -1.0 and force_up == 0.0:
		slide_along(normal, into_surface)
		return
	var perfect := is_braced()
	reflect_velocity(normal, into_surface)
	var hit_side := apply_bounce_direction(normal, other, force_up, perfect)
	if score_cooldown > 0.0:
		return
	score_cooldown = 0.15
	reward_bounce(point, perfect, force_up > 0.0, hit_side)
	last_bounce_time = clock
	last_bounce_pos = point
	if perfect:
		last_brace_time = -10.0
		can_upgrade_to_perfect = false
		perfect_bounce_effects(point)
	else:
		can_upgrade_to_perfect = true
		bounced.emit(false)
	bounced_on.emit(other)


func slide_along(normal: Vector3, into_surface: float) -> void:
	# Atingere ușoară: doar oprim mișcarea spre suprafață (alunecă pe ea).
	if into_surface < 0.0:
		velocity -= normal * into_surface


func reflect_velocity(normal: Vector3, into_surface: float) -> void:
	# Reflexia vitezei față de suprafață (ca o minge).
	# Factorul 1.85 = broasca păstrează 85% din viteză după ricoșeu.
	velocity -= 1.85 * into_surface * normal


func apply_bounce_direction(normal: Vector3, other, force_up: float, perfect: bool) -> bool:
	var power := bounce_power()
	if normal.y > 0.45:
		# Am aterizat PE o suprafață -> sărim în sus
		remember_platform(other)
		var up := BOUNCE_UP
		if perfect:
			up = PERFECT_UP
		if force_up > 0.0:
			up = force_up
			if perfect:
				up = force_up * 1.15
		velocity.y = maxf(velocity.y, up * power)
		return false
	if normal.y < -0.45:
		# Am lovit ceva cu capul -> coborâm
		velocity.y = minf(velocity.y, -4.0)
		return false
	# Am lovit ceva din lateral -> ne împinge înapoi
	velocity += normal * 6.0 * power
	if mode == "run" and normal.z > 0.5:
		velocity.y = maxf(velocity.y, 11.0 * power)   # din față: sărim peste
	return true


func bounce_power() -> float:
	var power := GameState.bounce_power()
	if has_powerup("super"):
		power *= 1.5
	return power


func remember_platform(other) -> void:
	# Salvăm platforma ca loc de întoarcere dacă broasca pică.
	if other == null:
		return
	var kind := str(other.get_meta("kind", ""))
	if kind == "solid" or kind == "pad" or kind == "unstable":
		respawn_point = (other as Node3D).global_position + Vector3(0, 4.0, 0)


func reward_bounce(point: Vector3, perfect: bool, from_pad: bool, hit_side: bool) -> void:
	# Puncte, combo, momentum, sunet și efecte pentru o săritură.
	if perfect:
		momentum = minf(momentum + 0.18, 1.0)
	else:
		momentum = minf(momentum + 0.07, 1.0)
	GameState.add_combo(1)
	combo_timer = COMBO_TIMEOUT
	var points := GameState.add_score(60 if from_pad else 50)
	GameState.add_evo(1)
	GameState.on_bounce()
	points += check_comeback_bonus()
	FX.popup(point + Vector3.UP, "+%d" % points, Color(1.0, 1.0, 0.45), 56)
	var color := Color(0.6, 1.0, 0.4)
	if has_powerup("super"):
		color = POWERUP_COLORS["super"]
	FX.burst(point, color, 18, 7.0, 0.3)
	var pitch := 1.0 + minf(GameState.combo, 25) * 0.025   # sunetul urcă odată cu combo-ul
	if hit_side:
		AudioManager.play("wall", pitch)
	else:
		AudioManager.play("bounce", pitch)
	FX.shake(0.12)
	model.squash()


func check_comeback_bonus() -> int:
	# Dacă sari la scurt timp după ce ai fost lovit -> bonus "Comeback".
	if comeback_timer <= 0.0:
		return 0
	comeback_timer = 0.0
	GameState.on_comeback()
	GameState.show_message.emit("COMEBACK BOUNCE! +300", Color(0.5, 1.0, 0.5))
	return GameState.add_score(300)


# =====================================================================
#  PERFECT BOUNCE
# =====================================================================
func press_bounce_button() -> void:
	last_brace_time = clock
	model.squash()
	# Corectitudine: dacă ai apăsat foarte puțin DUPĂ impact, tot e Perfect.
	if can_upgrade_to_perfect and clock - last_bounce_time <= LATE_PRESS_GRACE:
		can_upgrade_to_perfect = false
		last_brace_time = -10.0
		velocity.y += 6.0
		perfect_bounce_effects(last_bounce_pos)


func is_braced() -> bool:
	# Adevărat dacă SPACE a fost apăsat de curând (în fereastra Perfect).
	return clock - last_brace_time <= GameState.perfect_window()


func perfect_bounce_effects(point: Vector3) -> void:
	GameState.perfect_count += 1
	GameState.on_perfect()
	GameState.add_combo(1)
	var points := GameState.add_score(250)
	GameState.add_evo(3)
	invuln = maxf(invuln, 0.8)
	momentum = minf(momentum + 0.1, 1.0)
	GameState.show_message.emit("PERFECT BOUNCE!", Color(0.3, 1.0, 0.9))
	FX.burst(point, Color(0.3, 1.0, 0.9), 32, 12.0, 0.45, -2.0)
	FX.burst(point, Color(1, 1, 1), 24, 15.0, 0.2, 0.0)
	FX.flash(Color(0.6, 1.0, 1.0), 0.22)
	FX.shake(0.25)
	FX.popup(point + Vector3(0, 2.2, 0), "PERFECT +%d" % points, Color(0.4, 1.0, 1.0), 80)
	AudioManager.play("perfect")
	if GameState.stage() >= 5:
		plasma_shockwave()
	bounced.emit(true)


func plasma_shockwave() -> void:
	# Abilitatea de la evoluția 5: Perfect Bounce distruge inamicii din jur.
	FX.burst(global_position, Color(1.0, 0.3, 1.0), 32, 20.0, 0.5, 0.0)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var enemy3d := enemy as Node3D
		if enemy3d != null and enemy3d.global_position.distance_to(global_position) < 13.0:
			enemy3d.call("defeat")


# =====================================================================
#  INAMICI, BOSS, PROIECTILE
# =====================================================================
func hit_enemy(enemy, normal: Vector3, point: Vector3) -> void:
	var landed_on_top := normal.y > 0.45
	if landed_on_top or is_braced() or has_powerup("super"):
		enemy.defeat()
		if landed_on_top:
			bounce(normal, point, null, 0.0)
		else:
			bounce((normal + Vector3.UP).normalized(), point, null, 0.0)
	else:
		take_damage(float(enemy.get("contact_damage")), normal)
		velocity = normal * 14.0 + Vector3.UP * 8.0


func hit_boss(the_boss, normal: Vector3, point: Vector3) -> void:
	if normal.y > 0.45:
		# Am aterizat pe capul boss-ului: îi luăm viață
		var damage := 8.0
		if is_braced():
			damage = 14.0
		the_boss.take_hit(damage, point)
		bounce(normal, point, null, 24.0)
		var away := global_position - (the_boss as Node3D).global_position
		away.y = 0.0
		velocity += away.normalized() * 9.0
	else:
		take_damage(15.0, normal)
		velocity = normal * 16.0 + Vector3.UP * 8.0


## Apelată de proiectile. Întoarce true dacă proiectilul a fost trimis înapoi.
func try_reflect() -> bool:
	if dead:
		return false
	if is_braced():
		last_brace_time = -10.0
		GameState.show_message.emit("BOUNCED BACK!", Color(0.4, 1.0, 0.6))
		AudioManager.play("reflect")
		perfect_bounce_effects(global_position)
		return true
	if has_powerup("super"):
		AudioManager.play("reflect")
		GameState.add_score(100)
		return true
	return false


# =====================================================================
#  VIAȚĂ ȘI DAMAGE
# =====================================================================
func take_damage(amount: float, from_dir: Vector3 = Vector3.UP, ignore_invuln: bool = false) -> bool:
	if dead or mode == "cinematic":
		return false
	if invuln > 0.0 and not ignore_invuln:
		return false
	if has_powerup("shield"):
		block_with_shield()
		return false
	var real_damage := amount * GameState.armor() * GameState.damage_mult()
	GameState.set_hp(GameState.hp - real_damage)
	GameState.damage_this_level = true
	invuln = 1.3
	GameState.reset_combo()
	combo_timer = 0.0
	comeback_timer = 2.5                         # ai 2,5 s pentru bonusul Comeback
	momentum = minf(momentum + 0.15, 1.0)        # lovitura îți dă și viteză
	play_hurt_effects()
	if from_dir.length() > 0.1:
		velocity += from_dir.normalized() * 4.0
	if GameState.hp <= 0.0:
		die()
	else:
		GameState.show_message.emit("OUCH! BOUNCE BACK!", Color(1.0, 0.55, 0.4))
	return true


func block_with_shield() -> void:
	AudioManager.play("wall")
	FX.burst(global_position, POWERUP_COLORS["shield"], 24, 9.0)
	FX.popup(global_position + Vector3.UP * 2.0, "BLOCKED!", POWERUP_COLORS["shield"])
	invuln = 0.4


func play_hurt_effects() -> void:
	AudioManager.play("damage")
	FX.shake(0.5)
	FX.flash(Color(1.0, 0.15, 0.1), 0.35)
	FX.burst(global_position, Color(1.0, 0.3, 0.2), 24, 8.0)
	model.hurt(1.3)


func die() -> void:
	dead = true
	velocity = Vector3.ZERO
	model.pose = "sad"
	model.set_expression("sad")
	AudioManager.stop_music()
	Engine.time_scale = 0.35          # slow motion
	died.emit()
	await get_tree().create_timer(0.9, true, false, true).timeout
	GameState.on_player_died()       # trece la ecranul Game Over


# =====================================================================
#  POWER-UP-URI ȘI TURBO
# =====================================================================
func has_powerup(kind: String) -> bool:
	return powerups[kind] > 0.0


func activate_powerup(kind: String) -> void:
	if not powerups.has(kind):
		return
	powerups[kind] = POWERUP_TIME[kind]
	GameState.on_powerup(kind)
	AudioManager.play("pu_" + kind)
	GameState.show_message.emit(str(POWERUP_NAMES[kind]) + "!", POWERUP_COLORS[kind])
	FX.burst(global_position, POWERUP_COLORS[kind], 32, 10.0, 0.4, 0.0)
	FX.flash(POWERUP_COLORS[kind], 0.2)


func powerup_ended(kind: String) -> void:
	AudioManager.play("pu_end")
	FX.popup(global_position + Vector3.UP * 2.0, str(POWERUP_NAMES[kind]) + " ENDED", Color(0.8, 0.8, 0.8), 40)


func try_turbo() -> void:
	if GameState.stage() < 4 or turbo_cooldown > 0.0:
		return
	turbo_cooldown = 2.5
	velocity.y = maxf(velocity.y, 17.0)
	AudioManager.play("turbo")
	FX.burst(global_position - Vector3(0, 1, 0), Color(1.0, 0.6, 0.2), 24, 8.0, 0.35)


func turbo_ready() -> bool:
	return GameState.stage() >= 4 and turbo_cooldown <= 0.0


func combo_time_left() -> float:
	return clampf(combo_timer / COMBO_TIMEOUT, 0.0, 1.0)


# =====================================================================
#  CRONOMETRE (scad în fiecare cadru)
# =====================================================================
func update_timers(delta: float) -> void:
	invuln = maxf(invuln - delta, 0.0)
	score_cooldown -= delta
	turbo_cooldown = maxf(turbo_cooldown - delta, 0.0)
	comeback_timer = maxf(comeback_timer - delta, 0.0)
	momentum = maxf(momentum - delta * 0.04, 0.0)
	update_combo_timer(delta)
	update_powerup_timers(delta)


func update_combo_timer(delta: float) -> void:
	if combo_timer <= 0.0:
		return
	combo_timer -= delta
	if combo_timer <= 0.0:
		GameState.reset_combo()


func update_powerup_timers(delta: float) -> void:
	for kind in powerups.keys():
		if powerups[kind] > 0.0:
			powerups[kind] -= delta
			if powerups[kind] <= 0.0:
				powerups[kind] = 0.0
				powerup_ended(kind)


# =====================================================================
#  INELUL DE TIMING ȘI MARCAJUL DE ATERIZARE (raycast)
# =====================================================================
func cast_ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	# Trimite o "rază" invizibilă și întoarce ce a lovit (sau {} dacă nimic).
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


func predict_impact() -> void:
	# Câte secunde mai sunt până lovim ceva pe direcția de mers?
	var speed := velocity.length()
	impact_is_danger = false
	if speed < 1.0:
		time_to_impact = -1.0
		return
	var hit := cast_ray(global_position, global_position + velocity * 0.75, 1 | 4)
	if hit.is_empty():
		time_to_impact = -1.0
		return
	var hit_point: Vector3 = hit["position"]
	var distance := global_position.distance_to(hit_point) - 0.95
	time_to_impact = maxf(distance / speed, 0.0)
	var kind := str(hit["collider"].get_meta("kind", "solid"))
	impact_is_danger = kind == "floor_hazard" or kind == "hazard"


func update_landing_marker() -> void:
	var hit := cast_ray(global_position, global_position + Vector3.DOWN * 60.0, 1)
	if hit.is_empty():
		landing_marker.visible = false
		return
	landing_marker.visible = true
	var ground: Vector3 = hit["position"]
	landing_marker.global_position = ground + Vector3(0, 0.08, 0)
	var height := global_position.y - ground.y
	landing_marker.scale = Vector3.ONE * clampf(1.3 - height * 0.02, 0.5, 1.3)
	var kind := str(hit["collider"].get_meta("kind", "solid"))
	if kind == "floor_hazard" or kind == "hazard":
		landing_marker.material_override = marker_red
	else:
		landing_marker.material_override = marker_green


# =====================================================================
#  ASPECT (model, power-up-uri, urma de viteză)
# =====================================================================
func update_visuals(delta: float) -> void:
	if mode == "run":
		model.bank = input_dir.x       # se înclină în viraj
	else:
		model.bank = 0.0
	model.pitch = clampf(velocity.y / 20.0, -1.0, 1.0)
	model.set_blink(invuln > 0.0 and invuln < 1.25 and not has_powerup("shield"))
	if mode == "arena":
		var forward := direction_to_boss()
		yaw_node.rotation.y = lerp_angle(yaw_node.rotation.y, atan2(-forward.x, -forward.z), delta * 8.0)
	update_powerup_visuals()
	speed_trail.emitting = momentum > 0.4 or has_powerup("speed")
	update_landing_marker()


func update_powerup_visuals() -> void:
	shield_mesh.visible = has_powerup("shield")
	shield_mesh.scale = Vector3.ONE * (1.0 + sin(clock * 8.0) * 0.04)
	super_ring.visible = has_powerup("super")
	super_ring.scale = Vector3.ONE * (1.0 + sin(clock * 12.0) * 0.12)
	magnet_ring.visible = has_powerup("magnet")
	magnet_ring.rotation = Vector3(sin(clock * 2.0) * 0.6, clock * 4.0, 0)


# =====================================================================
#  CAMERA
# =====================================================================
func update_camera(delta: float) -> void:
	var look_at_point: Vector3
	if mode == "arena":
		look_at_point = place_camera_in_arena(delta)
	else:
		look_at_point = place_camera_in_level(delta)
	add_camera_shake(look_at_point)
	# câmp vizual mai larg când mergi repede
	var speed_ratio := clampf(velocity.length() / 45.0, 0.0, 1.0)
	camera.fov = lerpf(camera.fov, 70.0 + 20.0 * speed_ratio, delta * 3.0)


func place_camera_in_level(delta: float) -> Vector3:
	# Camera stă în spatele și deasupra broaștei.
	var target := global_position + Vector3(0, 4.5, 11.0)
	var smooth := 1.0 - exp(-delta * 5.0)
	var pos := camera.global_position
	pos.x = lerpf(pos.x, target.x * 0.8, smooth)
	pos.y = lerpf(pos.y, target.y, smooth)
	pos.z = target.z
	camera.global_position = pos
	return global_position + Vector3(0, 1.0, -8.0)


func place_camera_in_arena(delta: float) -> Vector3:
	# Camera stă în spatele broaștei și privește spre boss.
	var behind := -direction_to_boss()
	var target := global_position + behind * 12.0 + Vector3.UP * 6.5
	camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-delta * 5.0))
	var focus := arena_center
	if boss != null and is_instance_valid(boss):
		focus = boss.global_position
	return global_position.lerp(focus, 0.45)


func add_camera_shake(look_at_point: Vector3) -> void:
	var strength := FX.trauma * FX.trauma
	var offset := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * strength * 0.9
	camera.global_position += offset * 0.5
	if camera.global_position.distance_to(look_at_point + offset) > 0.1:
		camera.look_at(look_at_point + offset, Vector3.UP)


# =====================================================================
#  APELATE DIN ALTE SCRIPTURI
# =====================================================================
func enter_arena(center: Vector3, boss_node: Node3D) -> void:
	mode = "arena"
	arena_center = center
	boss = boss_node


func start_cinematic() -> void:
	mode = "cinematic"
	velocity = Vector3.ZERO
